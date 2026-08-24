package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Registered as "9e_14_vitals.go" — see the long NOTE ON THE REGISTERED NAME
// in 10_art.go: PocketBase sorts migrations by string name, so 14_* would
// otherwise run before 1_init.
//
// Smartwatch vitals (kb/features.md, kb/platform-android.md "Smartwatches"):
// two more live-state telemetry fields on `devices`, fed by the phone from
// Health Connect (where the watch vendors' apps sync steps/HR) over the same
// only-present-keys heartbeat as every other telemetry field. Opt-in like all
// sharing (share_vitals pref, default off).
//
//   - steps_today: steps since local midnight on that device. 0 doubles as
//     "unreported" (same convention as battery — a real 0 only happens right
//     at midnight, when showing nothing is fine).
//   - heart_rate: {bpm, at} — the most recent sample Health Connect has,
//     WITH its own timestamp, because watches sync in batches and a reading
//     can be an hour stale by the time the phone sees it. Freshness gating
//     is the client's job (the beating heart only beats on recent samples);
//     the server just refuses nonsense.
func init() {
	m.Register(func(app core.App) error {
		devices, err := app.FindCollectionByNameOrId("devices")
		if err != nil {
			return err
		}
		devices.Fields.Add(
			&core.NumberField{Name: "steps_today", Min: types.Pointer(0.0), Max: types.Pointer(200000.0)},
			&core.JSONField{Name: "heart_rate"},
		)
		return app.Save(devices)
	}, func(app core.App) error {
		devices, err := app.FindCollectionByNameOrId("devices")
		if err != nil {
			return err
		}
		for _, name := range []string{"steps_today", "heart_rate"} {
			devices.Fields.RemoveByName(name)
		}
		return app.Save(devices)
	}, "9e_14_vitals.go")
}
