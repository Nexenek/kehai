package main

import (
	"net/http"
	"testing"
)

// TestEventsRules exercises CRUD on the shared `events` collection by both
// partners (shared ownership, not author-locked — same as countdowns/notes,
// see shared_content_test.go) plus outsider isolation.
func TestEventsRules(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	tokenA, tokenB, coupleID := pairedCouple(t, srv.URL)

	// A creates an event.
	res := doJSON(t, http.MethodPost, srv.URL+"/api/collections/calendar_events/records", tokenA, map[string]any{
		"couple":  coupleID,
		"title":   "dinner date",
		"starts":  "2026-09-01 19:00:00.000Z",
		"ends":    "2026-09-01 21:00:00.000Z",
		"all_day": false,
		"notes":   "wear the blue shirt",
		"color":   "pink",
	})
	if res.StatusCode != http.StatusOK {
		t.Fatalf("A create event: %d", res.StatusCode)
	}
	created := decodeJSON(t, res)
	eventID := created["id"].(string)
	if got := created["title"]; got != "dinner date" {
		t.Fatalf("expected title echoed back, got %v", got)
	}

	// B (not the author) can view, edit, and delete it — shared ownership.
	res = doJSON(t, http.MethodGet, srv.URL+"/api/collections/calendar_events/records/"+eventID, tokenB, nil)
	if res.StatusCode != http.StatusOK {
		t.Fatalf("B view event: %d", res.StatusCode)
	}

	res = doJSON(t, http.MethodPatch, srv.URL+"/api/collections/calendar_events/records/"+eventID, tokenB, map[string]any{
		"title": "dinner date!!",
		"color": "lavender",
	})
	if res.StatusCode != http.StatusOK {
		t.Fatalf("B edit event: %d", res.StatusCode)
	}
	if got := decodeJSON(t, res)["title"]; got != "dinner date!!" {
		t.Fatalf("expected edited title, got %v", got)
	}

	// A can list, filtered/sorted by starts (month-range query shape the app
	// repository will use).
	res = doJSON(t, http.MethodGet, srv.URL+"/api/collections/calendar_events/records?filter=couple%3D%27"+coupleID+"%27&sort=starts", tokenA, nil)
	if res.StatusCode != http.StatusOK {
		t.Fatalf("A list events: %d", res.StatusCode)
	}
	if got := decodeJSON(t, res)["totalItems"].(float64); got != 1 {
		t.Fatalf("expected 1 event, got %v", got)
	}

	// A deletes it (author or not — deletion isn't author-locked either).
	res = doJSON(t, http.MethodDelete, srv.URL+"/api/collections/calendar_events/records/"+eventID, tokenA, nil)
	if res.StatusCode != http.StatusNoContent {
		t.Fatalf("A delete event: %d", res.StatusCode)
	}

	// A required field missing (title) is rejected.
	res = doJSON(t, http.MethodPost, srv.URL+"/api/collections/calendar_events/records", tokenA, map[string]any{
		"couple": coupleID, "starts": "2026-09-02 09:00:00.000Z",
	})
	if res.StatusCode == http.StatusOK {
		t.Fatal("expected event without title to be rejected")
	}

	// --- outsider isolation -------------------------------------------

	res = doJSON(t, http.MethodPost, srv.URL+"/api/collections/calendar_events/records", tokenA, map[string]any{
		"couple": coupleID, "title": "anniversary trip", "starts": "2026-10-10 00:00:00.000Z", "all_day": true, "color": "mint",
	})
	if res.StatusCode != http.StatusOK {
		t.Fatalf("A create second event: %d", res.StatusCode)
	}
	secondID := decodeJSON(t, res)["id"].(string)

	tokenC, _, _ := pairedCouple(t, srv.URL)

	res = doJSON(t, http.MethodGet, srv.URL+"/api/collections/calendar_events/records", tokenC, nil)
	if got := decodeJSON(t, res)["totalItems"].(float64); got != 0 {
		t.Fatalf("outsider sees %v events", got)
	}
	res = doJSON(t, http.MethodGet, srv.URL+"/api/collections/calendar_events/records/"+secondID, tokenC, nil)
	if res.StatusCode == http.StatusOK {
		t.Fatal("outsider viewed someone else's event by id")
	}
	res = doJSON(t, http.MethodPost, srv.URL+"/api/collections/calendar_events/records", tokenC, map[string]any{
		"couple": coupleID, "title": "sneaky", "starts": "2026-10-10 00:00:00.000Z",
	})
	if res.StatusCode == http.StatusOK {
		t.Fatal("outsider created an event in someone else's couple")
	}
	res = doJSON(t, http.MethodPatch, srv.URL+"/api/collections/calendar_events/records/"+secondID, tokenC, map[string]any{
		"title": "hijacked",
	})
	if res.StatusCode == http.StatusOK {
		t.Fatal("outsider edited someone else's event")
	}
	res = doJSON(t, http.MethodDelete, srv.URL+"/api/collections/calendar_events/records/"+secondID, tokenC, nil)
	if res.StatusCode == http.StatusNoContent {
		t.Fatal("outsider deleted someone else's event")
	}

	// Unpaired user cannot create shared content at all.
	_, tokenLoner := registerAndLogin(t, srv.URL, uniqueEmail(t), "password1234")
	res = doJSON(t, http.MethodPost, srv.URL+"/api/collections/calendar_events/records", tokenLoner, map[string]any{
		"couple": coupleID, "title": "hi", "starts": "2026-10-10 00:00:00.000Z",
	})
	if res.StatusCode == http.StatusOK {
		t.Fatal("unpaired user created an event")
	}
}
