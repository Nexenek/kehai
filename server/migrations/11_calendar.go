package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Phase 4b — native shared calendar. Deviates from kb/decisions.md ADR-7
// (Baikal/CalDAV) for v1: a kehai-native events collection instead, mirror-
// ing countdowns' shared-ownership model. Robust, zero extra apps to run/
// pair/troubleshoot on a couple's home server; CalDAV/Google sync (Baikal +
// vdirsyncer, as ADR-7 originally specified) is deferred to an optional
// Phase 8 add-on that can sync *into* this collection later without an app
// data-model change. kb/decisions.md should be updated to record this
// (superseding ADR-7 for v1 scope) — left to the coordinator's kb pass.
//
// Collection is named "calendar_events", not "events" — 1_init.go already
// claims "events" for its generic append-only activity log (user, type,
// payload), and PocketBase collection names must be unique. "calendar_events"
// keeps the intent obvious without colliding.
//
// NOTE ON THE REGISTERED NAME (the third m.Register argument below): see
// 10_art.go's comment for the full explanation — PocketBase sorts
// migrations by plain string comparison of the registered file name, so a
// literal "11_calendar.go" would sort BEFORE "1_init.go" and run before the
// `couples` collection exists. Following that file's established
// convention (10 → "9a_*", 11 → "9b_11_*.go", 12 → "9c_12_*.go"), this one
// registers as "9b_11_calendar.go" so it lands right after 9_questions.go
// while the source file keeps its human-readable 11_* number.
func init() {
	m.Register(func(app core.App) error {
		couples, err := app.FindCollectionByNameOrId("couples")
		if err != nil {
			return err
		}

		// Shared ownership: either partner can create/edit/delete — same
		// rule shape as countdowns/notes (server/migrations/3_shared_content.go).
		shared := `@request.auth.id != "" && @request.auth.couple != "" && couple = @request.auth.couple`

		events := core.NewBaseCollection("calendar_events")
		events.Fields.Add(
			&core.RelationField{Name: "couple", CollectionId: couples.Id, MaxSelect: 1, Required: true},
			&core.TextField{Name: "title", Required: true, Max: 120},
			&core.DateField{Name: "starts", Required: true},
			&core.DateField{Name: "ends"},
			&core.BoolField{Name: "all_day"},
			&core.TextField{Name: "notes", Max: 500},
			&core.SelectField{Name: "color", Values: []string{"pink", "lavender", "mint", "sky", "butter"}, MaxSelect: 1},
			&core.AutodateField{Name: "created", OnCreate: true},
			&core.AutodateField{Name: "updated", OnCreate: true, OnUpdate: true},
		)
		// Month-range list queries filter/sort on (couple, starts).
		events.AddIndex("idx_calendar_events_couple_starts", false, "`couple`, `starts`", "")
		events.ListRule = types.Pointer(shared)
		events.ViewRule = types.Pointer(shared)
		events.CreateRule = types.Pointer(shared)
		events.UpdateRule = types.Pointer(shared)
		events.DeleteRule = types.Pointer(shared)
		return app.Save(events)
	}, func(app core.App) error {
		col, err := app.FindCollectionByNameOrId("calendar_events")
		if err == nil {
			if err := app.Delete(col); err != nil {
				return err
			}
		}
		return nil
	}, "9b_11_calendar.go")
}
