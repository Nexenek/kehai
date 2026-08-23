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

		// Shared board: a freeform decorable pinboard both partners arrange
		// together (kb/design-language.md's "desktop metaphor" power-user
		// wink — items genuinely drag around). Full couple-scoped shared
		// ownership, same shape as notes' `shared` rule in
		// 3_shared_content.go: create isn't author-locked because a board
		// item belongs to both partners the moment either one places it.
		shared := `@request.auth.id != "" && @request.auth.couple != "" && couple = @request.auth.couple`

		boardItems := core.NewBaseCollection("board_items")
		boardItems.Fields.Add(
			&core.RelationField{Name: "couple", CollectionId: couples.Id, MaxSelect: 1, Required: true},
			&core.SelectField{Name: "type", Values: []string{"note", "photo", "sticker"}, MaxSelect: 1, Required: true},
			// For notes.
			&core.TextField{Name: "text", Max: 500},
			// For photos.
			&core.FileField{
				Name:      "image",
				MaxSelect: 1,
				MaxSize:   5 << 20,
				MimeTypes: []string{"image/jpeg", "image/png", "image/webp"},
			},
			// For stickers — a single glyph/kaomoji token, not a sentence.
			&core.TextField{Name: "sticker", Max: 8},
			// Normalized 0..1 board position. Not Required: PocketBase
			// treats required numbers as non-zero, and 0.0 is a valid
			// coordinate (an item pinned at the board's edge) — same
			// reasoning as lat/lon in 5_location_instants.go.
			&core.NumberField{Name: "x", Min: types.Pointer(0.0), Max: types.Pointer(1.0)},
			&core.NumberField{Name: "y", Min: types.Pointer(0.0), Max: types.Pointer(1.0)},
			// Hand-placed tilt, degrees.
			&core.NumberField{Name: "rot", Min: types.Pointer(-30.0), Max: types.Pointer(30.0)},
			// Stacking order — bring-to-front on grab bumps this past the
			// current max. Not Required for the same "0 is valid" reason.
			&core.NumberField{Name: "z"},
			// Sticky-note pastel — same palette as `notes.color`.
			&core.SelectField{Name: "color", Values: []string{"pink", "lavender", "mint", "sky", "butter"}, MaxSelect: 1},
			&core.AutodateField{Name: "created", OnCreate: true},
			&core.AutodateField{Name: "updated", OnCreate: true, OnUpdate: true},
		)
		boardItems.AddIndex("idx_board_items_couple", false, "`couple`", "")
		boardItems.ListRule = types.Pointer(shared)
		boardItems.ViewRule = types.Pointer(shared)
		boardItems.CreateRule = types.Pointer(shared)
		boardItems.UpdateRule = types.Pointer(shared)
		boardItems.DeleteRule = types.Pointer(shared)
		return app.Save(boardItems)
	}, func(app core.App) error {
		col, err := app.FindCollectionByNameOrId("board_items")
		if err == nil {
			return app.Delete(col)
		}
		return nil
	})
}
