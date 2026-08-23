package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Registered as "9d_13_pings.go" — see the long NOTE ON THE REGISTERED NAME
// at the top of 10_art.go: PocketBase sorts migrations by STRING name, so
// "13_*" would run before "1_init.go" and find no `couples` collection.
// 10 → "9a_", 11 → "9b_", 12 → "9c_", 13 → "9d_".
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

		// pings: the one-tap "thinking of you" (kb/features.md's
		// research-additions table — "Zero-effort connection; distinct
		// custom sound"). A ping carries no payload beyond its kind: the
		// whole point is that sending one costs nothing, so there is
		// nothing to compose and nothing to read. Its entire life happens
		// in the moment it lands — a notification on the other person's
		// devices and a small flourish in the app.
		//
		// Shaped exactly like `touches` (7_delights.go): couple-scoped
		// read, author-locked create, immutable, purge-only delete. The
		// only real difference is the retention window — a ping is worth
		// glancing back at ("she sent three hugs yesterday"), a fingertip
		// position never is — so these live a week instead of an hour.
		coupleScoped := `@request.auth.id != "" && @request.auth.couple != "" && couple = @request.auth.couple`

		pings := core.NewBaseCollection("pings")
		pings.Fields.Add(
			&core.RelationField{Name: "couple", CollectionId: couples.Id, MaxSelect: 1, Required: true},
			&core.RelationField{Name: "from", CollectionId: users.Id, MaxSelect: 1, Required: true},
			// thinking ♡ / kiss (´ε｀ )♡ / hug (づ￣ ³￣)づ — the kaomoji
			// live client-side (app/lib/domain/models/ping.dart); the
			// server only guards the vocabulary.
			&core.SelectField{
				Name:      "kind",
				Values:    []string{"thinking", "kiss", "hug"},
				MaxSelect: 1,
				Required:  true,
			},
			&core.AutodateField{Name: "created", OnCreate: true},
		)
		pings.AddIndex("idx_pings_couple_created", false, "`couple`, `created`", "")
		pings.ListRule = types.Pointer(coupleScoped)
		pings.ViewRule = types.Pointer(coupleScoped)
		// `from = @request.auth.id` is the forgery block: you may only ever
		// send a ping as yourself, so a "thinking of you" in the feed is
		// always genuinely from the person it names.
		pings.CreateRule = types.Pointer(coupleScoped + ` && from = @request.auth.id`)
		// UpdateRule stays nil: a ping is a moment, not a document.
		// DeleteRule stays nil: only the purge cron (running as the app,
		// outside the record API rules) removes them — see pings.go.
		return app.Save(pings)
	}, func(app core.App) error {
		col, err := app.FindCollectionByNameOrId("pings")
		if err == nil {
			return app.Delete(col)
		}
		return nil
	}, "9d_13_pings.go")
}
