package main

import (
	"crypto/hmac"
	"crypto/sha1"
	"encoding/base64"
	"net/http"
	"strconv"
	"strings"
	"testing"
)

func TestPortalSignalsCoupleScopedAndForgeryBlocked(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	idA, tokenA, idB, tokenB, coupleID := pairedCoupleWithIDs(t, srv.URL)

	// A knocks.
	res := doJSON(t, http.MethodPost, srv.URL+"/api/collections/portal_signals/records", tokenA, map[string]any{
		"couple": coupleID, "from": idA, "kind": "knock",
	})
	body := decodeJSON(t, res)
	if res.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 creating a knock, got %d: %v", res.StatusCode, body)
	}
	signalID, _ := body["id"].(string)

	// B sees it over the couple-scoped read.
	res = doJSON(t, http.MethodGet, srv.URL+"/api/collections/portal_signals/records", tokenB, nil)
	listBody := decodeJSON(t, res)
	items, _ := listBody["items"].([]any)
	if res.StatusCode != http.StatusOK || len(items) != 1 {
		t.Fatalf("expected partner to list exactly the one signal, got %d: %v", res.StatusCode, listBody)
	}

	// Forgery: B cannot signal AS A.
	res = doJSON(t, http.MethodPost, srv.URL+"/api/collections/portal_signals/records", tokenB, map[string]any{
		"couple": coupleID, "from": idA, "kind": "hangup",
	})
	if res.StatusCode == http.StatusOK {
		t.Fatalf("expected forged-from signal to be rejected")
	}
	res.Body.Close()

	// Immutable: no update path at all.
	res = doJSON(t, http.MethodPatch, srv.URL+"/api/collections/portal_signals/records/"+signalID, tokenA, map[string]any{
		"kind": "hangup",
	})
	if res.StatusCode == http.StatusOK {
		t.Fatalf("expected signal update to be rejected")
	}
	res.Body.Close()

	// No client delete either — the purge cron owns cleanup.
	res = doJSON(t, http.MethodDelete, srv.URL+"/api/collections/portal_signals/records/"+signalID, tokenA, nil)
	if res.StatusCode == http.StatusOK || res.StatusCode == http.StatusNoContent {
		t.Fatalf("expected signal delete to be rejected, got %d", res.StatusCode)
	}
	res.Body.Close()

	// Outsider couple sees nothing and cannot write into ours.
	_, outsiderToken := registerAndLogin(t, srv.URL, uniqueEmail(t), "password1234")
	res = doJSON(t, http.MethodPost, srv.URL+"/api/couple/create", outsiderToken, map[string]any{"name": "them"})
	res.Body.Close()
	res = doJSON(t, http.MethodGet, srv.URL+"/api/collections/portal_signals/records", outsiderToken, nil)
	outBody := decodeJSON(t, res)
	outItems, _ := outBody["items"].([]any)
	if len(outItems) != 0 {
		t.Fatalf("outsider must see no signals, got %v", outBody)
	}
	_ = idB
}

func TestPortalSignalPayloadRoundTrips(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	idA, tokenA, _, tokenB, coupleID := pairedCoupleWithIDs(t, srv.URL)

	res := doJSON(t, http.MethodPost, srv.URL+"/api/collections/portal_signals/records", tokenA, map[string]any{
		"couple": coupleID, "from": idA, "kind": "offer",
		"payload": map[string]any{"sdp": "v=0\r\no=- 46117 2 IN IP4 127.0.0.1", "type": "offer"},
	})
	body := decodeJSON(t, res)
	if res.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 creating an offer, got %d: %v", res.StatusCode, body)
	}

	res = doJSON(t, http.MethodGet, srv.URL+"/api/collections/portal_signals/records", tokenB, nil)
	listBody := decodeJSON(t, res)
	items, _ := listBody["items"].([]any)
	payload, _ := items[0].(map[string]any)["payload"].(map[string]any)
	if payload["type"] != "offer" || !strings.HasPrefix(payload["sdp"].(string), "v=0") {
		t.Fatalf("expected the SDP payload back intact, got %v", items[0])
	}
}

func TestTurnEndpointOffByDefault(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	t.Setenv(turnEnvSecret, "")
	t.Setenv(turnEnvURLs, "")

	_, token := registerAndLogin(t, srv.URL, uniqueEmail(t), "password1234")
	res := doJSON(t, http.MethodGet, srv.URL+"/api/turn", token, nil)
	body := decodeJSON(t, res)
	if res.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 from /api/turn, got %d: %v", res.StatusCode, body)
	}
	servers, ok := body["iceServers"].([]any)
	if !ok || len(servers) != 0 {
		t.Fatalf("expected empty iceServers with TURN unconfigured, got %v", body)
	}

	// And auth is required at all.
	res = doJSON(t, http.MethodGet, srv.URL+"/api/turn", "", nil)
	if res.StatusCode == http.StatusOK {
		t.Fatalf("expected /api/turn to require auth")
	}
	res.Body.Close()
}

func TestTurnEndpointHandsOutValidRestAuthCredentials(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	const secret = "test-turn-secret"
	t.Setenv(turnEnvSecret, secret)
	t.Setenv(turnEnvURLs, "turn:home.example:3478?transport=udp, turn:home.example:3478?transport=tcp")

	_, token := registerAndLogin(t, srv.URL, uniqueEmail(t), "password1234")
	res := doJSON(t, http.MethodGet, srv.URL+"/api/turn", token, nil)
	body := decodeJSON(t, res)
	if res.StatusCode != http.StatusOK {
		t.Fatalf("expected 200, got %d: %v", res.StatusCode, body)
	}
	servers, _ := body["iceServers"].([]any)
	if len(servers) != 1 {
		t.Fatalf("expected one ice server entry, got %v", body)
	}
	server, _ := servers[0].(map[string]any)
	urls, _ := server["urls"].([]any)
	if len(urls) != 2 {
		t.Fatalf("expected both TURN urls, got %v", server["urls"])
	}

	username, _ := server["username"].(string)
	credential, _ := server["credential"].(string)

	// Username: "<future unix expiry>:kehai-<uid>" — coturn's REST shape.
	parts := strings.SplitN(username, ":", 2)
	if len(parts) != 2 || !strings.HasPrefix(parts[1], "kehai-") {
		t.Fatalf("unexpected TURN username shape: %q", username)
	}
	expiry, err := strconv.ParseInt(parts[0], 10, 64)
	if err != nil || expiry < 1_000_000_000 {
		t.Fatalf("expected a unix expiry timestamp, got %q", parts[0])
	}

	// The credential must be exactly what coturn will derive on its side.
	mac := hmac.New(sha1.New, []byte(secret))
	mac.Write([]byte(username))
	want := base64.StdEncoding.EncodeToString(mac.Sum(nil))
	if credential != want {
		t.Fatalf("credential is not HMAC-SHA1(secret, username): got %q want %q", credential, want)
	}
}
