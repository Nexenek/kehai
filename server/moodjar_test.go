package main

import (
	"fmt"
	"net/http"
	"testing"
)

// listMoodEntries fetches the jar as a client would, returning the items.
func listMoodEntries(t *testing.T, baseURL, token string) []map[string]any {
	t.Helper()
	res := doJSON(t, http.MethodGet, baseURL+"/api/collections/mood_entries/records?sort=-created", token, nil)
	body := decodeJSON(t, res)
	if res.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 listing mood entries, got %d: %v", res.StatusCode, body)
	}
	items, _ := body["items"].([]any)
	out := make([]map[string]any, 0, len(items))
	for _, item := range items {
		if m, ok := item.(map[string]any); ok {
			out = append(out, m)
		}
	}
	return out
}

func setMood(t *testing.T, baseURL, token, userID, mood, note string) {
	t.Helper()
	// Same upsert dance the app does: create the status once, update after.
	res := doJSON(t, http.MethodGet,
		baseURL+"/api/collections/statuses/records?filter="+
			fmt.Sprintf("user%%3D%%27%s%%27", userID), token, nil)
	body := decodeJSON(t, res)
	items, _ := body["items"].([]any)
	payload := map[string]any{"user": userID, "mood": mood, "note": note}
	if len(items) == 0 {
		res = doJSON(t, http.MethodPost, baseURL+"/api/collections/statuses/records", token, payload)
	} else {
		id := items[0].(map[string]any)["id"].(string)
		res = doJSON(t, http.MethodPatch, baseURL+"/api/collections/statuses/records/"+id, token, payload)
	}
	rbody := decodeJSON(t, res)
	if res.StatusCode != http.StatusOK {
		t.Fatalf("failed to set mood %q: %d %v", mood, res.StatusCode, rbody)
	}
}

func TestMoodJarAppendsOnMoodChangeOnly(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	idA, tokenA, _, tokenB, _ := pairedCoupleWithIDs(t, srv.URL)

	setMood(t, srv.URL, tokenA, idA, "happy", "")
	setMood(t, srv.URL, tokenA, idA, "happy", "note edit only — no new bead")
	setMood(t, srv.URL, tokenA, idA, "sleepy", "zzz")

	entries := listMoodEntries(t, srv.URL, tokenB)
	if len(entries) != 2 {
		t.Fatalf("expected exactly 2 beads (happy, sleepy), got %d: %v", len(entries), entries)
	}
	if entries[0]["mood"] != "sleepy" || entries[1]["mood"] != "happy" {
		t.Fatalf("expected [sleepy, happy] newest-first, got %v", entries)
	}
	if entries[0]["note"] != "zzz" {
		t.Fatalf("expected the bead to carry the note, got %v", entries[0]["note"])
	}
}

func TestMoodJarUnpairedUserGetsNoBeads(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	// A loner sets moods before joining a couple — nothing to scope the
	// bead to, so nothing is written (and nothing crashes).
	idA, tokenA := registerAndLogin(t, srv.URL, uniqueEmail(t), "password1234")
	setMood(t, srv.URL, tokenA, idA, "happy", "")

	res := doJSON(t, http.MethodPost, srv.URL+"/api/couple/create", tokenA, map[string]any{"name": "us"})
	res.Body.Close()
	setMood(t, srv.URL, tokenA, idA, "cozy", "")

	entries := listMoodEntries(t, srv.URL, tokenA)
	if len(entries) != 1 || entries[0]["mood"] != "cozy" {
		t.Fatalf("expected only the post-pairing bead, got %v", entries)
	}
}

func TestMoodJarClientsCannotWrite(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	idA, tokenA, _, _, coupleID := pairedCoupleWithIDs(t, srv.URL)

	res := doJSON(t, http.MethodPost, srv.URL+"/api/collections/mood_entries/records", tokenA, map[string]any{
		"couple": coupleID, "user": idA, "mood": "forged",
	})
	if res.StatusCode == http.StatusOK {
		t.Fatalf("expected client mood_entries create to be forbidden, got 200")
	}
	res.Body.Close()
}

func TestMoodJarOutsiderSeesNothing(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	idA, tokenA, _, _, _ := pairedCoupleWithIDs(t, srv.URL)
	setMood(t, srv.URL, tokenA, idA, "happy", "private-ish")

	_, outsiderToken := registerAndLogin(t, srv.URL, uniqueEmail(t), "password1234")
	res := doJSON(t, http.MethodPost, srv.URL+"/api/couple/create", outsiderToken, map[string]any{"name": "them"})
	res.Body.Close()

	entries := listMoodEntries(t, srv.URL, outsiderToken)
	if len(entries) != 0 {
		t.Fatalf("outsider must see an empty jar, got %v", entries)
	}
}
