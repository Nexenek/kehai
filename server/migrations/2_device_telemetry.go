package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Phase 2a telemetry contract (see kb/platform-desktop.md): live-state fields
// on the devices collection, set via the heartbeat endpoint and
// realtime-subscribed by the partner.
func init() {
	m.Register(func(app core.App) error {
		devices, err := app.FindCollectionByNameOrId("devices")
		if err != nil {
			return err
		}
		devices.Fields.Add(
			&core.NumberField{Name: "battery", Min: types.Pointer(0.0), Max: types.Pointer(100.0)},
			&core.BoolField{Name: "charging"},
			&core.NumberField{Name: "idle_seconds", Min: types.Pointer(0.0)},
			&core.JSONField{Name: "now_playing"},
			&core.TextField{Name: "activity", Max: 100},
		)
		return app.Save(devices)
	}, func(app core.App) error {
		devices, err := app.FindCollectionByNameOrId("devices")
		if err != nil {
			return err
		}
		for _, name := range []string{"battery", "charging", "idle_seconds", "now_playing", "activity"} {
			devices.Fields.RemoveByName(name)
		}
		return app.Save(devices)
	})
}
