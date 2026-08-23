package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

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

		// The shared pet: exactly one per couple, co-parented. Both partners
		// read and write the same row — feeding, petting, dressing and
		// renaming are all just updates to it.
		//
		// Mood/hunger are NOT stored: they're derived client-side from the
		// ages of fed_at/pet_at (see app/lib/ui/features/pet/pet_state.dart),
		// so the server never has to run a timer and the pet can never be
		// "starved" into a punishing state by a missed cron. kb/features.md
		// anti-features: "The pet gets 'sleepy', never dies."
		//
		// name has no server default — a fresh row comes back empty and the
		// app fills in "kehai-chan"; PocketBase text fields can't carry a
		// default, and baking one in via a hook would fight the rename.
		pets := core.NewBaseCollection("pets")
		pets.Fields.Add(
			&core.RelationField{Name: "couple", CollectionId: couples.Id, MaxSelect: 1, Required: true},
			&core.TextField{Name: "name", Max: 30},
			&core.SelectField{Name: "variant", Values: []string{"blob", "cat", "star"}, MaxSelect: 1},
			&core.DateField{Name: "fed_at"},
			&core.DateField{Name: "pet_at"},
			&core.SelectField{Name: "outfit", Values: []string{"none", "bow", "scarf", "crown"}, MaxSelect: 1},
			&core.AutodateField{Name: "created", OnCreate: true},
			&core.AutodateField{Name: "updated", OnCreate: true, OnUpdate: true},
		)
		// One pet per couple — the app's get-or-create races (both partners
		// opening the app at once) resolve here rather than silently
		// producing two pets.
		pets.AddIndex("idx_pets_couple", true, "`couple`", "")
		pets.ListRule = types.Pointer(coupleScoped)
		pets.ViewRule = types.Pointer(coupleScoped)
		pets.CreateRule = types.Pointer(coupleScoped)
		pets.UpdateRule = types.Pointer(coupleScoped)
		// DeleteRule stays nil: you don't delete the pet.
		if err := app.Save(pets); err != nil {
			return err
		}

		// Append-only care log — the raw material for a future "pet history"
		// view ("you fed them 12 times this week ♡"). Same author-forgery
		// guard as doodles/instants: you can only log your own actions.
		// No update/delete rules: the log is immutable.
		petEvents := core.NewBaseCollection("pet_events")
		petEvents.Fields.Add(
			&core.RelationField{Name: "couple", CollectionId: couples.Id, MaxSelect: 1, Required: true},
			&core.RelationField{Name: "user", CollectionId: users.Id, MaxSelect: 1, Required: true},
			&core.SelectField{Name: "type", Values: []string{"feed", "pet", "dress", "rename"}, MaxSelect: 1, Required: true},
			&core.AutodateField{Name: "created", OnCreate: true},
		)
		petEvents.AddIndex("idx_pet_events_couple_created", false, "`couple`, `created`", "")
		petEvents.ListRule = types.Pointer(coupleScoped)
		petEvents.ViewRule = types.Pointer(coupleScoped)
		petEvents.CreateRule = types.Pointer(coupleScoped + ` && user = @request.auth.id`)
		return app.Save(petEvents)
	}, func(app core.App) error {
		for _, name := range []string{"pet_events", "pets"} {
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
