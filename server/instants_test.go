package main

import (
	"bytes"
	"mime/multipart"
	"net/http"
	"testing"
)

func postInstant(t *testing.T, baseURL, token, coupleID, authorID, caption string) *http.Response {
	t.Helper()
	var body bytes.Buffer
	w := multipart.NewWriter(&body)
	_ = w.WriteField("couple", coupleID)
	_ = w.WriteField("author", authorID)
	_ = w.WriteField("caption", caption)
	fw, err := w.CreateFormFile("image", "instant.png")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := fw.Write(tinyPNG(t)); err != nil {
		t.Fatal(err)
	}
	_ = w.Close()

	req, err := http.NewRequest(http.MethodPost, baseURL+"/api/collections/instants/records", &body)
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

func TestInstantRules(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	idA, tokenA, idB, tokenB, coupleID := pairedCoupleWithIDs(t, srv.URL)

	if res := postInstant(t, srv.URL, tokenA, coupleID, idA, "dzień dobry ☀"); res.StatusCode != http.StatusOK {
		t.Fatalf("A create instant: %d", res.StatusCode)
	}
	// Author forgery blocked.
	if res := postInstant(t, srv.URL, tokenB, coupleID, idA, "sneaky"); res.StatusCode == http.StatusOK {
		t.Fatal("B forged an instant authored as A")
	}
	// Partner sees the feed and may delete (shared ownership of memories).
	res := doJSON(t, http.MethodGet, srv.URL+"/api/collections/instants/records", tokenB, nil)
	body := decodeJSON(t, res)
	if got := body["totalItems"].(float64); got != 1 {
		t.Fatalf("B sees %v instants, want 1", got)
	}
	instantID := body["items"].([]any)[0].(map[string]any)["id"].(string)
	res = doJSON(t, http.MethodDelete, srv.URL+"/api/collections/instants/records/"+instantID, tokenB, nil)
	if res.StatusCode != http.StatusNoContent {
		t.Fatalf("B delete instant: %d", res.StatusCode)
	}

	// Outsider isolation.
	if res := postInstant(t, srv.URL, tokenB, coupleID, idB, "keeper"); res.StatusCode != http.StatusOK {
		t.Fatalf("B create instant: %d", res.StatusCode)
	}
	tokenC, _, _ := pairedCouple(t, srv.URL)
	res = doJSON(t, http.MethodGet, srv.URL+"/api/collections/instants/records", tokenC, nil)
	if got := decodeJSON(t, res)["totalItems"].(float64); got != 0 {
		t.Fatalf("outsider sees %v instants", got)
	}
}
