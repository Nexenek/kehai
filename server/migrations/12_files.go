package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Phase 4b — shared file storage (kb/features.md "Shared file storage"):
// a simple shared drive backed directly by a PocketBase file field, rather
// than a bespoke upload pipeline. Immutable v1, same "create + delete only"
// shape as doodles/instants (server/migrations/4_doodles.go,
// 5_location_instants.go) — no UpdateRule; re-upload a new record instead
// of editing one.
//
// The underlying file is Protected: PocketBase's default behavior serves
// collection files off a plain, unauthenticated `/api/files/...` URL (the
// only "protection" being an unguessable random suffix in the stored
// filename — see core.FileField's Protected doc comment: "by default all
// files are publicly accessible... this is fine because... file names have
// a random part appended... which need to be known by the user before
// accessing the file"). That's not good enough for a couple's private
// files sitting in a shared-hosting/Tailscale environment where the base
// URL is already semi-known. Protected: true instead requires a
// short-lived per-request file token from `POST /api/files/token`
// (auth required) appended as `?token=...` on the download URL — PocketBase
// then re-checks the collection's ViewRule against the token's auth record
// on every download, so an outsider (or an unauthenticated fetch) can never
// pull a file even if they have the URL. See server/files_test.go's
// TestSharedFileProtectedAccess for the exercised flow.
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

		files := core.NewBaseCollection("shared_files")
		files.Fields.Add(
			&core.RelationField{Name: "couple", CollectionId: couples.Id, MaxSelect: 1, Required: true},
			&core.FileField{
				Name:      "file",
				MaxSelect: 1,
				MaxSize:   100 << 20, // 100MB — a general shared drive, not a photo feed
				// MimeTypes intentionally left empty: any file type is
				// allowed (kb/features.md just says "simple shared drive").
				Protected: true,
				Required:  true,
			},
			// Defaults to the picked filename app-side (see
			// shared_file_repository.dart's `create`) — not enforced
			// server-side so a re-label-only flow stays possible later.
			&core.TextField{Name: "label", Max: 120},
			&core.RelationField{Name: "uploaded_by", CollectionId: users.Id, MaxSelect: 1, Required: true},
			&core.AutodateField{Name: "created", OnCreate: true},
		)
		files.ListRule = types.Pointer(coupleScoped)
		files.ViewRule = types.Pointer(coupleScoped)
		// Forgery-blocked the same way as doodles.author: the create rule
		// pins uploaded_by to the caller's own id, so B can't upload a file
		// stamped as authored by A.
		files.CreateRule = types.Pointer(coupleScoped + ` && uploaded_by = @request.auth.id`)
		files.DeleteRule = types.Pointer(coupleScoped)
		// UpdateRule stays nil: immutable — re-upload instead of editing.
		return app.Save(files)
	}, func(app core.App) error {
		col, err := app.FindCollectionByNameOrId("shared_files")
		if err == nil {
			if err := app.Delete(col); err != nil {
				return err
			}
		}
		return nil
	}, "9c_12_files.go")
	// NOTE ON THE REGISTERED NAME (the third m.Register argument above):
	// PocketBase sorts migrations by plain string comparison of the
	// registered file name, so a literal "12_files.go" would sort BEFORE
	// "1_init.go" (comparing byte-by-byte, '2' < '_') and run before the
	// `couples`/`users` collections this migration depends on even exist —
	// see 9b_11_calendar.go's identical note. Following that established
	// convention (10 → "9a_*", 11 → "9b_11_*.go", 12 → "9c_12_*.go"), this
	// one registers as "9c_12_files.go" so it lands after
	// 9_questions.go/9b_11_calendar.go while the source file keeps its
	// human-readable 12_* number.
}
