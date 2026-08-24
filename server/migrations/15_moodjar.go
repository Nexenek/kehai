package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Registered as "9f_15_moodjar.go" — see the NOTE ON THE REGISTERED NAME in
// 10_art.go (PocketBase sorts migrations by string name).
//
// The mood jar (kb/features.md, Phase 6's last pending delight): every mood
// change drops a bead into a shared jar the couple can tip out together —
// "you were sleepy all tuesday (´｡• ᵕ •｡`)". `statuses` is one record per
// user updated in place, so history has to be captured somewhere, and that
// somewhere is this append-only log.
//
// Clients can only READ it (couple-scoped). Writing is the server's job — a
// hook on statuses (moodjar.go) appends an entry whenever the mood actually
// changes, which keeps the log honest: no client can retro-fill or edit a
// week of feelings. Purged after 90 days by a daily cron; the jar is a
// keepsake of the recent past, not a surveillance archive.
func init() {
	m.Register(func(app core.App) error {
		users, err := app.FindCollectionByNameOrId("users")
		if err != nil {
			return err
		}
		couples, err := app.FindCollectionByNameOrId("couples")
		if err != nil {
			return err
		}

		entries := core.NewBaseCollection("mood_entries")
		entries.Fields.Add(
			&core.RelationField{Name: "couple", CollectionId: couples.Id, MaxSelect: 1, Required: true},
			&core.RelationField{Name: "user", CollectionId: users.Id, MaxSelect: 1, Required: true},
			&core.TextField{Name: "mood", Required: true, Max: 40},
			&core.TextField{Name: "note", Max: 200},
			&core.AutodateField{Name: "created", OnCreate: true},
		)
		entries.AddIndex("idx_mood_entries_couple_created", false, "`couple`, `created`", "")
		coupleScoped := `@request.auth.id != "" && @request.auth.couple != "" && couple = @request.auth.couple`
		entries.ListRule = types.Pointer(coupleScoped)
		entries.ViewRule = types.Pointer(coupleScoped)
		// Create/Update/Delete stay nil: superuser (the hook + purge) only.
		return app.Save(entries)
	}, func(app core.App) error {
		col, err := app.FindCollectionByNameOrId("mood_entries")
		if err != nil {
			return nil
		}
		return app.Delete(col)
	}, "9f_15_moodjar.go")
}
