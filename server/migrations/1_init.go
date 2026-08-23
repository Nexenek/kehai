package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

func init() {
	m.Register(func(app core.App) error {
		// --- couples ---
		couples := core.NewBaseCollection("couples")
		couples.Fields.Add(
			&core.TextField{Name: "name", Required: true, Max: 100},
			&core.TextField{Name: "invite_code", Hidden: true},
			&core.AutodateField{Name: "created", OnCreate: true},
			&core.AutodateField{Name: "updated", OnCreate: true, OnUpdate: true},
		)
		couples.ListRule = types.Pointer(`@request.auth.id != "" && id = @request.auth.couple`)
		couples.ViewRule = types.Pointer(`@request.auth.id != "" && id = @request.auth.couple`)
		if err := app.Save(couples); err != nil {
			return err
		}

		// --- users: add couple relation, open visibility to the partner ---
		users, err := app.FindCollectionByNameOrId("users")
		if err != nil {
			return err
		}
		users.Fields.Add(
			&core.RelationField{Name: "couple", CollectionId: couples.Id, MaxSelect: 1},
		)
		partnerVisible := `id = @request.auth.id || (couple != "" && couple = @request.auth.couple)`
		users.ListRule = types.Pointer(partnerVisible)
		users.ViewRule = types.Pointer(partnerVisible)
		if err := app.Save(users); err != nil {
			return err
		}

		coupleScoped := `@request.auth.id != "" && @request.auth.couple != "" && owner.couple = @request.auth.couple`
		ownOnly := `@request.auth.id != "" && owner = @request.auth.id`

		// --- devices: one record per (owner, kind, name); powers the phone/pc/both indicator ---
		devices := core.NewBaseCollection("devices")
		devices.Fields.Add(
			&core.RelationField{Name: "owner", CollectionId: users.Id, MaxSelect: 1, Required: true},
			&core.TextField{Name: "name", Required: true, Max: 100},
			&core.SelectField{Name: "kind", Values: []string{"phone", "desktop", "tablet", "portal"}, MaxSelect: 1, Required: true},
			&core.DateField{Name: "last_seen"},
			&core.AutodateField{Name: "created", OnCreate: true},
			&core.AutodateField{Name: "updated", OnCreate: true, OnUpdate: true},
		)
		devices.AddIndex("idx_devices_owner_kind_name", true, "`owner`, `kind`, `name`", "")
		devices.ListRule = types.Pointer(coupleScoped)
		devices.ViewRule = types.Pointer(coupleScoped)
		devices.CreateRule = types.Pointer(ownOnly)
		devices.UpdateRule = types.Pointer(ownOnly)
		devices.DeleteRule = types.Pointer(ownOnly)
		if err := app.Save(devices); err != nil {
			return err
		}

		userScoped := `@request.auth.id != "" && @request.auth.couple != "" && user.couple = @request.auth.couple`
		ownUser := `@request.auth.id != "" && user = @request.auth.id`

		// --- statuses: one record per user (mood + note + which device it came from) ---
		statuses := core.NewBaseCollection("statuses")
		statuses.Fields.Add(
			&core.RelationField{Name: "user", CollectionId: users.Id, MaxSelect: 1, Required: true},
			&core.TextField{Name: "mood", Max: 40},
			&core.TextField{Name: "note", Max: 200},
			&core.SelectField{Name: "source_kind", Values: []string{"phone", "desktop", "tablet", "portal"}, MaxSelect: 1},
			&core.AutodateField{Name: "created", OnCreate: true},
			&core.AutodateField{Name: "updated", OnCreate: true, OnUpdate: true},
		)
		statuses.AddIndex("idx_statuses_user", true, "`user`", "")
		statuses.ListRule = types.Pointer(userScoped)
		statuses.ViewRule = types.Pointer(userScoped)
		statuses.CreateRule = types.Pointer(ownUser)
		statuses.UpdateRule = types.Pointer(ownUser)
		statuses.DeleteRule = types.Pointer(ownUser)
		if err := app.Save(statuses); err != nil {
			return err
		}

		// --- events: append-only log for later phases (pet, webhooks, history) ---
		events := core.NewBaseCollection("events")
		events.Fields.Add(
			&core.RelationField{Name: "user", CollectionId: users.Id, MaxSelect: 1, Required: true},
			&core.TextField{Name: "type", Required: true, Max: 60},
			&core.JSONField{Name: "payload"},
			&core.AutodateField{Name: "created", OnCreate: true},
		)
		events.ListRule = types.Pointer(userScoped)
		events.ViewRule = types.Pointer(userScoped)
		events.CreateRule = types.Pointer(ownUser)
		return app.Save(events)
	}, func(app core.App) error {
		for _, name := range []string{"events", "statuses", "devices", "couples"} {
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
