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

		// Doodles are immutable little drawings sent to the partner: create
		// and delete only, no edits. Both partners can see and delete; only
		// the author can create as themselves.
		doodles := core.NewBaseCollection("doodles")
		doodles.Fields.Add(
			&core.RelationField{Name: "couple", CollectionId: couples.Id, MaxSelect: 1, Required: true},
			&core.RelationField{Name: "author", CollectionId: users.Id, MaxSelect: 1, Required: true},
			&core.FileField{
				Name:      "image",
				MaxSelect: 1,
				MaxSize:   1 << 20, // 1MB — doodles are small PNGs
				MimeTypes: []string{"image/png"},
				Required:  true,
			},
			&core.AutodateField{Name: "created", OnCreate: true},
		)
		coupleScoped := `@request.auth.id != "" && @request.auth.couple != "" && couple = @request.auth.couple`
		doodles.ListRule = types.Pointer(coupleScoped)
		doodles.ViewRule = types.Pointer(coupleScoped)
		doodles.CreateRule = types.Pointer(coupleScoped + ` && author = @request.auth.id`)
		doodles.DeleteRule = types.Pointer(coupleScoped)
		// UpdateRule stays nil: immutable.
		return app.Save(doodles)
	}, func(app core.App) error {
		col, err := app.FindCollectionByNameOrId("doodles")
		if err != nil {
			return nil
		}
		return app.Delete(col)
	})
}
