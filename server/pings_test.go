package main

import (
	"net/http"
	"testing"
	"time"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/types"
)

// --- pings (one-tap "thinking of you") ------------------------------------

func postPing(t *testing.T, baseURL, token, coupleID, fromID, kind string) *http.Response {
	t.Helper()
	return doJSON(t, http.MethodPost, baseURL+"/api/collections/pings/records", token, map[string]any{
		"couple": coupleID,
		"from":   fromID,
		"kind":   kind,
	})
}

func TestPingCreateAndVisibility(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	idA, tokenA, _, tokenB, coupleID := pairedCoupleWithIDs(t, srv.URL)

	for _, kind := range []string{"thinking", "kiss", "hug"} {
		res := postPing(t, srv.URL, tokenA, coupleID, idA, kind)
		body := decodeJSON(t, res)
		if res.StatusCode != http.StatusOK {
			t.Fatalf("A create %q ping: %d: %v", kind, res.StatusCode, body)
		}
		if got, _ := body["kind"].(string); got != kind {
			t.Fatalf("expected kind %q back, got %v", kind, body["kind"])
		}
	}

	// The partner sees every one of them (this is the realtime-subscribable
	// listing the app's notifier hangs off).
	listRes := doJSON(t, http.MethodGet, srv.URL+"/api/collections/pings/records", tokenB, nil)
	listBody := decodeJSON(t, listRes)
	if got := listBody["totalItems"].(float64); got != 3 {
		t.Fatalf("B sees %v pings, want 3", got)
	}
}

func TestPingUnknownKindRejected(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	idA, tokenA, _, _, coupleID := pairedCoupleWithIDs(t, srv.URL)

	for _, kind := range []string{"", "smooch", "THINKING", "thinking hug"} {
		res := postPing(t, srv.URL, tokenA, coupleID, idA, kind)
		res.Body.Close()
		if res.StatusCode == http.StatusOK {
			t.Fatalf("expected kind %q to be rejected", kind)
		}
	}
}

func TestPingForgeryBlocked(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	idA, _, _, tokenB, coupleID := pairedCoupleWithIDs(t, srv.URL)

	// B cannot send a ping that claims to come from A — "thinking of you"
	// has to actually be from the person it names.
	res := postPing(t, srv.URL, tokenB, coupleID, idA, "kiss")
	res.Body.Close()
	if res.StatusCode == http.StatusOK {
		t.Fatal("B forged a ping authored as A")
	}
}

func TestPingIsolation(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	idA, tokenA, _, _, coupleID := pairedCoupleWithIDs(t, srv.URL)
	if res := postPing(t, srv.URL, tokenA, coupleID, idA, "hug"); res.StatusCode != http.StatusOK {
		t.Fatalf("A create ping: %d", res.StatusCode)
	}

	tokenC, _, _ := pairedCouple(t, srv.URL)

	res := doJSON(t, http.MethodGet, srv.URL+"/api/collections/pings/records", tokenC, nil)
	if got := decodeJSON(t, res)["totalItems"].(float64); got != 0 {
		t.Fatalf("outsider sees %v pings", got)
	}
	if res := postPing(t, srv.URL, tokenC, coupleID, idA, "hug"); res.StatusCode == http.StatusOK {
		t.Fatal("outsider posted a ping into another couple")
	}
}

func TestPingImmutable(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	idA, tokenA, _, tokenB, coupleID := pairedCoupleWithIDs(t, srv.URL)
	created := decodeJSON(t, postPing(t, srv.URL, tokenA, coupleID, idA, "thinking"))
	pingID, _ := created["id"].(string)
	if pingID == "" {
		t.Fatalf("ping create response missing id: %v", created)
	}

	// Neither the sender nor the receiver can rewrite or unsend it.
	for name, token := range map[string]string{"sender": tokenA, "receiver": tokenB} {
		updateRes := doJSON(t, http.MethodPatch, srv.URL+"/api/collections/pings/records/"+pingID, token, map[string]any{"kind": "hug"})
		updateRes.Body.Close()
		if updateRes.StatusCode == http.StatusOK {
			t.Fatalf("%s updated a ping; expected update to be blocked", name)
		}

		deleteRes := doJSON(t, http.MethodDelete, srv.URL+"/api/collections/pings/records/"+pingID, token, nil)
		deleteRes.Body.Close()
		if deleteRes.StatusCode == http.StatusNoContent {
			t.Fatalf("%s deleted a ping; expected delete to be blocked (purge-only)", name)
		}
	}
}

func TestPingsPurge(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)
	idA, tokenA, _, _, coupleID := pairedCoupleWithIDs(t, srv.URL)

	// One fresh ping through the API…
	if res := postPing(t, srv.URL, tokenA, coupleID, idA, "kiss"); res.StatusCode != http.StatusOK {
		t.Fatalf("create ping: %d", res.StatusCode)
	}

	pings, err := app.FindCollectionByNameOrId("pings")
	if err != nil {
		t.Fatal(err)
	}
	// …one just inside the window (6 days), which must survive…
	// …and one just outside it (8 days), which must not.
	plant := func(age time.Duration) string {
		rec := core.NewRecord(pings)
		rec.Set("couple", coupleID)
		rec.Set("from", idA)
		rec.Set("kind", "hug")
		if err := app.Save(rec); err != nil {
			t.Fatal(err)
		}
		when, _ := types.ParseDateTime(time.Now().Add(-age).UTC())
		if _, err := app.DB().NewQuery("UPDATE pings SET created = {:created} WHERE id = {:id}").
			Bind(map[string]any{"created": when.String(), "id": rec.Id}).Execute(); err != nil {
			t.Fatal(err)
		}
		return rec.Id
	}
	recentID := plant(6 * 24 * time.Hour)
	staleID := plant(8 * 24 * time.Hour)

	if err := purgeOldPings(app); err != nil {
		t.Fatal(err)
	}

	remaining, err := app.FindRecordsByFilter("pings", "couple = {:c}", "", 0, 0, dbx.Params{"c": coupleID})
	if err != nil {
		t.Fatal(err)
	}
	if len(remaining) != 2 {
		t.Fatalf("after purge: %d pings, want 2 (fresh + 6-day-old)", len(remaining))
	}
	ids := map[string]bool{}
	for _, r := range remaining {
		ids[r.Id] = true
	}
	if !ids[recentID] {
		t.Fatal("purge ate a 6-day-old ping; retention is 7 days")
	}
	if ids[staleID] {
		t.Fatal("purge left an 8-day-old ping behind")
	}
}
