package main

import (
	"net/http"
	"testing"
	"time"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/types"
)

// --- timezone (devices.timezone via heartbeat) -----------------------------

func TestHeartbeatTimezoneSetAndVisibleToPartner(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	_, tokenA, _, tokenB, _ := pairedCoupleWithIDs(t, srv.URL)

	res := doJSON(t, http.MethodPost, srv.URL+"/api/heartbeat", tokenA, map[string]any{
		"kind":     "phone",
		"name":     "Pixel",
		"timezone": "UTC+02:00",
	})
	body := decodeJSON(t, res)
	if res.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 setting timezone, got %d: %v", res.StatusCode, body)
	}
	deviceID, _ := body["device_id"].(string)
	if deviceID == "" {
		t.Fatalf("heartbeat response missing device_id: %v", body)
	}

	device := getDevice(t, srv.URL, tokenA, deviceID)
	if got, _ := device["timezone"].(string); got != "UTC+02:00" {
		t.Fatalf("expected timezone UTC+02:00, got %v", device["timezone"])
	}

	// Partner (B) can see A's timezone via the couple-scoped devices list.
	partnerDevice := getDevice(t, srv.URL, tokenB, deviceID)
	if got, _ := partnerDevice["timezone"].(string); got != "UTC+02:00" {
		t.Fatalf("expected partner to see timezone UTC+02:00, got %v", partnerDevice["timezone"])
	}

	// An outsider cannot.
	tokenC, _, _ := pairedCouple(t, srv.URL)
	viewRes := doJSON(t, http.MethodGet, srv.URL+"/api/collections/devices/records/"+deviceID, tokenC, nil)
	defer viewRes.Body.Close()
	if viewRes.StatusCode == http.StatusOK {
		t.Fatal("expected outsider to be denied viewing A's device timezone")
	}

	// A key-less heartbeat leaves it untouched (only-present-keys contract).
	res2 := doJSON(t, http.MethodPost, srv.URL+"/api/heartbeat", tokenA, map[string]any{
		"kind": "phone",
		"name": "Pixel",
	})
	if res2.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 on key-less heartbeat, got %d", res2.StatusCode)
	}
	device2 := getDevice(t, srv.URL, tokenA, deviceID)
	if got, _ := device2["timezone"].(string); got != "UTC+02:00" {
		t.Fatalf("expected timezone to remain UTC+02:00 after key-less heartbeat, got %v", device2["timezone"])
	}

	// Explicit null clears it.
	res3 := doJSON(t, http.MethodPost, srv.URL+"/api/heartbeat", tokenA, map[string]any{
		"kind":     "phone",
		"name":     "Pixel",
		"timezone": nil,
	})
	if res3.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 clearing timezone, got %d", res3.StatusCode)
	}
	device3 := getDevice(t, srv.URL, tokenA, deviceID)
	if got, _ := device3["timezone"].(string); got != "" {
		t.Fatalf("expected timezone cleared to empty, got %v", device3["timezone"])
	}
}

func TestHeartbeatTimezoneValidation(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	_, token := registerAndLogin(t, srv.URL, uniqueEmail(t), "password1234")

	cases := []struct {
		name     string
		timezone any
	}{
		{"empty string", ""},
		{"too long", string(make([]byte, 65))},
		{"exotic characters", "Europe/Warsaw; DROP TABLE devices"},
		{"not a string", 42.0},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			res := doJSON(t, http.MethodPost, srv.URL+"/api/heartbeat", token, map[string]any{
				"kind":     "phone",
				"name":     "Pixel",
				"timezone": c.timezone,
			})
			defer res.Body.Close()
			if res.StatusCode != http.StatusBadRequest {
				t.Fatalf("expected 400 for timezone %v, got %d", c.timezone, res.StatusCode)
			}
		})
	}

	// A legit IANA-shaped name is also accepted (not just UTC-offset strings).
	res := doJSON(t, http.MethodPost, srv.URL+"/api/heartbeat", token, map[string]any{
		"kind":     "phone",
		"name":     "Pixel",
		"timezone": "Europe/Warsaw",
	})
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 for a well-formed IANA name, got %d", res.StatusCode)
	}
}

// --- touches -----------------------------------------------------------

func postTouch(t *testing.T, baseURL, token, coupleID, userID string, x, y float64) *http.Response {
	t.Helper()
	return doJSON(t, http.MethodPost, baseURL+"/api/collections/touches/records", token, map[string]any{
		"couple": coupleID,
		"user":   userID,
		"x":      x,
		"y":      y,
	})
}

func TestTouchesCreateAndVisibility(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	idA, tokenA, _, tokenB, coupleID := pairedCoupleWithIDs(t, srv.URL)

	res := postTouch(t, srv.URL, tokenA, coupleID, idA, 0.42, 0.58)
	body := decodeJSON(t, res)
	if res.StatusCode != http.StatusOK {
		t.Fatalf("A create touch: %d: %v", res.StatusCode, body)
	}

	// Partner sees it in realtime-subscribable listing.
	listRes := doJSON(t, http.MethodGet, srv.URL+"/api/collections/touches/records", tokenB, nil)
	listBody := decodeJSON(t, listRes)
	if got := listBody["totalItems"].(float64); got != 1 {
		t.Fatalf("B sees %v touches, want 1", got)
	}
	item := listBody["items"].([]any)[0].(map[string]any)
	if got, _ := item["x"].(float64); got != 0.42 {
		t.Fatalf("expected x 0.42, got %v", item["x"])
	}
}

