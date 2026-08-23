package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Daily question, blind reveal (kb/features.md: "both answer blind, reveal
// together — ritual + conversation fuel"). Two collections:
//
//   - question_days: one row per couple per calendar day, holding that
//     day's prompt in both languages. Get-or-create only happens through
//     the /api/question/today route (questions.go) — Create/Update/Delete
//     rules stay nil so nothing else can mint or edit a day's question.
//
//   - answers: one row per (day, user). The blind is enforced here, at the
//     collection's own List/ViewRule, so it holds even for a client that
//     bypasses the /api/question/* routes and talks to the record API
//     directly. See the blindReveal rule below for how.
func init() {
	m.Register(func(app core.App) error {
		couples, err := app.FindCollectionByNameOrId("couples")
		if err != nil {
			return err
		}
		users, err := app.FindCollectionByNameOrId("users")
		if err != nil {
			return err
		}

		coupleScoped := `@request.auth.id != "" && @request.auth.couple != "" && couple = @request.auth.couple`

		questionDays := core.NewBaseCollection("question_days")
		questionDays.Fields.Add(
			&core.RelationField{Name: "couple", CollectionId: couples.Id, MaxSelect: 1, Required: true},
			&core.TextField{Name: "date", Required: true, Max: 10, Pattern: `^\d{4}-\d{2}-\d{2}$`},
			&core.TextField{Name: "question_en", Max: 300},
			&core.TextField{Name: "question_pl", Max: 300},
			&core.AutodateField{Name: "created", OnCreate: true},
		)
		// One question per couple per day — also what makes the route's
		// get-or-create race-safe (see getOrCreateQuestionDay).
		questionDays.AddIndex("idx_question_days_couple_date", true, "`couple`, `date`", "")
		questionDays.ListRule = types.Pointer(coupleScoped)
		questionDays.ViewRule = types.Pointer(coupleScoped)
		// Create/Update/Delete stay nil: route-managed only (questions.go
		// saves through app.Save, which bypasses API rules entirely).
		if err := app.Save(questionDays); err != nil {
			return err
		}

		answers := core.NewBaseCollection("answers")
		answers.Fields.Add(
			&core.RelationField{Name: "couple", CollectionId: couples.Id, MaxSelect: 1, Required: true},
			&core.RelationField{Name: "day", CollectionId: questionDays.Id, MaxSelect: 1, Required: true},
			&core.RelationField{Name: "user", CollectionId: users.Id, MaxSelect: 1, Required: true},
			&core.TextField{Name: "text", Max: 1000},
			&core.AutodateField{Name: "created", OnCreate: true},
			&core.AutodateField{Name: "updated", OnCreate: true, OnUpdate: true},
		)
		// One answer per user per day — also what makes the route's upsert
		// race-safe (see upsertAnswer).
		answers.AddIndex("idx_answers_day_user", true, "`day`, `user`", "")

		ownAnswer := `user = @request.auth.id`
		// THE BLIND: you can always see your own answer. You can see your
		// partner's answer on this day only once you've ALSO answered —
		// which we can't say directly ("has the OTHER couple member
		// answered"), so instead we check it from your own side: does this
		// day have *any* answer authored by you? That's only true once
		// you've submitted your own, and the record being evaluated here is
		// always the partner's (your own already passed via the first
		// clause) — so the two conditions together mean exactly "both of
		// us have answered". `day.answers_via_day` is the implicit back-
		// relation from question_days to every answers row pointing at it
		// through the `day` field (naming: `<collection>_via_<field>`);
		// `?=` forces "at least one match" semantics over that multi-valued
		// hop instead of PocketBase's default all-match reading. Verified
		// against a real running instance in questions_test.go
		// (TestBlindReveal*) — direct list, direct view-by-id, and a
		// same-day-different-couple isolation check all confirmed hidden
		// until both have answered, then visible to both.
		blindReveal := coupleScoped + ` && (` + ownAnswer + ` || day.answers_via_day.user ?= @request.auth.id)`

		answers.ListRule = types.Pointer(blindReveal)
		answers.ViewRule = types.Pointer(blindReveal)
		answers.CreateRule = types.Pointer(coupleScoped + ` && ` + ownAnswer)
		answers.UpdateRule = types.Pointer(coupleScoped + ` && ` + ownAnswer)
		// DeleteRule stays nil: no take-backs; edit via Update instead.
		return app.Save(answers)
	}, func(app core.App) error {
		for _, name := range []string{"answers", "question_days"} {
			col, err := app.FindCollectionByNameOrId(name)
			if err == nil {
				if err := app.Delete(col); err != nil {
					return err
				}
			}
		}
		return nil
	})
}
