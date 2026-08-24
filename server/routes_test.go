package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tests"
)

// --- test app / server plumbing ---------------------------------------

// newTestApp boots a fresh PocketBase app (our migrations included, since
// they're registered via main.go's blank import into the same package)
// against an empty, per-test temp data dir.
func newTestApp(t *testing.T) *tests.TestApp {
	t.Helper()

	app, err := tests.NewTestAppWithConfig(core.BaseAppConfig{
		DataDir:       t.TempDir(),
		EncryptionEnv: "pb_test_env",
	})
	if err != nil {
		t.Fatalf("failed to init test app: %v", err)
	}
	t.Cleanup(app.Cleanup)

	return app
}

// newTestServer wires our custom routes (bindRoutes) plus PocketBase's own
// API onto a real HTTP test server so tests can exercise the app exactly
// like a real client would.
func newTestServer(t *testing.T, app *tests.TestApp) *httptest.Server {
	t.Helper()

	bindRoutes(app)

	router, err := apis.NewRouter(app)
	if err != nil {
		t.Fatalf("failed to build router: %v", err)
	}

	serveEvent := &core.ServeEvent{App: app, Router: router}
	if err := app.OnServe().Trigger(serveEvent, func(e *core.ServeEvent) error {
		return e.Next()
	}); err != nil {
		t.Fatalf("failed to trigger serve event: %v", err)
	}

	mux, err := router.BuildMux()
	if err != nil {
		t.Fatalf("failed to build mux: %v", err)
	}

	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)

	return srv
}

// --- HTTP helpers -------------------------------------------------------

func doJSON(t *testing.T, method, url, token string, body any) *http.Response {
	t.Helper()

	var reader *bytes.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			t.Fatalf("failed to marshal body: %v", err)
		}
		reader = bytes.NewReader(b)
	} else {
		reader = bytes.NewReader(nil)
	}

	req, err := http.NewRequest(method, url, reader)
	if err != nil {
		t.Fatalf("failed to build request: %v", err)
	}
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", token)
	}

	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("request failed: %v", err)
	}
	return res
}

func decodeJSON(t *testing.T, res *http.Response) map[string]any {
	t.Helper()
	defer res.Body.Close()

	var out map[string]any
	if err := json.NewDecoder(res.Body).Decode(&out); err != nil {
		t.Fatalf("failed to decode response body: %v", err)
	}
	return out
}

// registerAndLogin creates a "users" record over the public HTTP API and
// exchanges its credentials for an auth token, exactly like a real client.
func registerAndLogin(t *testing.T, baseURL, email, password string) (userID, token string) {
	t.Helper()

	createRes := doJSON(t, http.MethodPost, baseURL+"/api/collections/users/records", "", map[string]any{
		"email":           email,
		"password":        password,
		"passwordConfirm": password,
	})
	created := decodeJSON(t, createRes)
	if createRes.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 creating user, got %d: %v", createRes.StatusCode, created)
	}
	userID, _ = created["id"].(string)
	if userID == "" {
		t.Fatalf("user create response missing id: %v", created)
	}

	authRes := doJSON(t, http.MethodPost, baseURL+"/api/collections/users/auth-with-password", "", map[string]any{
		"identity": email,
		"password": password,
	})
	authBody := decodeJSON(t, authRes)
	if authRes.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 authenticating user, got %d: %v", authRes.StatusCode, authBody)
	}
	token, _ = authBody["token"].(string)
	if token == "" {
		t.Fatalf("auth response missing token: %v", authBody)
	}

	return userID, token
}

func uniqueEmail(t *testing.T) string {
	t.Helper()
	return fmt.Sprintf("%s@example.test", strings.ToLower(strings.ReplaceAll(t.Name(), "/", "-")+fmt.Sprintf("%d", time.Now().UnixNano())))
}

// --- unit test: newInviteCode -------------------------------------------

