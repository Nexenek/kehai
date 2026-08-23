package main

import (
	"net/http"
	"testing"

	"github.com/pocketbase/dbx"
)

func getQuestionToday(t *testing.T, baseURL, token string) map[string]any {
	t.Helper()
	res := doJSON(t, http.MethodGet, baseURL+"/api/question/today", token, nil)
	body := decodeJSON(t, res)
	if res.StatusCode != http.StatusOK {
		t.Fatalf("GET /api/question/today: %d: %v", res.StatusCode, body)
	}
	return body
}

func postQuestionAnswer(t *testing.T, baseURL, token, text string) *http.Response {
	t.Helper()
	return doJSON(t, http.MethodPost, baseURL+"/api/question/answer", token, map[string]any{"text": text})
}

// --- get-or-create idempotency -------------------------------------------

func TestQuestionTodayGetOrCreateIdempotent(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	tokenA, _, coupleID := pairedCouple(t, srv.URL)

	first := getQuestionToday(t, srv.URL, tokenA)
	second := getQuestionToday(t, srv.URL, tokenA)

	if first["date"] != second["date"] {
		t.Fatalf("date changed between calls: %v vs %v", first["date"], second["date"])
	}
	if first["question_en"] != second["question_en"] {
		t.Fatalf("question changed between calls: %v vs %v", first["question_en"], second["question_en"])
	}
	if first["question_en"] == "" || first["question_pl"] == "" {
		t.Fatalf("expected non-empty bilingual question, got %v", first)
	}
	if first["both_answered"] != false {
		t.Fatalf("expected both_answered=false with nobody having answered, got %v", first["both_answered"])
	}
	if first["my_answer"] != nil || first["partner_answer"] != nil {
		t.Fatalf("expected nil answers before anyone answers, got my=%v partner=%v", first["my_answer"], first["partner_answer"])
	}

	// Exactly one question_days row exists for this couple — the
	// get-or-create didn't fork a second row on the repeat call.
	rows, err := app.FindRecordsByFilter("question_days", "couple = {:c}", "", 0, 0, dbx.Params{"c": coupleID})
	if err != nil {
		t.Fatalf("query question_days: %v", err)
	}
	if len(rows) != 1 {
		t.Fatalf("expected exactly 1 question_days row, got %d", len(rows))
	}
}

// A second, unrelated couple asking "today" on the same date must get a
// question, but there's no reason to expect it's a *different* one — pack
// index is a hash of (coupleId,date), so different couples routinely land
// on different entries but could coincide. The real invariant under test is
// that each couple gets its own row.
func TestQuestionTodaySeparateCouplesGetOwnRows(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	tokenA, _, coupleA := pairedCouple(t, srv.URL)
	tokenC, _, coupleB := pairedCouple(t, srv.URL)

	if coupleA == coupleB {
		t.Fatalf("test setup produced the same couple twice")
	}

	getQuestionToday(t, srv.URL, tokenA)
	getQuestionToday(t, srv.URL, tokenC)

	rowsA, _ := app.FindRecordsByFilter("question_days", "couple = {:c}", "", 0, 0, dbx.Params{"c": coupleA})
	rowsB, _ := app.FindRecordsByFilter("question_days", "couple = {:c}", "", 0, 0, dbx.Params{"c": coupleB})
	if len(rowsA) != 1 || len(rowsB) != 1 {
		t.Fatalf("expected 1 row per couple, got %d and %d", len(rowsA), len(rowsB))
	}
}

// --- answer upsert ---------------------------------------------------------

func TestQuestionAnswerUpsert(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	idA, tokenA, _, _, coupleID := pairedCoupleWithIDs(t, srv.URL)

	if res := postQuestionAnswer(t, srv.URL, tokenA, "pierogi, obviously"); res.StatusCode != http.StatusOK {
		t.Fatalf("first answer: %d", res.StatusCode)
	}
	got := getQuestionToday(t, srv.URL, tokenA)
	if got["my_answer"] != "pierogi, obviously" {
		t.Fatalf("expected my_answer to stick, got %v", got["my_answer"])
	}

	// Editing before the reveal upserts in place, not a second row.
	if res := postQuestionAnswer(t, srv.URL, tokenA, "actually, żurek"); res.StatusCode != http.StatusOK {
		t.Fatalf("second answer (edit): %d", res.StatusCode)
	}
	got = getQuestionToday(t, srv.URL, tokenA)
	if got["my_answer"] != "actually, żurek" {
		t.Fatalf("expected edited my_answer, got %v", got["my_answer"])
	}

	rows, err := app.FindRecordsByFilter(
		"answers", "couple = {:c} && user = {:u}", "", 0, 0,
		dbx.Params{"c": coupleID, "u": idA},
	)
	if err != nil {
		t.Fatalf("query answers: %v", err)
	}
	if len(rows) != 1 {
		t.Fatalf("expected exactly 1 answer row after 2 upserts, got %d", len(rows))
	}
}

