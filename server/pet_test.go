package main

import (
	"net/http"
	"testing"
)

// TestPetRules covers the shared pet's ownership contract: one pet per
// couple, either partner may care for it, nobody outside the couple can see
// or touch it, and there is no way to delete it (kb/features.md: the pet
// gets sleepy, never dies — and never gets deleted out from under you).
func TestPetRules(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	idA, tokenA, idB, tokenB, coupleID := pairedCoupleWithIDs(t, srv.URL)

	// A adopts the pet.
	res := doJSON(t, http.MethodPost, srv.URL+"/api/collections/pets/records", tokenA, map[string]any{
		"couple": coupleID, "name": "kehai-chan", "variant": "blob", "outfit": "none",
		"fed_at": "2026-08-23 08:00:00.000Z", "pet_at": "2026-08-23 08:00:00.000Z",
	})
	if res.StatusCode != http.StatusOK {
		t.Fatalf("A create pet: %d", res.StatusCode)
	}
	petID := decodeJSON(t, res)["id"].(string)

	// B sees the same pet — one row, shared.
	res = doJSON(t, http.MethodGet, srv.URL+"/api/collections/pets/records", tokenB, nil)
	if got := decodeJSON(t, res)["totalItems"].(float64); got != 1 {
		t.Fatalf("B sees %v pets, want 1", got)
	}

	// Either partner feeds/pets/dresses: B (not the creator) updates.
	res = doJSON(t, http.MethodPatch, srv.URL+"/api/collections/pets/records/"+petID, tokenB, map[string]any{
		"fed_at": "2026-08-23 19:30:00.000Z", "outfit": "bow", "variant": "cat", "name": "mochi",
	})
	if res.StatusCode != http.StatusOK {
		t.Fatalf("B update pet: %d", res.StatusCode)
	}
	updated := decodeJSON(t, res)
	if updated["outfit"] != "bow" || updated["name"] != "mochi" || updated["variant"] != "cat" {
		t.Fatalf("B's care did not stick: %v", updated)
	}

	// One pet per couple: a second adoption in the same couple is refused
	// by the unique index, so a get-or-create race can't fork the pet.
	res = doJSON(t, http.MethodPost, srv.URL+"/api/collections/pets/records", tokenB, map[string]any{
		"couple": coupleID, "name": "impostor", "variant": "star",
	})
	if res.StatusCode == http.StatusOK {
		t.Fatal("a couple got a second pet")
	}

	// Nobody deletes the pet — not even a partner (no delete rule at all).
	res = doJSON(t, http.MethodDelete, srv.URL+"/api/collections/pets/records/"+petID, tokenA, nil)
	if res.StatusCode == http.StatusOK || res.StatusCode == http.StatusNoContent {
		t.Fatalf("pet was deletable: %d", res.StatusCode)
	}

	// Care events: A logs a feed as themselves.
	res = doJSON(t, http.MethodPost, srv.URL+"/api/collections/pet_events/records", tokenA, map[string]any{
		"couple": coupleID, "user": idA, "type": "feed",
	})
	if res.StatusCode != http.StatusOK {
		t.Fatalf("A log feed event: %d", res.StatusCode)
	}
	eventID := decodeJSON(t, res)["id"].(string)

	// B can read A's event (shared history) …
	res = doJSON(t, http.MethodGet, srv.URL+"/api/collections/pet_events/records", tokenB, nil)
	if got := decodeJSON(t, res)["totalItems"].(float64); got != 1 {
		t.Fatalf("B sees %v pet events, want 1", got)
	}
	// … but cannot forge one authored as A.
	res = doJSON(t, http.MethodPost, srv.URL+"/api/collections/pet_events/records", tokenB, map[string]any{
		"couple": coupleID, "user": idA, "type": "pet",
	})
	if res.StatusCode == http.StatusOK {
		t.Fatal("B logged a pet event impersonating A")
	}
	// B logging as themselves is fine.
	res = doJSON(t, http.MethodPost, srv.URL+"/api/collections/pet_events/records", tokenB, map[string]any{
		"couple": coupleID, "user": idB, "type": "pet",
	})
	if res.StatusCode != http.StatusOK {
		t.Fatalf("B log pet event: %d", res.StatusCode)
	}

	// The log is append-only: no edits, no deletes.
	res = doJSON(t, http.MethodPatch, srv.URL+"/api/collections/pet_events/records/"+eventID, tokenA, map[string]any{
		"type": "rename",
	})
	if res.StatusCode == http.StatusOK {
		t.Fatal("pet event was editable")
	}
	res = doJSON(t, http.MethodDelete, srv.URL+"/api/collections/pet_events/records/"+eventID, tokenA, nil)
	if res.StatusCode == http.StatusOK || res.StatusCode == http.StatusNoContent {
		t.Fatalf("pet event was deletable: %d", res.StatusCode)
	}

	// Outsiders: their own couple's pet is a different pet; they see and
	// touch nothing of A+B's.
	tokenC, _, coupleC := pairedCouple(t, srv.URL)
	res = doJSON(t, http.MethodGet, srv.URL+"/api/collections/pets/records", tokenC, nil)
	if got := decodeJSON(t, res)["totalItems"].(float64); got != 0 {
		t.Fatalf("outsider sees %v pets", got)
	}
	res = doJSON(t, http.MethodPatch, srv.URL+"/api/collections/pets/records/"+petID, tokenC, map[string]any{
		"name": "stolen",
	})
	if res.StatusCode == http.StatusOK {
		t.Fatal("outsider renamed someone else's pet")
	}
	res = doJSON(t, http.MethodPost, srv.URL+"/api/collections/pets/records", tokenC, map[string]any{
		"couple": coupleID, "name": "sneaky",
	})
	if res.StatusCode == http.StatusOK {
		t.Fatal("outsider adopted a pet into someone else's couple")
	}
	res = doJSON(t, http.MethodPost, srv.URL+"/api/collections/pet_events/records", tokenC, map[string]any{
		"couple": coupleID, "user": idA, "type": "feed",
	})
	if res.StatusCode == http.StatusOK {
		t.Fatal("outsider logged an event into someone else's couple")
	}

	// The outsider couple can still adopt its own pet — the unique index is
	// per couple, not global.
	res = doJSON(t, http.MethodPost, srv.URL+"/api/collections/pets/records", tokenC, map[string]any{
		"couple": coupleC, "name": "kehai-chan", "variant": "star",
	})
	if res.StatusCode != http.StatusOK {
		t.Fatalf("outsider couple could not adopt its own pet: %d", res.StatusCode)
	}

	// Unpaired user can't adopt at all.
	_, tokenLoner := registerAndLogin(t, srv.URL, uniqueEmail(t), "password1234")
	res = doJSON(t, http.MethodPost, srv.URL+"/api/collections/pets/records", tokenLoner, map[string]any{
		"couple": coupleID, "name": "lonely",
	})
	if res.StatusCode == http.StatusOK {
		t.Fatal("unpaired user adopted a pet")
	}
}