func TestNewInviteCode(t *testing.T) {
	seen := make(map[string]bool)
	for i := 0; i < 200; i++ {
		code, err := newInviteCode()
		if err != nil {
			t.Fatalf("newInviteCode returned error: %v", err)
		}
		if len(code) != 6 {
			t.Fatalf("expected code of length 6, got %q (len %d)", code, len(code))
		}
		for _, c := range code {
			if !strings.ContainsRune(inviteAlphabet, c) {
				t.Fatalf("code %q contains character %q outside inviteAlphabet %q", code, c, inviteAlphabet)
			}
		}
		seen[code] = true
	}
	// not a strict guarantee, but 200 draws from a 32^6 space colliding
	// heavily would indicate a broken RNG.
	if len(seen) < 190 {
		t.Fatalf("suspiciously few unique codes out of 200 draws: %d", len(seen))
	}
}

// --- couple create / join ------------------------------------------------

func TestCreateCouple(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	_, token := registerAndLogin(t, srv.URL, uniqueEmail(t), "password1234")

	res := doJSON(t, http.MethodPost, srv.URL+"/api/couple/create", token, map[string]any{"name": "us ♡"})
	body := decodeJSON(t, res)
	if res.StatusCode != http.StatusOK {
		t.Fatalf("expected 200, got %d: %v", res.StatusCode, body)
	}

	coupleID, _ := body["couple_id"].(string)
	if coupleID == "" {
		t.Fatalf("response missing couple_id: %v", body)
	}
	inviteCode, _ := body["invite_code"].(string)
	if len(inviteCode) != 6 {
		t.Fatalf("expected 6-char invite_code, got %q", inviteCode)
	}

	// creating a second couple for the same (now-linked) user must fail
	res2 := doJSON(t, http.MethodPost, srv.URL+"/api/couple/create", token, map[string]any{"name": "again"})
	body2 := decodeJSON(t, res2)
	if res2.StatusCode != http.StatusBadRequest {
		t.Fatalf("expected 400 creating a second couple, got %d: %v", res2.StatusCode, body2)
	}
}

func TestJoinCouple(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	_, tokenA := registerAndLogin(t, srv.URL, uniqueEmail(t), "password1234")
	createRes := decodeJSON(t, doJSON(t, http.MethodPost, srv.URL+"/api/couple/create", tokenA, map[string]any{"name": "us"}))
	code, _ := createRes["invite_code"].(string)
	coupleID, _ := createRes["couple_id"].(string)
	if code == "" || coupleID == "" {
		t.Fatalf("failed to set up couple: %v", createRes)
	}

	userB, tokenB := registerAndLogin(t, srv.URL, uniqueEmail(t), "password1234")

	res := doJSON(t, http.MethodPost, srv.URL+"/api/couple/join", tokenB, map[string]any{"code": code})
	body := decodeJSON(t, res)
	if res.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 joining with a valid code, got %d: %v", res.StatusCode, body)
	}
	if got, _ := body["couple_id"].(string); got != coupleID {
		t.Fatalf("expected couple_id %q, got %q", coupleID, got)
	}

	// verify server-side that user B is actually linked to the couple
	userRec, err := app.FindRecordById("users", userB)
	if err != nil {
		t.Fatalf("failed to fetch user B record: %v", err)
	}
	if got := userRec.GetString("couple"); got != coupleID {
		t.Fatalf("expected user B's couple field to be %q, got %q", coupleID, got)
	}
}

func TestJoinCoupleBadCode(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	_, token := registerAndLogin(t, srv.URL, uniqueEmail(t), "password1234")

	res := doJSON(t, http.MethodPost, srv.URL+"/api/couple/join", token, map[string]any{"code": "ZZZZZZ"})
	body := decodeJSON(t, res)
	if res.StatusCode != http.StatusBadRequest {
		t.Fatalf("expected 400 joining with a bad code, got %d: %v", res.StatusCode, body)
	}
}

