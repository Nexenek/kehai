package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

// --- webhook receiver test double ------------------------------------------

// webhookReceipt is one POST captured by a receiver.
type webhookReceipt struct {
	body    []byte
	headers http.Header
}

// newWebhookReceiver starts an httptest server that stands in for a smart-
// home hub (Home Assistant, ntfy, ...). Every POST it gets is decoded and
// pushed onto the returned channel (buffered, so the delivery goroutine
// never blocks on a slow test). statusCode lets a test simulate a
// misbehaving/dead receiver (e.g. 500).
func newWebhookReceiver(t *testing.T, statusCode int, delay time.Duration) (*httptest.Server, <-chan webhookReceipt) {
	t.Helper()

	ch := make(chan webhookReceipt, 20)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		if delay > 0 {
			time.Sleep(delay)
		}
		w.WriteHeader(statusCode)
		ch <- webhookReceipt{body: body, headers: r.Header.Clone()}
	}))
	t.Cleanup(srv.Close)

	return srv, ch
}

func waitWebhook(t *testing.T, ch <-chan webhookReceipt, timeout time.Duration) webhookReceipt {
	t.Helper()
	select {
	case r := <-ch:
		return r
	case <-time.After(timeout):
		t.Fatal("timed out waiting for webhook delivery")
		return webhookReceipt{}
	}
}

func expectNoWebhook(t *testing.T, ch <-chan webhookReceipt, wait time.Duration) {
	t.Helper()
	select {
	case r := <-ch:
		t.Fatalf("expected no webhook, but got one: %s", string(r.body))
	case <-time.After(wait):
	}
}

func hmacHex(t *testing.T, secret string, body []byte) string {
	t.Helper()
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write(body)
	return hex.EncodeToString(mac.Sum(nil))
}

// --- mood_changed ------------------------------------------------------

func TestWebhookMoodChangedFiresWithSignature(t *testing.T) {
	receiver, ch := newWebhookReceiver(t, http.StatusOK, 0)
	t.Setenv("KEHAI_WEBHOOK_URLS", receiver.URL)
	t.Setenv("KEHAI_WEBHOOK_SECRET", "s3cr3t-lamp-key")

	app := newTestApp(t)
	srv := newTestServer(t, app)

	userID, token := registerAndLogin(t, srv.URL, uniqueEmail(t), "password1234")

	res := doJSON(t, http.MethodPost, srv.URL+"/api/collections/statuses/records", token, map[string]any{
		"user": userID,
		"mood": "content_kitten",
		"note": "feeling good today",
	})
	created := decodeJSON(t, res)
	if res.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 creating status, got %d: %v", res.StatusCode, created)
	}

	receipt := waitWebhook(t, ch, 2*time.Second)

	var payload map[string]any
	if err := json.Unmarshal(receipt.body, &payload); err != nil {
		t.Fatalf("failed to decode webhook payload: %v (body=%s)", err, receipt.body)
	}

	if got := payload["event"]; got != "mood_changed" {
		t.Fatalf("expected event mood_changed, got %v", got)
	}
	if got := payload["user"]; got != userID {
		t.Fatalf("expected user %q, got %v", userID, got)
	}
	// no "name" was ever set on the account, so user_name falls back to email.
	if got, _ := payload["user_name"].(string); got == "" {
		t.Fatalf("expected non-empty user_name (email fallback), got %v", payload["user_name"])
	}
	if got := payload["mood"]; got != "content_kitten" {
		t.Fatalf("expected mood content_kitten, got %v", got)
	}
	if got := payload["note"]; got != "feeling good today" {
		t.Fatalf("expected note 'feeling good today', got %v", got)
	}
	at, _ := payload["at"].(string)
	if _, err := time.Parse(time.RFC3339, at); err != nil {
		t.Fatalf("expected RFC3339 'at', got %q: %v", at, err)
	}

	// signature must be hex(hmac-sha256(secret, raw body)).
	wantSig := hmacHex(t, "s3cr3t-lamp-key", receipt.body)
	if got := receipt.headers.Get("X-Kehai-Signature"); got != wantSig {
		t.Fatalf("expected signature %q, got %q", wantSig, got)
	}
}

