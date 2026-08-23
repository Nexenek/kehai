package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

func init() {
	m.Register(func(app core.App) error {
		// couples: anniversary date for the "together N days" counter; members
		// may update their own couple (invite_code stays safe — hidden fields
		// are not writable through the record API by regular users).
		couples, err := app.FindCollectionByNameOrId("couples")
		if err != nil {
			return err
		}
		couples.Fields.Add(&core.DateField{Name: "anniversary"})
		couples.UpdateRule = types.Pointer(`@request.auth.id != "" && id = @request.auth.couple`)
		if err := app.Save(couples); err != nil {
			return err
		}

		// Shared ownership: either partner can create/edit/delete — it's theirs
		// together. The create rule also pins the incoming record to the
		// author's own couple.
		shared := `@request.auth.id != "" && @request.auth.couple != "" && couple = @request.auth.couple`

		countdowns := core.NewBaseCollection("countdowns")
		countdowns.Fields.Add(
			&core.RelationField{Name: "couple", CollectionId: couples.Id, MaxSelect: 1, Required: true},
			&core.TextField{Name: "title", Required: true, Max: 100},
			&core.DateField{Name: "date", Required: true},
			&core.TextField{Name: "kaomoji", Max: 20},
			&core.AutodateField{Name: "created", OnCreate: true},
			&core.AutodateField{Name: "updated", OnCreate: true, OnUpdate: true},
		)
		countdowns.ListRule = types.Pointer(shared)
		countdowns.ViewRule = types.Pointer(shared)
		countdowns.CreateRule = types.Pointer(shared)
		countdowns.UpdateRule = types.Pointer(shared)
		countdowns.DeleteRule = types.Pointer(shared)
		if err := app.Save(countdowns); err != nil {
			return err
		}

		notes := core.NewBaseCollection("notes")
		notes.Fields.Add(
			&core.RelationField{Name: "couple", CollectionId: couples.Id, MaxSelect: 1, Required: true},
			&core.TextField{Name: "title", Max: 100},
			&core.TextField{Name: "body", Max: 10000},
			&core.SelectField{Name: "color", Values: []string{"pink", "lavender", "mint", "sky", "butter"}, MaxSelect: 1},
			&core.BoolField{Name: "pinned"},
			&core.AutodateField{Name: "created", OnCreate: true},
			&core.AutodateField{Name: "updated", OnCreate: true, OnUpdate: true},
		)
		notes.ListRule = types.Pointer(shared)
		notes.ViewRule = types.Pointer(shared)
		notes.CreateRule = types.Pointer(shared)
		notes.UpdateRule = types.Pointer(shared)
		notes.DeleteRule = types.Pointer(shared)
		return app.Save(notes)
	}, func(app core.App) error {
		for _, name := range []string{"notes", "countdowns"} {
			col, err := app.FindCollectionByNameOrId(name)
			if err == nil {
				if err := app.Delete(col); err != nil {
					return err
				}
			}
		}
		couples, err := app.FindCollectionByNameOrId("couples")
		if err != nil {
			return err
		}
		couples.Fields.RemoveByName("anniversary")
		couples.UpdateRule = nil
		return app.Save(couples)
	})
}
