package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

func init() {
	m.Register(func(app core.App) error {
		users, err := app.FindCollectionByNameOrId("users")
		if err != nil {
			return err
		}
		// Honest ghost mode: partner can always see that (and until when)
		// location sharing is paused — the field rides on the already
		// partner-visible users record.
		users.Fields.Add(&core.DateField{Name: "ghost_until"})
		if err := app.Save(users); err != nil {
			return err
		}

		couples, err := app.FindCollectionByNameOrId("couples")
		if err != nil {
			return err
		}

		userScoped := `@request.auth.id != "" && @request.auth.couple != "" && user.couple = @request.auth.couple`

		// Location points are written ONLY by the /api/owntracks route (no
		// client create/update/delete — nil rules mean superuser/route only).
		// lat/lon are not Required: PocketBase treats required numbers as
		// non-zero, and 0.0 is a valid coordinate; the route validates.
		locations := core.NewBaseCollection("locations")
		locations.Fields.Add(
			&core.RelationField{Name: "user", CollectionId: users.Id, MaxSelect: 1, Required: true},
			&core.NumberField{Name: "lat"},
			&core.NumberField{Name: "lon"},
			&core.NumberField{Name: "accuracy"},
			&core.NumberField{Name: "battery"},
			&core.NumberField{Name: "velocity"},
			&core.DateField{Name: "recorded", Required: true},
			&core.AutodateField{Name: "created", OnCreate: true},
		)
		locations.AddIndex("idx_locations_user_recorded", false, "`user`, `recorded`", "")
		locations.ListRule = types.Pointer(userScoped)
		locations.ViewRule = types.Pointer(userScoped)
		if err := app.Save(locations); err != nil {
			return err
		}

		// Instants: same shape/rules as doodles + caption, bigger files.
		coupleScoped := `@request.auth.id != "" && @request.auth.couple != "" && couple = @request.auth.couple`
		instants := core.NewBaseCollection("instants")
		instants.Fields.Add(
			&core.RelationField{Name: "couple", CollectionId: couples.Id, MaxSelect: 1, Required: true},
			&core.RelationField{Name: "author", CollectionId: users.Id, MaxSelect: 1, Required: true},
			&core.FileField{
				Name:      "image",
				MaxSelect: 1,
				MaxSize:   5 << 20,
				MimeTypes: []string{"image/jpeg", "image/png", "image/webp"},
				Required:  true,
			},
			&core.TextField{Name: "caption", Max: 140},
			&core.AutodateField{Name: "created", OnCreate: true},
		)
		instants.ListRule = types.Pointer(coupleScoped)
		instants.ViewRule = types.Pointer(coupleScoped)
		instants.CreateRule = types.Pointer(coupleScoped + ` && author = @request.auth.id`)
		instants.DeleteRule = types.Pointer(coupleScoped)
		return app.Save(instants)
	}, func(app core.App) error {
		for _, name := range []string{"instants", "locations"} {
			col, err := app.FindCollectionByNameOrId(name)
			if err == nil {
				if err := app.Delete(col); err != nil {
					return err
				}
			}
		}
		users, err := app.FindCollectionByNameOrId("users")
		if err != nil {
			return err
		}
		users.Fields.RemoveByName("ghost_until")
		return app.Save(users)
	})
}