func TestQuestionAnswerValidation(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	_, tokenA := registerAndLogin(t, srv.URL, uniqueEmail(t), "password1234")

	// Not in a couple yet.
	if res := postQuestionAnswer(t, srv.URL, tokenA, "hi"); res.StatusCode != http.StatusBadRequest {
		t.Fatalf("expected 400 answering without a couple, got %d", res.StatusCode)
	}

	res := doJSON(t, http.MethodPost, srv.URL+"/api/couple/create", tokenA, map[string]any{"name": "us"})
	res.Body.Close()

	if res := postQuestionAnswer(t, srv.URL, tokenA, ""); res.StatusCode != http.StatusBadRequest {
		t.Fatalf("expected 400 for an empty answer, got %d", res.StatusCode)
	}
}

// --- THE BLIND -------------------------------------------------------------

// TestBlindReveal is the hard test: partner answers must be invisible by
// every path — the /api/question/today route, direct collection list,
// direct view-by-id, and an expand off the question_days record — until
// BOTH partners have answered, at which point both paths open up for both
// of them.
func TestBlindReveal(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	idA, tokenA, _, tokenB, coupleID := pairedCoupleWithIDs(t, srv.URL)

	getQuestionToday(t, srv.URL, tokenA)
	dayRow, err := app.FindFirstRecordByFilter("question_days", "couple = {:c}", dbx.Params{"c": coupleID})
	if err != nil {
		t.Fatalf("find question_days row: %v", err)
	}

	// A answers. B has not.
	if res := postQuestionAnswer(t, srv.URL, tokenA, "the day we got the pet"); res.StatusCode != http.StatusOK {
		t.Fatalf("A answers: %d", res.StatusCode)
	}
	aAnswer, ok := app.FindRecordsByFilter("answers", "couple = {:c} && user = {:u}", "", 0, 0, dbx.Params{"c": coupleID, "u": idA})
	if ok != nil || len(aAnswer) != 1 {
		t.Fatalf("expected A's answer row to exist: err=%v rows=%v", ok, aAnswer)
	}
	aAnswerID := aAnswer[0].Id

	// Route: A sees their own answer, no partner_answer yet, not both_answered.
	gotA := getQuestionToday(t, srv.URL, tokenA)
	if gotA["my_answer"] != "the day we got the pet" || gotA["partner_answer"] != nil || gotA["both_answered"] != false {
		t.Fatalf("A's pre-reveal view leaked or was wrong: %v", gotA)
	}

	// Route: B sees no answers at all yet (B hasn't answered either).
	gotB := getQuestionToday(t, srv.URL, tokenB)
	if gotB["my_answer"] != nil || gotB["partner_answer"] != nil || gotB["both_answered"] != false {
		t.Fatalf("B's pre-answer view leaked A's answer: %v", gotB)
	}

	// Direct collection LIST as B: must not include A's answer.
	listRes := doJSON(t, http.MethodGet, srv.URL+"/api/collections/answers/records", tokenB, nil)
	listBody := decodeJSON(t, listRes)
	if got := listBody["totalItems"].(float64); got != 0 {
		t.Fatalf("blind broken: B's list shows %v answers before answering", got)
	}

	// Direct collection VIEW-BY-ID as B: must be refused, not just omitted.
	viewRes := doJSON(t, http.MethodGet, srv.URL+"/api/collections/answers/records/"+aAnswerID, tokenB, nil)
	defer viewRes.Body.Close()
	if viewRes.StatusCode == http.StatusOK {
		t.Fatalf("blind broken: B could view A's answer by id before answering (status %d)", viewRes.StatusCode)
	}

	// Expand trick: querying question_days with expand=answers_via_day as B
	// must not smuggle A's answer text through the expansion.
	expandRes := doJSON(t, http.MethodGet, srv.URL+"/api/collections/question_days/records/"+dayRow.Id+"?expand=answers_via_day", tokenB, nil)
	expandBody := decodeJSON(t, expandRes)
	if expandRes.StatusCode == http.StatusOK {
		if expand, ok := expandBody["expand"].(map[string]any); ok {
			if related, ok := expand["answers_via_day"]; ok {
				items, _ := related.([]any)
				for _, item := range items {
					rec, _ := item.(map[string]any)
					if rec != nil && rec["user"] == idA {
						t.Fatalf("blind broken: expand leaked A's answer to B before B answered: %v", rec)
					}
				}
			}
		}
	}

	// B answers. Now both have.
	if res := postQuestionAnswer(t, srv.URL, tokenB, "the day we got the pet too, obviously"); res.StatusCode != http.StatusOK {
		t.Fatalf("B answers: %d", res.StatusCode)
	}

	// Route: both now see each other's answer and both_answered=true.
	gotA = getQuestionToday(t, srv.URL, tokenA)
	if gotA["partner_answer"] != "the day we got the pet too, obviously" || gotA["both_answered"] != true {
		t.Fatalf("A should now see B's answer: %v", gotA)
	}
	gotB = getQuestionToday(t, srv.URL, tokenB)
	if gotB["partner_answer"] != "the day we got the pet" || gotB["both_answered"] != true {
		t.Fatalf("B should now see A's answer: %v", gotB)
	}

	// Direct collection LIST as B: now includes both rows.
	listRes = doJSON(t, http.MethodGet, srv.URL+"/api/collections/answers/records", tokenB, nil)
	listBody = decodeJSON(t, listRes)
	if got := listBody["totalItems"].(float64); got != 2 {
		t.Fatalf("expected B to see 2 answers post-reveal, got %v", got)
	}

	// Direct collection VIEW-BY-ID as B: now allowed.
	viewRes = doJSON(t, http.MethodGet, srv.URL+"/api/collections/answers/records/"+aAnswerID, tokenB, nil)
	viewBody := decodeJSON(t, viewRes)
	if viewRes.StatusCode != http.StatusOK {
		t.Fatalf("expected B to view A's answer post-reveal, got %d", viewRes.StatusCode)
	}
	if viewBody["text"] != "the day we got the pet" {
		t.Fatalf("unexpected text in post-reveal view: %v", viewBody)
	}
}

