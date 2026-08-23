package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// NOTE ON THE REGISTERED NAME (the third m.Register argument below).
//
// PocketBase records — and, crucially, SORTS BY — the migration's file name
// using plain string comparison, not numeric order (see
// core.MigrationsList.Register). "10_art.go" therefore sorts BEFORE
// "1_init.go" ('0' < '_'), which would run this migration against a
// database that has no `couples` collection yet ("sql: no rows in result
// set"). Registering under an explicit name starting "9a_" puts it
// immediately after "9_questions.go" where it belongs, while the file keeps
// its human-readable 10_* number.
//
// Any migration numbered 10 or higher has to do the same: 11 →
// "9b_11_*.go", 12 → "9c_12_*.go", and so on.
func init() {
	m.Register(func(app core.App) error {
		couples, err := app.FindCollectionByNameOrId("couples")
		if err != nil {
			return err
		}

		// The paper-doll art system (ADR-13, kb/features.md "Status art
		// system"). One partner draws reusable transparent PNG layers on a
		// shared square canvas; the app composites them at runtime into a
		// live scene of the *other* partner, driven by their mood + ambient
		// state.
		//
		// Slots paint in a fixed order — background, base, outfit,
		// expression, prop — so the artist never has to think about z-order
		// across slots; `sort` only orders layers *within* one slot (and is
		// the tie-break when two layers in a slot match the current state
		// equally well: lower sort wins, which is "higher in the list" in
		// the manager UI).
		//
		// `conditions` is a small JSON object rather than more columns
		// because it's genuinely open-ended matching data, not queried
		// server-side — everything is resolved client-side by
		// app/lib/domain/art_scene.dart's resolveArtScene():
		//
		//   {"moods": ["sleepy","cozy"], "ambient": ["music"], "default": true}
		//
		// An empty/missing array matches anything in that dimension;
		// "default": true marks the slot's fallback. The client parses this
		// defensively (garbage never crashes the portrait — it degrades to
		// "matches anything"), so the server does not validate its shape.
		//
		// Ownership is fully shared, mirroring notes/board_items in
		// 3_shared_content.go and 8_board.go: no author field and no author
		// lock, because the art belongs to the couple the moment either of
		// them uploads it — the non-drawing partner has to be able to fix a
		// typo'd name or delete a mistake without asking.
		shared := `@request.auth.id != "" && @request.auth.couple != "" && couple = @request.auth.couple`

		artLayers := core.NewBaseCollection("art_layers")
		artLayers.Fields.Add(
			&core.RelationField{Name: "couple", CollectionId: couples.Id, MaxSelect: 1, Required: true},
			&core.SelectField{
				Name:      "slot",
				Values:    []string{"background", "base", "outfit", "expression", "prop"},
				MaxSelect: 1,
				Required:  true,
			},
			&core.TextField{Name: "name", Max: 60},
			// Transparent PNG only: a JPEG would paint an opaque rectangle
			// over every layer under it, which is exactly the failure the
			// artist would struggle to diagnose. The client enforces this
			// too (magic-byte check before upload) so the error is friendly
			// rather than a 400.
			&core.FileField{
				Name:      "image",
				MaxSelect: 1,
				MaxSize:   2 << 20, // 2MB — a 512x512 pixel-art PNG is a few KB
				MimeTypes: []string{"image/png"},
				Required:  true,
			},
			// z within the slot / match tie-break. Not Required: PocketBase
			// treats required numbers as non-zero and 0 is the natural first
			// position — same reasoning as board_items.z in 8_board.go.
			&core.NumberField{Name: "sort"},
			&core.JSONField{Name: "conditions", MaxSize: 4096},
			&core.AutodateField{Name: "created", OnCreate: true},
			&core.AutodateField{Name: "updated", OnCreate: true, OnUpdate: true},
		)
		artLayers.AddIndex("idx_art_layers_couple_slot", false, "`couple`, `slot`", "")
		artLayers.ListRule = types.Pointer(shared)
		artLayers.ViewRule = types.Pointer(shared)
		artLayers.CreateRule = types.Pointer(shared)
		artLayers.UpdateRule = types.Pointer(shared)
		artLayers.DeleteRule = types.Pointer(shared)
		return app.Save(artLayers)
	}, func(app core.App) error {
		col, err := app.FindCollectionByNameOrId("art_layers")
		if err == nil {
			return app.Delete(col)
		}
		return nil
	}, "9a_10_art.go")
}
