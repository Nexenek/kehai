package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Registered as "9g_16_portal.go" — see the NOTE ON THE REGISTERED NAME in
// 10_art.go (PocketBase sorts migrations by string name).
//
// Portal mode's signaling channel (kb/roadmap.md Phase 7, ADR in
// kb/decisions.md: raw WebRTC P2P for exactly two peers — no SFU). Before
// two devices can stream to each other they exchange a handful of small
// messages: a knock ("someone's at the window"), an accept/decline, then
// the WebRTC offer/answer SDPs and ICE candidates, and finally a hangup
// that drops the curtain on both sides. Each of those is simply a record
// here, delivered over the same PocketBase realtime subscription every
// other feature already rides — no separate signaling server.
//
// The media itself NEVER touches this collection or this server: WebRTC
// streams peer-to-peer (DTLS-SRTP encrypted), with coturn as an optional
// blind relay (see /api/turn in portal.go).
//
// Signals are moments, not history: purged after an hour (hourly cron),
// same lifecycle as thumb-kiss touches.
func init() {
	m.Register(func(app core.App) error {
		users, err := app.FindCollectionByNameOrId("users")
		if err != nil {
			return err
		}
		couples, err := app.FindCollectionByNameOrId("couples")
		if err != nil {
			return err
		}

		signals := core.NewBaseCollection("portal_signals")
		signals.Fields.Add(
			&core.RelationField{Name: "couple", CollectionId: couples.Id, MaxSelect: 1, Required: true},
			&core.RelationField{Name: "from", CollectionId: users.Id, MaxSelect: 1, Required: true},
			&core.SelectField{
				Name:      "kind",
				Required:  true,
				MaxSelect: 1,
				Values:    []string{"knock", "accept", "decline", "offer", "answer", "ice", "hangup"},
			},
			// SDPs are a few KB of text, candidates a line — JSON carries
			// both shapes without the server caring which.
			&core.JSONField{Name: "payload"},
			&core.AutodateField{Name: "created", OnCreate: true},
		)
		signals.AddIndex("idx_portal_signals_couple_created", false, "`couple`, `created`", "")

		coupleScoped := `@request.auth.id != "" && @request.auth.couple != "" && couple = @request.auth.couple`
		signals.ListRule = types.Pointer(coupleScoped)
		signals.ViewRule = types.Pointer(coupleScoped)
		// The forgery block every write-path collection here carries: you
		// can only signal as yourself, into your own couple.
		signals.CreateRule = types.Pointer(coupleScoped + ` && from = @request.auth.id`)
		// No update (a signal is immutable once sent), no client delete
		// (the purge cron owns cleanup).
		return app.Save(signals)
	}, func(app core.App) error {
		col, err := app.FindCollectionByNameOrId("portal_signals")
		if err != nil {
			return nil
		}
		return app.Delete(col)
	}, "9g_16_portal.go")
}
