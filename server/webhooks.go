package main

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Outbound webhooks — the smart-home / power-user hook documented in
// kb/features.md "Smart-lamp / power-user API" and kb/apis-external.md
// "Our own outbound API". Self-hosted-friendly zero-config default:
// KEHAI_WEBHOOK_URLS unset (or empty) means the whole feature is off — no
// hooks are even registered, so a heartbeat or status save never pays for
// work it doesn't need.
const (
	webhookEnvURLs     = "KEHAI_WEBHOOK_URLS"
	webhookEnvSecret   = "KEHAI_WEBHOOK_SECRET"
	webhookHTTPTimeout = 5 * time.Second
	webhookDebounce    = 10 * time.Second
	webhookSigHeader   = "X-Kehai-Signature"
)

// bindWebhooks wires the outbound-webhook hooks onto app. It is a no-op
// (nothing registered at all) when KEHAI_WEBHOOK_URLS is empty.
func bindWebhooks(app core.App) {
	urls := parseWebhookURLs(os.Getenv(webhookEnvURLs))
	if len(urls) == 0 {
		return
	}
	secret := os.Getenv(webhookEnvSecret)
	presence := newWebhookDebouncer()

	// mood_changed: every statuses create/update fires — mood is the whole
	// point of the record, there's nothing to debounce against (a partner
	// mashing the mood picker is rare and each tap is a deliberate event).
	app.OnRecordAfterCreateSuccess("statuses").BindFunc(func(e *core.RecordEvent) error {
		fireMoodChanged(e.App, e.Record, urls, secret)
		return e.Next()
	})
	app.OnRecordAfterUpdateSuccess("statuses").BindFunc(func(e *core.RecordEvent) error {
		fireMoodChanged(e.App, e.Record, urls, secret)
		return e.Next()
	})

	// presence_changed: devices get a heartbeat every few seconds, so this
	// one both filters (only activity/now_playing changes count) and
	// debounces (max once per user per webhookDebounce window).
	app.OnRecordAfterUpdateSuccess("devices").BindFunc(func(e *core.RecordEvent) error {
		firePresenceChanged(e.App, e.Record, urls, secret, presence)
		return e.Next()
	})
}

// parseWebhookURLs splits and trims a comma-separated URL list, dropping
// empty entries. An empty/whitespace-only value yields a nil (feature-off)
// slice.
func parseWebhookURLs(raw string) []string {
	var urls []string
	for _, part := range strings.Split(raw, ",") {
		part = strings.TrimSpace(part)
		if part != "" {
			urls = append(urls, part)
		}
	}
	return urls
}

// webhookDebouncer collapses rapid-fire events for the same key within
// webhookDebounce. A plain in-memory map + mutex is enough — Kehai runs as
// a single process (kb/selfhosting.md).
type webhookDebouncer struct {
	mu   sync.Mutex
	last map[string]time.Time
}

func newWebhookDebouncer() *webhookDebouncer {
	return &webhookDebouncer{last: make(map[string]time.Time)}
}

// allow reports whether an event for key may fire now, stamping key as
// just-fired if so. A call within webhookDebounce of the last allowed call
// for the same key is collapsed (returns false).
func (d *webhookDebouncer) allow(key string) bool {
	d.mu.Lock()
	defer d.mu.Unlock()

	now := time.Now()
	if last, ok := d.last[key]; ok && now.Sub(last) < webhookDebounce {
		return false
	}
	d.last[key] = now
	return true
}

// fireMoodChanged sends the mood_changed event for a statuses record.
func fireMoodChanged(app core.App, record *core.Record, urls []string, secret string) {
	userID := record.GetString("user")
	payload := map[string]any{
		"event":     "mood_changed",
		"user":      userID,
		"user_name": resolveUserName(app, userID),
		"mood":      record.GetString("mood"),
		"note":      record.GetString("note"),
		"at":        time.Now().UTC().Format(time.RFC3339),
	}
	sendWebhooks(app, urls, secret, payload)
}

