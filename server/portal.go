package main

import (
	"crypto/hmac"
	"crypto/sha1"
	"encoding/base64"
	"fmt"
	"net/http"
	"os"
	"time"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Portal mode's server half beyond the signals collection (see
// migrations/16_portal.go): TURN credentials and signal cleanup.
//
// TURN is the fallback path for when the two peers can't reach each other
// directly (no shared tailnet, hotel wifi, CGNAT): a coturn relay on the
// home server that shovels the still-encrypted stream through. The app
// asks GET /api/turn for connection details; with KEHAI_TURN_SECRET unset
// the endpoint answers an empty server list and the app proceeds with
// host/STUN candidates only — which is all a Tailscale-to-Tailscale pair
// ever needs, so the feature is OFF by default like every optional service
// (kb/selfhosting.md).
//
// Credentials use coturn's REST-auth scheme (`use-auth-secret`): the
// username is an expiry unix timestamp (+ a label), the password is
// base64(HMAC-SHA1(secret, username)). coturn derives the same HMAC from
// its own copy of the secret, so nothing is stored per-user and every
// credential self-expires — the app never holds a long-lived TURN password
// it could leak.

const (
	turnEnvSecret = "KEHAI_TURN_SECRET"
	// Comma-separated turn/stun URLs, e.g.
	// "turn:home.example:3478?transport=udp,turn:home.example:3478?transport=tcp".
	turnEnvURLs = "KEHAI_TURN_URLS"

	// How long a handed-out credential stays valid. Long enough to cover a
	// whole portal session comfortably (ICE only needs it at connect and
	// on network changes), short enough that a leaked one goes stale the
	// same day.
	turnCredentialTTL = 6 * time.Hour
)

// turnCredentials answers ICE server config for the authed user. Shape
// mirrors what flutter_webrtc feeds RTCPeerConnection:
//
//	{"iceServers": [{"urls": [...], "username": "...", "credential": "..."}]}
//
// An empty iceServers list means "no TURN configured" — never an error, so
// the client needs no special-casing to work tailnet-only.
func turnCredentials(e *core.RequestEvent) error {
	secret := os.Getenv(turnEnvSecret)
	urls := parseWebhookURLs(os.Getenv(turnEnvURLs)) // same comma-split+trim
	if secret == "" || len(urls) == 0 {
		return e.JSON(http.StatusOK, map[string]any{"iceServers": []any{}})
	}

	expiry := time.Now().Add(turnCredentialTTL).Unix()
	// coturn splits on the FIRST colon for the timestamp when
	// `rest-api-separator` is default; "<expiry>:<label>" is its
	// documented username shape.
	username := fmt.Sprintf("%d:kehai-%s", expiry, e.Auth.Id)
	mac := hmac.New(sha1.New, []byte(secret))
	mac.Write([]byte(username))
	credential := base64.StdEncoding.EncodeToString(mac.Sum(nil))

	return e.JSON(http.StatusOK, map[string]any{
		"iceServers": []any{
			map[string]any{
				"urls":       urls,
				"username":   username,
				"credential": credential,
			},
		},
	})
}

// Signals are ephemeral by design — an hour is already generous for a
// handshake that completes in seconds (same stance as touches.go).
const portalSignalRetention = time.Hour

func purgeOldPortalSignals(app core.App) error {
	cutoff, err := types.ParseDateTime(time.Now().Add(-portalSignalRetention).UTC())
	if err != nil {
		return err
	}
	_, err = app.DB().NewQuery("DELETE FROM portal_signals WHERE created < {:cutoff}").
		Bind(map[string]any{"cutoff": cutoff.String()}).Execute()
	return err
}