func TestWebhookMoodChangedFiresOnUpdateToo(t *testing.T) {
	receiver, ch := newWebhookReceiver(t, http.StatusOK, 0)
	t.Setenv("KEHAI_WEBHOOK_URLS", receiver.URL)

	app := newTestApp(t)
	srv := newTestServer(t, app)

	userID, token := registerAndLogin(t, srv.URL, uniqueEmail(t), "password1234")

	created := decodeJSON(t, doJSON(t, http.MethodPost, srv.URL+"/api/collections/statuses/records", token, map[string]any{
		"user": userID,
		"mood": "sleepy",
	}))
	statusID, _ := created["id"].(string)
	if statusID == "" {
		t.Fatalf("status create response missing id: %v", created)
	}
	waitWebhook(t, ch, 2*time.Second) // drain the create event

	res := doJSON(t, http.MethodPatch, srv.URL+"/api/collections/statuses/records/"+statusID, token, map[string]any{
		"mood": "excited",
	})
	if res.StatusCode != http.StatusOK {
		body := decodeJSON(t, res)
		t.Fatalf("expected 200 updating status, got %d: %v", res.StatusCode, body)
	}

	receipt := waitWebhook(t, ch, 2*time.Second)
	var payload map[string]any
	if err := json.Unmarshal(receipt.body, &payload); err != nil {
		t.Fatalf("failed to decode webhook payload: %v", err)
	}
	if got := payload["mood"]; got != "excited" {
		t.Fatalf("expected updated mood 'excited', got %v", got)
	}
}

// --- presence_changed ----------------------------------------------------

func TestWebhookPresenceChangedOnActivity(t *testing.T) {
	receiver, ch := newWebhookReceiver(t, http.StatusOK, 0)
	t.Setenv("KEHAI_WEBHOOK_URLS", receiver.URL)

	app := newTestApp(t)
	srv := newTestServer(t, app)

	userID, token := registerAndLogin(t, srv.URL, uniqueEmail(t), "password1234")

	// first heartbeat creates the device — a create, not an update, so no
	// presence_changed should fire yet.
	created := decodeJSON(t, doJSON(t, http.MethodPost, srv.URL+"/api/heartbeat", token, map[string]any{
		"kind": "desktop",
		"name": "Workstation",
	}))
	if created["device_id"] == nil || created["device_id"] == "" {
		t.Fatalf("heartbeat response missing device_id: %v", created)
	}
	expectNoWebhook(t, ch, 300*time.Millisecond)

	// a second heartbeat that changes activity is an update -> should fire.
	res := doJSON(t, http.MethodPost, srv.URL+"/api/heartbeat", token, map[string]any{
		"kind":     "desktop",
		"name":     "Workstation",
		"activity": "🎮 gaming",
	})
	if res.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 on heartbeat, got %d", res.StatusCode)
	}

	receipt := waitWebhook(t, ch, 2*time.Second)
	var payload map[string]any
	if err := json.Unmarshal(receipt.body, &payload); err != nil {
		t.Fatalf("failed to decode webhook payload: %v", err)
	}
	if got := payload["event"]; got != "presence_changed" {
		t.Fatalf("expected event presence_changed, got %v", got)
	}
	if got := payload["user"]; got != userID {
		t.Fatalf("expected user %q, got %v", userID, got)
	}
	if got := payload["kind"]; got != "desktop" {
		t.Fatalf("expected kind desktop, got %v", got)
	}
	if got := payload["activity"]; got != "🎮 gaming" {
		t.Fatalf("expected activity '🎮 gaming', got %v", got)
	}
	if got := payload["now_playing"]; got != nil {
		t.Fatalf("expected nil now_playing, got %v", got)
	}

	// a heartbeat that changes nothing power-user-relevant (just last_seen)
	// must stay silent.
	res2 := doJSON(t, http.MethodPost, srv.URL+"/api/heartbeat", token, map[string]any{
		"kind": "desktop",
		"name": "Workstation",
	})
	if res2.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 on plain heartbeat, got %d", res2.StatusCode)
	}
	expectNoWebhook(t, ch, 300*time.Millisecond)
}