// TestAnswerCreateUpdateForgery: you can only ever author/edit your own
// answer row, even by naming someone else's id or a couple you're not in.
func TestAnswerCreateUpdateForgery(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	idA, tokenA, _, tokenB, coupleID := pairedCoupleWithIDs(t, srv.URL)

	dayRow, err := app.FindFirstRecordByFilter("question_days", "couple = {:c}", dbx.Params{"c": coupleID})
	if err != nil {
		// Nothing has asked for today's question yet in this couple —
		// trigger get-or-create first.
		getQuestionToday(t, srv.URL, tokenA)
		dayRow, err = app.FindFirstRecordByFilter("question_days", "couple = {:c}", dbx.Params{"c": coupleID})
		if err != nil {
			t.Fatalf("find question_days row: %v", err)
		}
	}

	// B tries to create an answer authored as A.
	res := doJSON(t, http.MethodPost, srv.URL+"/api/collections/answers/records", tokenB, map[string]any{
		"couple": coupleID, "day": dayRow.Id, "user": idA, "text": "forged",
	})
	if res.StatusCode == http.StatusOK {
		t.Fatal("B forged an answer authored as A")
	}

	// A creates their real answer, then B tries to edit it.
	res = doJSON(t, http.MethodPost, srv.URL+"/api/collections/answers/records", tokenA, map[string]any{
		"couple": coupleID, "day": dayRow.Id, "user": idA, "text": "real answer",
	})
	if res.StatusCode != http.StatusOK {
		t.Fatalf("A creates real answer directly: %d", res.StatusCode)
	}
	answerID := decodeJSON(t, res)["id"].(string)

	res = doJSON(t, http.MethodPatch, srv.URL+"/api/collections/answers/records/"+answerID, tokenB, map[string]any{
		"text": "tampered",
	})
	if res.StatusCode == http.StatusOK {
		t.Fatal("B edited A's answer directly")
	}

	// Nobody (not even the author, not even a superuser-less client) can
	// create a question_days row through the collection API — route-only.
	res = doJSON(t, http.MethodPost, srv.URL+"/api/collections/question_days/records", tokenA, map[string]any{
		"couple": coupleID, "date": "2099-01-01", "question_en": "sneaky", "question_pl": "sneaky",
	})
	if res.StatusCode == http.StatusOK {
		t.Fatal("client created a question_days row directly through the collection API")
	}
}