func TestJoinCoupleThirdMemberRejected(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	_, tokenA := registerAndLogin(t, srv.URL, uniqueEmail(t), "password1234")
	createRes := decodeJSON(t, doJSON(t, http.MethodPost, srv.URL+"/api/couple/create", tokenA, map[string]any{"name": "us"}))
	code, _ := createRes["invite_code"].(string)

	_, tokenB := registerAndLogin(t, srv.URL, uniqueEmail(t), "password1234")
	joinRes := doJSON(t, http.MethodPost, srv.URL+"/api/couple/join", tokenB, map[string]any{"code": code})
	if joinRes.StatusCode != http.StatusOK {
		t.Fatalf("expected second member to join fine, got %d", joinRes.StatusCode)
	}

	_, tokenC := registerAndLogin(t, srv.URL, uniqueEmail(t), "password1234")
	res := doJSON(t, http.MethodPost, srv.URL+"/api/couple/join", tokenC, map[string]any{"code": code})
	body := decodeJSON(t, res)
	if res.StatusCode != http.StatusBadRequest {
		t.Fatalf("expected 400 for a third member trying to join, got %d: %v", res.StatusCode, body)
	}
}

// --- heartbeat -------------------------------------------------------------

func TestHeartbeatCreatesThenUpdatesDevice(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	userID, token := registerAndLogin(t, srv.URL, uniqueEmail(t), "password1234")

	res1 := doJSON(t, http.MethodPost, srv.URL+"/api/heartbeat", token, map[string]any{"kind": "phone", "name": "Pixel"})
	body1 := decodeJSON(t, res1)
	if res1.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 on first heartbeat, got %d: %v", res1.StatusCode, body1)
	}
	deviceID1, _ := body1["device_id"].(string)
	lastSeen1, _ := body1["last_seen"].(string)
	if deviceID1 == "" || lastSeen1 == "" {
		t.Fatalf("first heartbeat response missing fields: %v", body1)
	}

	// make sure the second last_seen timestamp is observably different
	time.Sleep(5 * time.Millisecond)

	res2 := doJSON(t, http.MethodPost, srv.URL+"/api/heartbeat", token, map[string]any{"kind": "phone", "name": "Pixel"})
	body2 := decodeJSON(t, res2)
	if res2.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 on second heartbeat, got %d: %v", res2.StatusCode, body2)
	}
	deviceID2, _ := body2["device_id"].(string)
	lastSeen2, _ := body2["last_seen"].(string)

	if deviceID2 != deviceID1 {
		t.Fatalf("expected the same device to be reused, got %q then %q", deviceID1, deviceID2)
	}
	if lastSeen2 == lastSeen1 {
		t.Fatalf("expected last_seen to change between heartbeats, both were %q", lastSeen1)
	}

	// confirm there's exactly one device row for this owner (upsert, not duplicate)
	devices, err := app.FindRecordsByFilter("devices", "owner = {:owner}", "", 0, 0, dbx.Params{"owner": userID})
	if err != nil {
		t.Fatalf("failed to query devices: %v", err)
	}
	if len(devices) != 1 {
		t.Fatalf("expected exactly 1 device row after 2 heartbeats, got %d", len(devices))
	}
}

func TestHeartbeatRejectsUnknownKind(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	_, token := registerAndLogin(t, srv.URL, uniqueEmail(t), "password1234")

	res := doJSON(t, http.MethodPost, srv.URL+"/api/heartbeat", token, map[string]any{"kind": "toaster", "name": "x"})
	if res.StatusCode != http.StatusBadRequest {
		t.Fatalf("expected 400 for an unknown device kind, got %d", res.StatusCode)
	}
	res.Body.Close()
}

// --- auth is required at all -----------------------------------------------

// --- heartbeat telemetry (Phase 2a contract) -------------------------------

// getDevice fetches a single device record over the public HTTP API, the
// same way a client (or the partner) would.
func getDevice(t *testing.T, baseURL, token, id string) map[string]any {
	t.Helper()

	res := doJSON(t, http.MethodGet, baseURL+"/api/collections/devices/records/"+id, token, nil)
	body := decodeJSON(t, res)
	if res.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 fetching device %s, got %d: %v", id, res.StatusCode, body)
	}
	return body
}

