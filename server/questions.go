package main

import (
	"hash/fnv"
	"net/http"
	"time"
	"unicode/utf8"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

// questionLookback bounds how much of a couple's question_days history we
// scan to avoid repeating a recently-used prompt. The pack is small (~60
// entries) — once a couple has answered more days than that, some repeat is
// inevitable and that's fine.
const questionLookback = 45

// todayDate returns the current UTC date as YYYY-MM-DD. The feature runs on
// one shared server-clock day rather than each partner's local timezone, so
// "today's question" always names the same question_days row for both —
// deliberately simple for v1; a per-couple local-day boundary can come
// later if the UTC cutover ever actually bites someone.
func todayDate() string {
	return time.Now().UTC().Format("2006-01-02")
}

// pickQuestion deterministically chooses a pack entry for coupleID+date:
// hashing the pair seeds the pick so it's stable without a round-trip or
// stored "current index" state, then linear-probes forward past anything
// in recentEN so the couple doesn't see the same prompt twice in quick
// succession while the pack still has fresh entries left.
func pickQuestion(coupleID, date string, recentEN map[string]bool) QuestionPackEntry {
	h := fnv.New32a()
	_, _ = h.Write([]byte(coupleID + date))
	start := int(h.Sum32() % uint32(len(questionPack)))

	for i := 0; i < len(questionPack); i++ {
		candidate := questionPack[(start+i)%len(questionPack)]
		if !recentEN[candidate.EN] {
			return candidate
		}
	}
	// Every entry was used recently (small pack, long history) — recycle.
	return questionPack[start]
}

// getOrCreateQuestionDay fetches (or, on the first ask for a given
// couple+date, creates) that day's question_days row. Both partners' apps
// may call this at roughly the same moment on a fresh day; the
// (couple,date) unique index (migrations/9_questions.go) makes the loser of
// that race fail its Save, and we just re-fetch the winner's row instead of
// erroring — the couple always converges on one question per day.
func getOrCreateQuestionDay(app core.App, coupleID, date string) (*core.Record, error) {
	existing, err := app.FindFirstRecordByFilter(
		"question_days",
		"couple = {:couple} && date = {:date}",
		dbx.Params{"couple": coupleID, "date": date},
	)
	if err == nil {
		return existing, nil
	}

	recent, err := app.FindRecordsByFilter(
		"question_days",
		"couple = {:couple}",
		"-date", questionLookback, 0,
		dbx.Params{"couple": coupleID},
	)
	if err != nil {
		return nil, err
	}
	recentEN := make(map[string]bool, len(recent))
	for _, r := range recent {
		recentEN[r.GetString("question_en")] = true
	}

	q := pickQuestion(coupleID, date, recentEN)

	col, err := app.FindCollectionByNameOrId("question_days")
	if err != nil {
		return nil, err
	}
	day := core.NewRecord(col)
	day.Set("couple", coupleID)
	day.Set("date", date)
	day.Set("question_en", q.EN)
	day.Set("question_pl", q.PL)
	if err := app.Save(day); err != nil {
		again, ferr := app.FindFirstRecordByFilter(
			"question_days",
			"couple = {:couple} && date = {:date}",
			dbx.Params{"couple": coupleID, "date": date},
		)
		if ferr != nil {
			return nil, err
		}
		return again, nil
	}
	return day, nil
}

// findAnswer looks up the (day,user) answer row, if any.
func findAnswer(app core.App, dayID, userID string) (*core.Record, bool) {
	rec, err := app.FindFirstRecordByFilter(
		"answers",
		"day = {:day} && user = {:user}",
		dbx.Params{"day": dayID, "user": userID},
	)
	if err != nil {
		return nil, false
	}
	return rec, true
}

// upsertAnswer creates or updates the caller's own answer row for dayID —
// editable any time (the design's "submit once, editable until both
// answered" is a client-side courtesy; nothing server-side needs to lock it
// once both have answered, since the blind is about *reading* the
// partner's answer, not about freezing your own).
func upsertAnswer(app core.App, coupleID, dayID, userID, text string) error {
	if existing, ok := findAnswer(app, dayID, userID); ok {
		existing.Set("text", text)
		return app.Save(existing)
	}

	col, err := app.FindCollectionByNameOrId("answers")
	if err != nil {
		return err
	}
	rec := core.NewRecord(col)
	rec.Set("couple", coupleID)
	rec.Set("day", dayID)
	rec.Set("user", userID)
	rec.Set("text", text)
	if err := app.Save(rec); err != nil {
		// Lost a race against our own duplicate concurrent request — the
		// (day,user) unique index rejected it; update the winner instead.
		if again, ok := findAnswer(app, dayID, userID); ok {
			again.Set("text", text)
			return app.Save(again)
		}
		return err
	}
	return nil
}

// partnerID returns the other member of coupleID, or "" if nobody else has
// joined yet.
func partnerID(app core.App, coupleID, selfID string) string {
	rec, err := app.FindFirstRecordByFilter(
		"users",
		"couple = {:couple} && id != {:self}",
		dbx.Params{"couple": coupleID, "self": selfID},
	)
	if err != nil {
		return ""
	}
	return rec.Id
}

// questionToday is GET /api/question/today: get-or-creates today's
// question and returns it plus the caller's own answer and — the blind —
// the partner's answer, but ONLY once both partners have answered. That
// check happens here in trusted server code via direct App-level lookups,
// not by delegating to the answers collection's own API rules — belt and
// suspenders on top of the collection's own blindReveal rule (see
// migrations/9_questions.go): even if that rule were ever loosened, this
// route still never hands back a partner's answer early.
func questionToday(e *core.RequestEvent) error {
	coupleID := e.Auth.GetString("couple")
	if coupleID == "" {
		return e.BadRequestError("You need to be part of a couple first.", nil)
	}

	date := todayDate()
	day, err := getOrCreateQuestionDay(e.App, coupleID, date)
	if err != nil {
		return e.InternalServerError("Could not load today's question.", err)
	}

	var myAnswer any
	myRec, iAnswered := findAnswer(e.App, day.Id, e.Auth.Id)
	if iAnswered {
		myAnswer = myRec.GetString("text")
	}

	var partnerAnswer any
	bothAnswered := false
	if partner := partnerID(e.App, coupleID, e.Auth.Id); partner != "" && iAnswered {
		if pRec, ok := findAnswer(e.App, day.Id, partner); ok {
			partnerAnswer = pRec.GetString("text")
			bothAnswered = true
		}
	}

	return e.JSON(http.StatusOK, map[string]any{
		"date":           date,
		"question_en":    day.GetString("question_en"),
		"question_pl":    day.GetString("question_pl"),
		"my_answer":      myAnswer,
		"partner_answer": partnerAnswer,
		"both_answered":  bothAnswered,
	})
}

// questionAnswer is POST /api/question/answer {text}: upserts the caller's
// own answer for today's question.
func questionAnswer(e *core.RequestEvent) error {
	coupleID := e.Auth.GetString("couple")
	if coupleID == "" {
		return e.BadRequestError("You need to be part of a couple first.", nil)
	}

	body := struct {
		Text string `json:"text"`
	}{}
	if err := e.BindBody(&body); err != nil {
		return e.BadRequestError("Invalid request body.", err)
	}
	if body.Text == "" {
		return e.BadRequestError("An answer can't be empty.", nil)
	}
	if utf8.RuneCountInString(body.Text) > 1000 {
		return e.BadRequestError("Keep it under 1000 characters.", nil)
	}

	day, err := getOrCreateQuestionDay(e.App, coupleID, todayDate())
	if err != nil {
		return e.InternalServerError("Could not load today's question.", err)
	}

	if err := upsertAnswer(e.App, coupleID, day.Id, e.Auth.Id, body.Text); err != nil {
		return e.InternalServerError("Could not save your answer.", err)
	}

	return e.JSON(http.StatusOK, map[string]any{"ok": true})
}
