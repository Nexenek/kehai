package main

import (
	"net/http"
	"testing"
)

// pairedCouple registers two users, pairs them, and returns their tokens
// plus the couple id.
func pairedCouple(t *testing.T, baseURL string) (tokenA, tokenB, coupleID string) {
	t.Helper()
	_, tokenA, _, tokenB, coupleID = pairedCoupleWithIDs(t, baseURL)
	return tokenA, tokenB, coupleID
}

// pairedCoupleWithIDs is pairedCouple, also exposing the user ids (needed by
// tests that must author records as a specific member — resolving ids from
// the users list instead is order-dependent and flaky).
func pairedCoupleWithIDs(t *testing.T, baseURL string) (idA, tokenA, idB, tokenB, coupleID string) {
	t.Helper()
	idA, tokenA = registerAndLogin(t, baseURL, uniqueEmail(t), "password1234")
	res := doJSON(t, http.MethodPost, baseURL+"/api/couple/create", tokenA, map[string]any{"name": "test"})
	if res.StatusCode != http.StatusOK {
		t.Fatalf("create couple: %d", res.StatusCode)
	}
	created := decodeJSON(t, res)
	coupleID = created["couple_id"].(string)

	idB, tokenB = registerAndLogin(t, baseURL, uniqueEmail(t), "password1234")
	res = doJSON(t, http.MethodPost, baseURL+"/api/couple/join", tokenB, map[string]any{"code": created["invite_code"]})
	if res.StatusCode != http.StatusOK {
		t.Fatalf("join couple: %d", res.StatusCode)
	}
	return idA, tokenA, idB, tokenB, coupleID
}

func TestSharedContentRules(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	tokenA, tokenB, coupleID := pairedCouple(t, srv.URL)

	// A creates a countdown and a note.
	res := doJSON(t, http.MethodPost, srv.URL+"/api/collections/countdowns/records", tokenA, map[string]any{
		"couple": coupleID, "title": "reunion!!", "date": "2026-12-24 12:00:00.000Z", "kaomoji": "(っ˘з˘)っ",
	})
	if res.StatusCode != http.StatusOK {
		t.Fatalf("A create countdown: %d", res.StatusCode)
	}
	countdownID := decodeJSON(t, res)["id"].(string)

	res = doJSON(t, http.MethodPost, srv.URL+"/api/collections/notes/records", tokenA, map[string]any{
		"couple": coupleID, "title": "groceries", "body": "pierogi", "color": "mint",
	})
	if res.StatusCode != http.StatusOK {
		t.Fatalf("A create note: %d", res.StatusCode)
	}
	noteID := decodeJSON(t, res)["id"].(string)

	// Shared ownership: B (not the author) can edit and delete both.
	res = doJSON(t, http.MethodPatch, srv.URL+"/api/collections/countdowns/records/"+countdownID, tokenB, map[string]any{
		"title": "REUNION!!!",
	})
	if res.StatusCode != http.StatusOK {
		t.Fatalf("B edit countdown: %d", res.StatusCode)
	}
	res = doJSON(t, http.MethodDelete, srv.URL+"/api/collections/notes/records/"+noteID, tokenB, nil)
	if res.StatusCode != http.StatusNoContent {
		t.Fatalf("B delete note: %d", res.StatusCode)
	}

	// B sets the anniversary on the shared couple record.
	res = doJSON(t, http.MethodPatch, srv.URL+"/api/collections/couples/records/"+coupleID, tokenB, map[string]any{
		"anniversary": "2024-02-14 00:00:00.000Z",
	})
	if res.StatusCode != http.StatusOK {
		t.Fatalf("B set anniversary: %d", res.StatusCode)
	}
	// invite_code stays hidden even on the update response.
	if _, leaked := decodeJSON(t, res)["invite_code"]; leaked {
		t.Fatal("invite_code leaked in couple update response")
	}

	// Outsiders: a third account in its own couple sees none of it and
	// cannot write into A+B's couple even by naming its id.
	tokenC, _, _ := pairedCoupleC(t, srv.URL)
	res = doJSON(t, http.MethodGet, srv.URL+"/api/collections/countdowns/records", tokenC, nil)
	if got := decodeJSON(t, res)["totalItems"].(float64); got != 0 {
		t.Fatalf("outsider sees %v countdowns", got)
	}
	res = doJSON(t, http.MethodPost, srv.URL+"/api/collections/countdowns/records", tokenC, map[string]any{
		"couple": coupleID, "title": "sneaky", "date": "2026-12-24 12:00:00.000Z",
	})
	if res.StatusCode == http.StatusOK {
		t.Fatal("outsider created a countdown in someone else's couple")
	}
	res = doJSON(t, http.MethodPatch, srv.URL+"/api/collections/couples/records/"+coupleID, tokenC, map[string]any{
		"anniversary": "2000-01-01 00:00:00.000Z",
	})
	if res.StatusCode == http.StatusOK {
		t.Fatal("outsider updated someone else's couple")
	}

	// Unpaired user cannot create shared content at all.
	_, tokenLoner := registerAndLogin(t, srv.URL, uniqueEmail(t), "password1234")
	res = doJSON(t, http.MethodPost, srv.URL+"/api/collections/notes/records", tokenLoner, map[string]any{
		"couple": coupleID, "title": "hi", "body": "hi",
	})
	if res.StatusCode == http.StatusOK {
		t.Fatal("unpaired user created a note")
	}
}

// pairedCoupleC builds a second, unrelated couple.
func pairedCoupleC(t *testing.T, baseURL string) (tokenC, tokenD, coupleID string) {
	t.Helper()
	return pairedCouple(t, baseURL)
}