func TestHeartbeatTelemetry(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	_, token := registerAndLogin(t, srv.URL, uniqueEmail(t), "password1234")
	// devices are only viewable by couple members (see coupleScoped in
	// 1_init.go), so pair this user up before reading telemetry back.
	setupRes := doJSON(t, http.MethodPost, srv.URL+"/api/couple/create", token, map[string]any{"name": "us"})
	setupRes.Body.Close()
	if setupRes.StatusCode != http.StatusOK {
		t.Fatalf("failed to set up couple: %d", setupRes.StatusCode)
	}

	res1 := doJSON(t, http.MethodPost, srv.URL+"/api/heartbeat", token, map[string]any{
		"kind":         "desktop",
		"name":         "Workstation",
		"battery":      55.0,
		"charging":     true,
		"idle_seconds": 12.0,
		"now_playing": map[string]any{
			"title": "Song", "artist": "Artist", "album": "Album", "player": "Spotify", "state": "playing",
		},
		"activity": "gaming",
	})
	body1 := decodeJSON(t, res1)
	if res1.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 on telemetry heartbeat, got %d: %v", res1.StatusCode, body1)
	}
	deviceID, _ := body1["device_id"].(string)
	if deviceID == "" {
		t.Fatalf("heartbeat response missing device_id: %v", body1)
	}

	device := getDevice(t, srv.URL, token, deviceID)
	if got, _ := device["battery"].(float64); got != 55 {
		t.Fatalf("expected battery 55, got %v", device["battery"])
	}
	if got, _ := device["charging"].(bool); got != true {
		t.Fatalf("expected charging true, got %v", device["charging"])
	}
	if got, _ := device["idle_seconds"].(float64); got != 12 {
		t.Fatalf("expected idle_seconds 12, got %v", device["idle_seconds"])
	}
	np, ok := device["now_playing"].(map[string]any)
	if !ok || np["title"] != "Song" {
		t.Fatalf("expected now_playing with title 'Song', got %v", device["now_playing"])
	}
	if got, _ := device["activity"].(string); got != "gaming" {
		t.Fatalf("expected activity 'gaming', got %v", device["activity"])
	}

	// a heartbeat that omits the telemetry keys entirely must leave the
	// previously-recorded values untouched (absent != clear).
	res2 := doJSON(t, http.MethodPost, srv.URL+"/api/heartbeat", token, map[string]any{
		"kind": "desktop",
		"name": "Workstation",
	})
	body2 := decodeJSON(t, res2)
	if res2.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 on key-less heartbeat, got %d: %v", res2.StatusCode, body2)
	}

	device2 := getDevice(t, srv.URL, token, deviceID)
	if got, _ := device2["battery"].(float64); got != 55 {
		t.Fatalf("expected battery to remain 55 after key-less heartbeat, got %v", device2["battery"])
	}
	if got, _ := device2["charging"].(bool); got != true {
		t.Fatalf("expected charging to remain true after key-less heartbeat, got %v", device2["charging"])
	}
	if got, _ := device2["activity"].(string); got != "gaming" {
		t.Fatalf("expected activity to remain 'gaming' after key-less heartbeat, got %v", device2["activity"])
	}
	np2, ok := device2["now_playing"].(map[string]any)
	if !ok || np2["title"] != "Song" {
		t.Fatalf("expected now_playing to remain set after key-less heartbeat, got %v", device2["now_playing"])
	}

	// an explicit null clears now_playing back to "nothing playing".
	res3 := doJSON(t, http.MethodPost, srv.URL+"/api/heartbeat", token, map[string]any{
		"kind":        "desktop",
		"name":        "Workstation",
		"now_playing": nil,
	})
	body3 := decodeJSON(t, res3)
	if res3.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 clearing now_playing, got %d: %v", res3.StatusCode, body3)
	}

	device3 := getDevice(t, srv.URL, token, deviceID)
	if device3["now_playing"] != nil {
		t.Fatalf("expected now_playing to be cleared to null, got %v", device3["now_playing"])
	}
	// unrelated fields sent on the same request untouched must still survive.
	if got, _ := device3["activity"].(string); got != "gaming" {
		t.Fatalf("expected activity to remain 'gaming' after clearing now_playing, got %v", device3["activity"])
	}
}

func TestHeartbeatInvalidBatteryRejected(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	_, token := registerAndLogin(t, srv.URL, uniqueEmail(t), "password1234")

	res := doJSON(t, http.MethodPost, srv.URL+"/api/heartbeat", token, map[string]any{
		"kind":    "phone",
		"name":    "Pixel",
		"battery": 150.0,
	})
	body := decodeJSON(t, res)
	if res.StatusCode != http.StatusBadRequest {
		t.Fatalf("expected 400 for battery=150, got %d: %v", res.StatusCode, body)
	}
}

