package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Phase "delights" — the classic LDR physical-touch substitute (thumb-kiss)
// and the "what time is it there" dual clock. See kb/features.md's
// research-additions table.
func init() {
	m.Register(func(app core.App) error {
		// devices.timezone: set via the heartbeat route, same only-present-keys
		// contract as battery/charging/idle_seconds/now_playing/activity
		// (routes.go `heartbeat`). Named "timezone" but, per the client-side
		// note in heartbeat_service.dart, the app actually sends a UTC-offset
		// string like "UTC+02:00" rather than an IANA zone name — Dart's SDK
		// has no built-in IANA zone lookup and this batch doesn't add a
		// package for it. The field stays generously sized (64 chars) and
		// loosely validated so a real IANA name works too, if a future
		// client/plugin can produce one.
		devices, err := app.FindCollectionByNameOrId("devices")
		if err != nil {
			return err
		}
		devices.Fields.Add(&core.TextField{Name: "timezone", Max: 64})
		if err := app.Save(devices); err != nil {
			return err
		}

		couples, err := app.FindCollectionByNameOrId("couples")
		if err != nil {
			return err
		}
		users, err := app.FindCollectionByNameOrId("users")
		if err != nil {
			return err
		}

		// touches: ephemeral thumb-kiss touch points. Both partners' fingertip
		// positions stream through here while a thumb-kiss session is active;
		// realtime-subscribed, then purged after an hour by cron (nobody reads
		// old touches — the UI only ever cares about the last second or two).
		coupleScoped := `@request.auth.id != "" && @request.auth.couple != "" && couple = @request.auth.couple`
		touches := core.NewBaseCollection("touches")
		touches.Fields.Add(
			&core.RelationField{Name: "couple", CollectionId: couples.Id, MaxSelect: 1, Required: true},
			&core.RelationField{Name: "user", CollectionId: users.Id, MaxSelect: 1, Required: true},
			&core.NumberField{Name: "x", Required: true, Min: types.Pointer(0.0), Max: types.Pointer(1.0)},
			&core.NumberField{Name: "y", Required: true, Min: types.Pointer(0.0), Max: types.Pointer(1.0)},
			&core.AutodateField{Name: "created", OnCreate: true},
		)
		touches.AddIndex("idx_touches_couple_created", false, "`couple`, `created`", "")
		touches.ListRule = types.Pointer(coupleScoped)
		touches.ViewRule = types.Pointer(coupleScoped)
		touches.CreateRule = types.Pointer(coupleScoped + ` && user = @request.auth.id`)
		// UpdateRule stays nil: touches are write-once, never edited.
		// DeleteRule stays nil: only the purge cron (running as the app, not
		// through the record API rules) removes them.
		return app.Save(touches)
	}, func(app core.App) error {
		col, err := app.FindCollectionByNameOrId("touches")
		if err == nil {
			if err := app.Delete(col); err != nil {
				return err
			}
		}

		devices, err := app.FindCollectionByNameOrId("devices")
		if err != nil {
			return err
		}
		devices.Fields.RemoveByName("timezone")
		return app.Save(devices)
	})
}