// --- outsider isolation -----------------------------------------------------

func TestQuestionOutsiderIsolation(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	idA, tokenA, _, tokenB, coupleID := pairedCoupleWithIDs(t, srv.URL)

	if res := postQuestionAnswer(t, srv.URL, tokenA, "us, obviously"); res.StatusCode != http.StatusOK {
		t.Fatalf("A answers: %d", res.StatusCode)
	}
	if res := postQuestionAnswer(t, srv.URL, tokenB, "also us"); res.StatusCode != http.StatusOK {
		t.Fatalf("B answers: %d", res.StatusCode)
	}

	answers, err := app.FindRecordsByFilter("answers", "couple = {:c} && user = {:u}", "", 0, 0, dbx.Params{"c": coupleID, "u": idA})
	if err != nil || len(answers) != 1 {
		t.Fatalf("expected A's answer row: err=%v rows=%v", err, answers)
	}
	aAnswerID := answers[0].Id

	dayRow, err := app.FindFirstRecordByFilter("question_days", "couple = {:c}", dbx.Params{"c": coupleID})
	if err != nil {
		t.Fatalf("find question_days row: %v", err)
	}

	// C is an outsider — a member of a completely different couple.
	tokenC, _, _ := pairedCouple(t, srv.URL)

	if res := doJSON(t, http.MethodGet, srv.URL+"/api/question/today", tokenC, nil); res.StatusCode != http.StatusOK {
		t.Fatalf("C's own /api/question/today should work fine for C's own couple, got %d", res.StatusCode)
	}

	res := doJSON(t, http.MethodGet, srv.URL+"/api/collections/answers/records", tokenC, nil)
	body := decodeJSON(t, res)
	if got := body["totalItems"].(float64); got != 0 {
		t.Fatalf("outsider sees %v answers from a couple they're not in", got)
	}

	viewRes := doJSON(t, http.MethodGet, srv.URL+"/api/collections/answers/records/"+aAnswerID, tokenC, nil)
	defer viewRes.Body.Close()
	if viewRes.StatusCode == http.StatusOK {
		t.Fatalf("outsider viewed a stranger couple's answer by id")
	}

	dayViewRes := doJSON(t, http.MethodGet, srv.URL+"/api/collections/question_days/records/"+dayRow.Id, tokenC, nil)
	defer dayViewRes.Body.Close()
	if dayViewRes.StatusCode == http.StatusOK {
		t.Fatalf("outsider viewed a stranger couple's question_days row by id")
	}

	// Unauthenticated requests are rejected outright.
	res = doJSON(t, http.MethodGet, srv.URL+"/api/question/today", "", nil)
	res.Body.Close()
	if res.StatusCode != http.StatusUnauthorized {
		t.Fatalf("expected 401 for unauthenticated /api/question/today, got %d", res.StatusCode)
	}
	res = postQuestionAnswer(t, srv.URL, "", "hi")
	res.Body.Close()
	if res.StatusCode != http.StatusUnauthorized {
		t.Fatalf("expected 401 for unauthenticated /api/question/answer, got %d", res.StatusCode)
	}
}

// --- pack sanity -------------------------------------------------------------

func TestPickQuestionDeterministicAndAvoidsRecent(t *testing.T) {
	first := pickQuestion("couple1", "2026-08-23", nil)
	second := pickQuestion("couple1", "2026-08-23", nil)
	if first.EN != second.EN {
		t.Fatalf("pickQuestion isn't deterministic for the same couple+date: %q vs %q", first.EN, second.EN)
	}

	// Marking every entry but one as recently used forces that one entry.
	recent := make(map[string]bool, len(questionPack))
	for _, q := range questionPack {
		recent[q.EN] = true
	}
	spared := questionPack[len(questionPack)/2].EN
	delete(recent, spared)

	got := pickQuestion("couple1", "2026-08-23", recent)
	if got.EN != spared {
		t.Fatalf("expected pickQuestion to avoid every recently-used entry but the spared one, got %q want %q", got.EN, spared)
	}
}
