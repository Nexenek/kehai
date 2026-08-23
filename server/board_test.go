package main

import (
	"bytes"
	"mime/multipart"
	"net/http"
	"strconv"
	"testing"
)

// postBoardPhoto creates a "photo" board_items record via multipart upload
// (image files can't ride a JSON body) — same shape as postDoodle/postInstant.
func postBoardPhoto(t *testing.T, baseURL, token, coupleID string, x, y, z float64) *http.Response {
	t.Helper()
	var body bytes.Buffer
	w := multipart.NewWriter(&body)
	_ = w.WriteField("couple", coupleID)
	_ = w.WriteField("type", "photo")
	_ = w.WriteField("x", strconv.FormatFloat(x, 'f', -1, 64))
	_ = w.WriteField("y", strconv.FormatFloat(y, 'f', -1, 64))
	_ = w.WriteField("z", strconv.FormatFloat(z, 'f', -1, 64))
	fw, err := w.CreateFormFile("image", "board.png")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := fw.Write(tinyPNG(t)); err != nil {
		t.Fatal(err)
	}
	_ = w.Close()

	req, err := http.NewRequest(http.MethodPost, baseURL+"/api/collections/board_items/records", &body)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Content-Type", w.FormDataContentType())
	req.Header.Set("Authorization", token)
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	return res
}

func TestBoardItemRules(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	tokenA, tokenB, coupleID := pairedCouple(t, srv.URL)

	// A creates one of each type.
	res := doJSON(t, http.MethodPost, srv.URL+"/api/collections/board_items/records", tokenA, map[string]any{
		"couple": coupleID, "type": "note", "text": "miss you", "x": 0.2, "y": 0.3, "rot": -5, "z": 1, "color": "mint",
	})
	if res.StatusCode != http.StatusOK {
		t.Fatalf("A create note item: %d", res.StatusCode)
	}
	noteID := decodeJSON(t, res)["id"].(string)

	res = doJSON(t, http.MethodPost, srv.URL+"/api/collections/board_items/records", tokenA, map[string]any{
		"couple": coupleID, "type": "sticker", "sticker": "♥︎", "x": 0.5, "y": 0.5, "rot": 10, "z": 2,
	})
	if res.StatusCode != http.StatusOK {
		t.Fatalf("A create sticker item: %d", res.StatusCode)
	}
	stickerID := decodeJSON(t, res)["id"].(string)

	res = postBoardPhoto(t, srv.URL, tokenA, coupleID, 0.1, 0.9, 3)
	if res.StatusCode != http.StatusOK {
		t.Fatalf("A create photo item: %d", res.StatusCode)
	}
	photoID := decodeJSON(t, res)["id"].(string)

	// B (not the author) can move any of them — shared ownership, not
	// author-locked, per the brief.
	res = doJSON(t, http.MethodPatch, srv.URL+"/api/collections/board_items/records/"+noteID, tokenB, map[string]any{
		"x": 0.6, "y": 0.7,
	})
	if res.StatusCode != http.StatusOK {
		t.Fatalf("B move note item: %d", res.StatusCode)
	}
	moved := decodeJSON(t, res)
	if got := moved["x"].(float64); got != 0.6 {
		t.Fatalf("expected x=0.6 after B's move, got %v", got)
	}

	// B can delete too.
	res = doJSON(t, http.MethodDelete, srv.URL+"/api/collections/board_items/records/"+stickerID, tokenB, nil)
	if res.StatusCode != http.StatusNoContent {
		t.Fatalf("B delete sticker item: %d", res.StatusCode)
	}

	// A still sees the note (moved) and the photo, not the deleted sticker.
	res = doJSON(t, http.MethodGet, srv.URL+"/api/collections/board_items/records", tokenA, nil)
	body := decodeJSON(t, res)
	if got := body["totalItems"].(float64); got != 2 {
		t.Fatalf("expected 2 remaining board items, got %v", got)
	}
	_ = photoID

	// Outsider isolation: a third, unrelated couple sees none of this and
	// cannot write into A+B's couple even by naming its id.
	tokenC, _, _ := pairedCoupleC(t, srv.URL)
	res = doJSON(t, http.MethodGet, srv.URL+"/api/collections/board_items/records", tokenC, nil)
	if got := decodeJSON(t, res)["totalItems"].(float64); got != 0 {
		t.Fatalf("outsider sees %v board items", got)
	}
	res = doJSON(t, http.MethodPost, srv.URL+"/api/collections/board_items/records", tokenC, map[string]any{
		"couple": coupleID, "type": "note", "text": "sneaky", "x": 0.1, "y": 0.1,
	})
	if res.StatusCode == http.StatusOK {
		t.Fatal("outsider created a board item in someone else's couple")
	}
	res = doJSON(t, http.MethodDelete, srv.URL+"/api/collections/board_items/records/"+noteID, tokenC, nil)
	if res.StatusCode == http.StatusOK {
		t.Fatal("outsider deleted a board item in someone else's couple")
	}

	// Unpaired user cannot create board items at all.
	_, tokenLoner := registerAndLogin(t, srv.URL, uniqueEmail(t), "password1234")
	res = doJSON(t, http.MethodPost, srv.URL+"/api/collections/board_items/records", tokenLoner, map[string]any{
		"couple": coupleID, "type": "note", "text": "hi", "x": 0.1, "y": 0.1,
	})
	if res.StatusCode == http.StatusOK {
		t.Fatal("unpaired user created a board item")
	}
}