func TestHeartbeatTelemetryVisibleToPartnerButNotOutsider(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	// A creates a couple and sends a heartbeat with telemetry.
	userA, tokenA := registerAndLogin(t, srv.URL, uniqueEmail(t), "password1234")
	createRes := decodeJSON(t, doJSON(t, http.MethodPost, srv.URL+"/api/couple/create", tokenA, map[string]any{"name": "us"}))
	code, _ := createRes["invite_code"].(string)
	if code == "" {
		t.Fatalf("failed to set up couple: %v", createRes)
	}

	hbRes := decodeJSON(t, doJSON(t, http.MethodPost, srv.URL+"/api/heartbeat", tokenA, map[string]any{
		"kind":     "desktop",
		"name":     "Workstation",
		"battery":  42.0,
		"activity": "gaming",
	}))
	deviceID, _ := hbRes["device_id"].(string)
	if deviceID == "" {
		t.Fatalf("heartbeat response missing device_id: %v", hbRes)
	}

	// B joins the couple and should see A's telemetry via the devices list.
	_, tokenB := registerAndLogin(t, srv.URL, uniqueEmail(t), "password1234")
	joinRes := doJSON(t, http.MethodPost, srv.URL+"/api/couple/join", tokenB, map[string]any{"code": code})
	if joinRes.StatusCode != http.StatusOK {
		t.Fatalf("expected partner to join fine, got %d", joinRes.StatusCode)
	}

	listRes := doJSON(t, http.MethodGet, srv.URL+"/api/collections/devices/records", tokenB, nil)
	listBody := decodeJSON(t, listRes)
	if listRes.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 listing devices as partner, got %d: %v", listRes.StatusCode, listBody)
	}
	items, _ := listBody["items"].([]any)
	found := false
	for _, item := range items {
		rec, _ := item.(map[string]any)
		if rec == nil {
			continue
		}
		if rec["owner"] == userA {
			found = true
			if got, _ := rec["battery"].(float64); got != 42 {
				t.Fatalf("expected partner to see battery 42, got %v", rec["battery"])
			}
			if got, _ := rec["activity"].(string); got != "gaming" {
				t.Fatalf("expected partner to see activity 'gaming', got %v", rec["activity"])
			}
		}
	}
	if !found {
		t.Fatalf("expected partner's device list to include A's device, got items: %v", items)
	}

	// C is not in any couple and must not be able to view A's device.
	_, tokenC := registerAndLogin(t, srv.URL, uniqueEmail(t), "password1234")
	viewRes := doJSON(t, http.MethodGet, srv.URL+"/api/collections/devices/records/"+deviceID, tokenC, nil)
	defer viewRes.Body.Close()
	if viewRes.StatusCode == http.StatusOK {
		t.Fatalf("expected outsider to be denied viewing A's device, got 200")
	}

	listResC := doJSON(t, http.MethodGet, srv.URL+"/api/collections/devices/records", tokenC, nil)
	listBodyC := decodeJSON(t, listResC)
	if listResC.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 listing devices as outsider, got %d: %v", listResC.StatusCode, listBodyC)
	}
	itemsC, _ := listBodyC["items"].([]any)
	if len(itemsC) != 0 {
		t.Fatalf("expected outsider's device list to be empty, got: %v", itemsC)
	}
}

func TestUnauthenticatedRequestsRejected(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	cases := []struct {
		name   string
		method string
		url    string
		body   any
	}{
		{"couple create", http.MethodPost, srv.URL + "/api/couple/create", map[string]any{"name": "us"}},
		{"couple join", http.MethodPost, srv.URL + "/api/couple/join", map[string]any{"code": "ABCDEF"}},
		{"heartbeat", http.MethodPost, srv.URL + "/api/heartbeat", map[string]any{"kind": "phone", "name": "x"}},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			res := doJSON(t, c.method, c.url, "", c.body)
			defer res.Body.Close()
			if res.StatusCode != http.StatusUnauthorized {
				t.Fatalf("expected 401 for unauthenticated %s, got %d", c.name, res.StatusCode)
			}
		})
	}
}