// firePresenceChanged sends the presence_changed event for a devices
// record, but only when a field power users actually script against
// (activity, now_playing) changed — a bare last_seen heartbeat stays
// silent — and only once per user within webhookDebounce.
func firePresenceChanged(app core.App, record *core.Record, urls []string, secret string, debounce *webhookDebouncer) {
	original := record.Original()

	activityChanged := record.GetString("activity") != original.GetString("activity")
	nowPlayingChanged := !jsonEqual(record.Get("now_playing"), original.Get("now_playing"))
	if !activityChanged && !nowPlayingChanged {
		return
	}

	userID := record.GetString("owner")
	if !debounce.allow("presence_changed:" + userID) {
		return
	}

	payload := map[string]any{
		"event":       "presence_changed",
		"user":        userID,
		"user_name":   resolveUserName(app, userID),
		"kind":        record.GetString("kind"),
		"activity":    record.GetString("activity"),
		"now_playing": jsonValue(record.Get("now_playing")),
		"at":          time.Now().UTC().Format(time.RFC3339),
	}
	sendWebhooks(app, urls, secret, payload)
}

// resolveUserName looks up a display name for a user id, falling back to
// their email when "name" was never set. The built-in users auth
// collection always has a "name" text field (seeded by PocketBase itself).
func resolveUserName(app core.App, userID string) string {
	user, err := app.FindRecordById("users", userID)
	if err != nil {
		return ""
	}
	if name := user.GetString("name"); name != "" {
		return name
	}
	return user.GetString("email")
}

// jsonEqual compares two JSONField values (types.JSONRaw under the hood) by
// their canonical JSON encoding.
func jsonEqual(a, b any) bool {
	return jsonString(a) == jsonString(b)
}

func jsonString(v any) string {
	if raw, ok := v.(types.JSONRaw); ok {
		return raw.String()
	}
	if v == nil {
		return "null"
	}
	b, err := json.Marshal(v)
	if err != nil {
		return ""
	}
	return string(b)
}

// jsonValue decodes a JSONField value (types.JSONRaw) into a plain Go value
// suitable for embedding in an outbound payload: nil for an empty/null/
// empty-object value (now_playing cleared), otherwise the decoded object.
func jsonValue(v any) any {
	raw, ok := v.(types.JSONRaw)
	if !ok || len(raw) == 0 {
		return nil
	}
	var out any
	if err := json.Unmarshal(raw, &out); err != nil {
		return nil
	}
	if m, ok := out.(map[string]any); ok && len(m) == 0 {
		return nil
	}
	return out
}

// sendWebhooks POSTs payload as JSON to every configured URL, fire-and-
// forget: one goroutine per URL, a webhookHTTPTimeout timeout, failures
// logged at debug level only. A dead lamp must never slow down a heartbeat
// or status save, and v1 does no retries.
func sendWebhooks(app core.App, urls []string, secret string, payload map[string]any) {
	body, err := json.Marshal(payload)
	if err != nil {
		app.Logger().Debug("webhook: failed to marshal payload", "error", err)
		return
	}

	var signature string
	if secret != "" {
		mac := hmac.New(sha256.New, []byte(secret))
		mac.Write(body)
		signature = hex.EncodeToString(mac.Sum(nil))
	}

	for _, url := range urls {
		go deliverWebhook(app, url, body, signature)
	}
}

func deliverWebhook(app core.App, url string, body []byte, signature string) {
	client := &http.Client{Timeout: webhookHTTPTimeout}

	req, err := http.NewRequest(http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		app.Logger().Debug("webhook: failed to build request", "url", url, "error", err)
		return
	}
	req.Header.Set("Content-Type", "application/json")
	if signature != "" {
		req.Header.Set(webhookSigHeader, signature)
	}

	res, err := client.Do(req)
	if err != nil {
		app.Logger().Debug("webhook: delivery failed", "url", url, "error", err)
		return
	}
	defer res.Body.Close()

	if res.StatusCode >= 300 {
		app.Logger().Debug("webhook: receiver returned non-2xx", "url", url, "status", res.StatusCode)
	}
}
