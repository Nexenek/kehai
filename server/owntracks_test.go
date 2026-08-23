package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/types"
)

func postOwntracks(t *testing.T, baseURL, email, secret string, payload map[string]any) *http.Response {
	t.Helper()
	raw, _ := json.Marshal(payload)
	req, err := http.NewRequest(http.MethodPost, baseURL+"/api/owntracks", bytes.NewReader(raw))
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.SetBasicAuth(email, secret)
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	return res
}

func locationPayload(lat, lon float64) map[string]any {
	return map[string]any{
		"_type": "location", "lat": lat, "lon": lon,
		"acc": 12.0, "batt": 77.0, "vel": 3.0,
		"tst": time.Now().Unix(),
	}
}

func TestOwntracksIngest(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	idA, tokenA, _, tokenB, _ := pairedCoupleWithIDs(t, srv.URL)
	userA, err := app.FindRecordById("users", idA)
	if err != nil {
		t.Fatal(err)
	}
	emailA := userA.Email()

	// Password auth path.
	res := postOwntracks(t, srv.URL, emailA, "password1234", locationPayload(52.23, 21.01))
	if res.StatusCode != http.StatusOK {
		t.Fatalf("password-auth ingest: %d", res.StatusCode)
	}
	// Token-in-password-slot auth path.
	res = postOwntracks(t, srv.URL, emailA, tokenA, locationPayload(52.24, 21.02))
	if res.StatusCode != http.StatusOK {
		t.Fatalf("token-auth ingest: %d", res.StatusCode)
	}

	// Partner sees the points; count = 2.
	res = doJSON(t, http.MethodGet, srv.URL+"/api/collections/locations/records", tokenB, nil)
	if got := decodeJSON(t, res)["totalItems"].(float64); got != 2 {
		t.Fatalf("partner sees %v locations, want 2", got)
	}

	// Bad credentials → 401.
	res = postOwntracks(t, srv.URL, emailA, "wrong-password", locationPayload(1, 1))
	if res.StatusCode != http.StatusUnauthorized {
		t.Fatalf("bad creds: %d, want 401", res.StatusCode)
	}

	// Out-of-range coords → 400.
	res = postOwntracks(t, srv.URL, emailA, tokenA, locationPayload(123, 21))
	if res.StatusCode != http.StatusBadRequest {
		t.Fatalf("bad coords: %d, want 400", res.StatusCode)
	}

	// Non-location payloads are acknowledged and ignored.
	res = postOwntracks(t, srv.URL, emailA, tokenA, map[string]any{"_type": "waypoint"})
	if res.StatusCode != http.StatusOK {
		t.Fatalf("waypoint ack: %d", res.StatusCode)
	}

	// Ghost mode: points are dropped while ghost_until is in the future.
	future, _ := types.ParseDateTime(time.Now().Add(1 * time.Hour).UTC())
	userA.Set("ghost_until", future)
	if err := app.Save(userA); err != nil {
		t.Fatal(err)
	}
	res = postOwntracks(t, srv.URL, emailA, tokenA, locationPayload(52.25, 21.03))
	if res.StatusCode != http.StatusOK {
		t.Fatalf("ghost ingest ack: %d", res.StatusCode)
	}
	res = doJSON(t, http.MethodGet, srv.URL+"/api/collections/locations/records", tokenB, nil)
	if got := decodeJSON(t, res)["totalItems"].(float64); got != 2 {
		t.Fatalf("ghosted point stored! partner sees %v, want still 2", got)
	}

	// Outsider couple sees nothing; unauthenticated list rejected.
	tokenC, _, _ := pairedCouple(t, srv.URL)
	res = doJSON(t, http.MethodGet, srv.URL+"/api/collections/locations/records", tokenC, nil)
	if got := decodeJSON(t, res)["totalItems"].(float64); got != 0 {
		t.Fatalf("outsider sees %v locations", got)
	}
	// Clients cannot create/update/delete locations directly.
	res = doJSON(t, http.MethodPost, srv.URL+"/api/collections/locations/records", tokenA, map[string]any{
		"user": idA, "lat": 1, "lon": 1, "recorded": "2026-01-01 00:00:00.000Z",
	})
	if res.StatusCode == http.StatusOK {
		t.Fatal("client created a location directly")
	}
}

func TestLocationsPurge(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)
	idA, tokenA, _, _, _ := pairedCoupleWithIDs(t, srv.URL)
	userA, err := app.FindRecordById("users", idA)
	if err != nil {
		t.Fatal(err)
	}
	emailA := userA.Email()

	// One fresh point via the route…
	res := postOwntracks(t, srv.URL, emailA, tokenA, locationPayload(52.23, 21.01))
	if res.StatusCode != http.StatusOK {
		t.Fatalf("ingest: %d", res.StatusCode)
	}
	// …and one ancient point planted directly.
	locations, err := app.FindCollectionByNameOrId("locations")
	if err != nil {
		t.Fatal(err)
	}
	ancient, _ := types.ParseDateTime(time.Now().Add(-40 * 24 * time.Hour).UTC())
	stale := core.NewRecord(locations)
	stale.Set("user", idA)
	stale.Set("lat", 50.0)
	stale.Set("lon", 20.0)
	stale.Set("recorded", ancient)
	if err := app.Save(stale); err != nil {
		t.Fatal(err)
	}

	if err := purgeOldLocations(app); err != nil {
		t.Fatal(err)
	}

	remaining, err := app.FindRecordsByFilter("locations", "user = {:u}", "", 0, 0, dbx.Params{"u": idA})
	if err != nil {
		t.Fatal(err)
	}
	if len(remaining) != 1 {
		t.Fatalf("after purge: %d points, want 1 (fresh only)", len(remaining))
	}
}