// --- heartbeat vitals (smartwatch wave, migration 14) ------------------------

func TestHeartbeatVitals(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	_, token := registerAndLogin(t, srv.URL, uniqueEmail(t), "password1234")
	setupRes := doJSON(t, http.MethodPost, srv.URL+"/api/couple/create", token, map[string]any{"name": "us"})
	setupRes.Body.Close()
	if setupRes.StatusCode != http.StatusOK {
		t.Fatalf("failed to set up couple: %d", setupRes.StatusCode)
	}

	res1 := doJSON(t, http.MethodPost, srv.URL+"/api/heartbeat", token, map[string]any{
		"kind":        "phone",
		"name":        "Pixel",
		"steps_today": 4231.0,
		"heart_rate":  map[string]any{"bpm": 72.0, "at": "2026-08-24T12:00:00Z"},
	})
	body1 := decodeJSON(t, res1)
	if res1.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 on vitals heartbeat, got %d: %v", res1.StatusCode, body1)
	}
	deviceID, _ := body1["device_id"].(string)

	device := getDevice(t, srv.URL, token, deviceID)
	if got, _ := device["steps_today"].(float64); got != 4231 {
		t.Fatalf("expected steps_today 4231, got %v", device["steps_today"])
	}
	hr, ok := device["heart_rate"].(map[string]any)
	if !ok || hr["bpm"] != 72.0 || hr["at"] != "2026-08-24T12:00:00Z" {
		t.Fatalf("expected heart_rate {72, 2026-08-24T12:00:00Z}, got %v", device["heart_rate"])
	}

	// absent keys leave vitals untouched; explicit null clears heart_rate.
	res2 := doJSON(t, http.MethodPost, srv.URL+"/api/heartbeat", token, map[string]any{
		"kind": "phone", "name": "Pixel",
	})
	res2.Body.Close()
	device2 := getDevice(t, srv.URL, token, deviceID)
	if got, _ := device2["steps_today"].(float64); got != 4231 {
		t.Fatalf("expected steps_today to survive a key-less heartbeat, got %v", device2["steps_today"])
	}
	if _, ok := device2["heart_rate"].(map[string]any); !ok {
		t.Fatalf("expected heart_rate to survive a key-less heartbeat, got %v", device2["heart_rate"])
	}

	res3 := doJSON(t, http.MethodPost, srv.URL+"/api/heartbeat", token, map[string]any{
		"kind": "phone", "name": "Pixel", "heart_rate": nil, "steps_today": nil,
	})
	res3.Body.Close()
	device3 := getDevice(t, srv.URL, token, deviceID)
	if device3["heart_rate"] != nil {
		t.Fatalf("expected heart_rate cleared to null, got %v", device3["heart_rate"])
	}
	if got, _ := device3["steps_today"].(float64); got != 0 {
		t.Fatalf("expected steps_today cleared to 0, got %v", device3["steps_today"])
	}

	// garbage is refused: bpm out of range, unparseable at, wrong shapes.
	for _, bad := range []any{
		map[string]any{"bpm": 500.0, "at": "2026-08-24T12:00:00Z"},
		map[string]any{"bpm": 72.0, "at": "yesterday-ish"},
		map[string]any{"bpm": 72.0},
		"72",
	} {
		res := doJSON(t, http.MethodPost, srv.URL+"/api/heartbeat", token, map[string]any{
			"kind": "phone", "name": "Pixel", "heart_rate": bad,
		})
		if res.StatusCode != http.StatusBadRequest {
			t.Fatalf("expected 400 for heart_rate %v, got %d", bad, res.StatusCode)
		}
		res.Body.Close()
	}
	res4 := doJSON(t, http.MethodPost, srv.URL+"/api/heartbeat", token, map[string]any{
		"kind": "phone", "name": "Pixel", "steps_today": -5.0,
	})
	if res4.StatusCode != http.StatusBadRequest {
		t.Fatalf("expected 400 for negative steps_today, got %d", res4.StatusCode)
	}
	res4.Body.Close()
}