func TestWebhookDebounceCollapsesRapidUpdates(t *testing.T) {
	receiver, ch := newWebhookReceiver(t, http.StatusOK, 0)
	t.Setenv("KEHAI_WEBHOOK_URLS", receiver.URL)

	app := newTestApp(t)
	srv := newTestServer(t, app)

	_, token := registerAndLogin(t, srv.URL, uniqueEmail(t), "password1234")

	doJSON(t, http.MethodPost, srv.URL+"/api/heartbeat", token, map[string]any{
		"kind": "desktop",
		"name": "Workstation",
	})

	// first activity change: fires, and starts the 10s debounce window.
	doJSON(t, http.MethodPost, srv.URL+"/api/heartbeat", token, map[string]any{
		"kind":     "desktop",
		"name":     "Workstation",
		"activity": "gaming",
	})
	first := waitWebhook(t, ch, 2*time.Second)
	var firstPayload map[string]any
	json.Unmarshal(first.body, &firstPayload)
	if firstPayload["activity"] != "gaming" {
		t.Fatalf("expected first activity 'gaming', got %v", firstPayload["activity"])
	}

	// rapid follow-up activity changes within the debounce window must be
	// collapsed (not delivered at all in v1 — no queued trailing send).
	for i, act := range []string{"coding", "browsing", "afk"} {
		res := doJSON(t, http.MethodPost, srv.URL+"/api/heartbeat", token, map[string]any{
			"kind":     "desktop",
			"name":     "Workstation",
			"activity": act,
		})
		if res.StatusCode != http.StatusOK {
			t.Fatalf("heartbeat %d failed: %d", i, res.StatusCode)
		}
	}
	expectNoWebhook(t, ch, 500*time.Millisecond)
}

// --- feature-off default --------------------------------------------------

func TestWebhookEmptyEnvFiresNothing(t *testing.T) {
	receiver, ch := newWebhookReceiver(t, http.StatusOK, 0)
	// deliberately NOT setting KEHAI_WEBHOOK_URLS: zero-config off-by-default.
	_ = receiver

	app := newTestApp(t)
	srv := newTestServer(t, app)

	userID, token := registerAndLogin(t, srv.URL, uniqueEmail(t), "password1234")

	doJSON(t, http.MethodPost, srv.URL+"/api/collections/statuses/records", token, map[string]any{
		"user": userID,
		"mood": "happy",
	})
	doJSON(t, http.MethodPost, srv.URL+"/api/heartbeat", token, map[string]any{
		"kind": "phone",
		"name": "Pixel",
	})
	doJSON(t, http.MethodPost, srv.URL+"/api/heartbeat", token, map[string]any{
		"kind":     "phone",
		"name":     "Pixel",
		"activity": "gaming",
	})

	expectNoWebhook(t, ch, 500*time.Millisecond)
}

// --- fire-and-forget: a dead/slow receiver must never slow the API down ---

func TestWebhookSlowReceiverDoesNotSlowSave(t *testing.T) {
	// receiver takes way longer than any reasonable API response time, and
	// answers with a 500 to boot.
	receiver, ch := newWebhookReceiver(t, http.StatusInternalServerError, 2*time.Second)
	t.Setenv("KEHAI_WEBHOOK_URLS", receiver.URL)

	app := newTestApp(t)
	srv := newTestServer(t, app)

	userID, token := registerAndLogin(t, srv.URL, uniqueEmail(t), "password1234")

	start := time.Now()
	res := doJSON(t, http.MethodPost, srv.URL+"/api/collections/statuses/records", token, map[string]any{
		"user": userID,
		"mood": "chill",
	})
	elapsed := time.Since(start)
	if res.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 creating status even with a dead webhook receiver, got %d", res.StatusCode)
	}
	if elapsed > 500*time.Millisecond {
		t.Fatalf("expected the record save to return fast regardless of receiver slowness, took %v", elapsed)
	}

	// the slow/failing delivery still eventually happens in the background.
	waitWebhook(t, ch, 3*time.Second)
}