func TestTouchesForgeryBlocked(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	idA, tokenA, _, tokenB, coupleID := pairedCoupleWithIDs(t, srv.URL)

	// B cannot post a touch pretending to be A.
	res := postTouch(t, srv.URL, tokenB, coupleID, idA, 0.1, 0.1)
	if res.StatusCode == http.StatusOK {
		t.Fatal("B forged a touch authored as A")
	}
	_ = tokenA
}

func TestTouchesIsolation(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	idA, tokenA, _, _, coupleID := pairedCoupleWithIDs(t, srv.URL)
	if res := postTouch(t, srv.URL, tokenA, coupleID, idA, 0.3, 0.3); res.StatusCode != http.StatusOK {
		t.Fatalf("A create touch: %d", res.StatusCode)
	}

	tokenC, _, _ := pairedCouple(t, srv.URL)

	// Outsider sees nothing.
	res := doJSON(t, http.MethodGet, srv.URL+"/api/collections/touches/records", tokenC, nil)
	if got := decodeJSON(t, res)["totalItems"].(float64); got != 0 {
		t.Fatalf("outsider sees %v touches", got)
	}
	// Outsider cannot post into A+B's couple.
	if res := postTouch(t, srv.URL, tokenC, coupleID, idA, 0.2, 0.2); res.StatusCode == http.StatusOK {
		t.Fatal("outsider posted a touch into another couple")
	}
}

func TestTouchesNoUpdateNoClientDelete(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	idA, tokenA, _, _, coupleID := pairedCoupleWithIDs(t, srv.URL)
	createRes := decodeJSON(t, postTouch(t, srv.URL, tokenA, coupleID, idA, 0.5, 0.5))
	touchID, _ := createRes["id"].(string)
	if touchID == "" {
		t.Fatalf("touch create response missing id: %v", createRes)
	}

	updateRes := doJSON(t, http.MethodPatch, srv.URL+"/api/collections/touches/records/"+touchID, tokenA, map[string]any{"x": 0.9})
	defer updateRes.Body.Close()
	if updateRes.StatusCode == http.StatusOK {
		t.Fatal("client updated a touch record; expected update to be blocked")
	}

	deleteRes := doJSON(t, http.MethodDelete, srv.URL+"/api/collections/touches/records/"+touchID, tokenA, nil)
	defer deleteRes.Body.Close()
	if deleteRes.StatusCode == http.StatusNoContent {
		t.Fatal("client deleted a touch record; expected delete to be blocked (purge-only)")
	}
}

func TestTouchesOutOfRangeRejected(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	idA, tokenA, _, _, coupleID := pairedCoupleWithIDs(t, srv.URL)

	res := postTouch(t, srv.URL, tokenA, coupleID, idA, 1.5, 0.5)
	defer res.Body.Close()
	if res.StatusCode == http.StatusOK {
		t.Fatal("expected an out-of-range x to be rejected")
	}
}

func TestTouchesPurge(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)
	idA, tokenA, _, _, coupleID := pairedCoupleWithIDs(t, srv.URL)

	// One fresh touch via the route…
	if res := postTouch(t, srv.URL, tokenA, coupleID, idA, 0.4, 0.4); res.StatusCode != http.StatusOK {
		t.Fatalf("create touch: %d", res.StatusCode)
	}
	// …and one ancient touch planted directly.
	touches, err := app.FindCollectionByNameOrId("touches")
	if err != nil {
		t.Fatal(err)
	}
	ancient, _ := types.ParseDateTime(time.Now().Add(-2 * time.Hour).UTC())
	stale := core.NewRecord(touches)
	stale.Set("couple", coupleID)
	stale.Set("user", idA)
	stale.Set("x", 0.1)
	stale.Set("y", 0.1)
	if err := app.Save(stale); err != nil {
		t.Fatal(err)
	}
	// created is an autodate set on creation; back-date it directly in the DB
	// so the purge query (created < cutoff) actually has something to catch.
	if _, err := app.DB().NewQuery("UPDATE touches SET created = {:created} WHERE id = {:id}").
		Bind(map[string]any{"created": ancient.String(), "id": stale.Id}).Execute(); err != nil {
		t.Fatal(err)
	}

	if err := purgeOldTouches(app); err != nil {
		t.Fatal(err)
	}

	remaining, err := app.FindRecordsByFilter("touches", "couple = {:c}", "", 0, 0, dbx.Params{"c": coupleID})
	if err != nil {
		t.Fatal(err)
	}
	if len(remaining) != 1 {
		t.Fatalf("after purge: %d touches, want 1 (fresh only)", len(remaining))
	}
}
