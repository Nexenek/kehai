package main

import (
	"bytes"
	"image"
	"image/color"
	"image/png"
	"mime/multipart"
	"net/http"
	"testing"
)

func tinyPNG(t *testing.T) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, 8, 8))
	img.Set(3, 3, color.RGBA{R: 255, A: 255})
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func postDoodle(t *testing.T, baseURL, token, coupleID, authorID string) *http.Response {
	t.Helper()
	var body bytes.Buffer
	w := multipart.NewWriter(&body)
	_ = w.WriteField("couple", coupleID)
	_ = w.WriteField("author", authorID)
	fw, err := w.CreateFormFile("image", "doodle.png")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := fw.Write(tinyPNG(t)); err != nil {
		t.Fatal(err)
	}
	_ = w.Close()

	req, err := http.NewRequest(http.MethodPost, baseURL+"/api/collections/doodles/records", &body)
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

func TestDoodleRules(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	idA, tokenA, _, tokenB, coupleID := pairedCoupleWithIDs(t, srv.URL)

	// A sends a doodle; B can see it.
	if res := postDoodle(t, srv.URL, tokenA, coupleID, idA); res.StatusCode != http.StatusOK {
		var buf bytes.Buffer
		_, _ = buf.ReadFrom(res.Body)
		t.Fatalf("A create doodle: %d — %s", res.StatusCode, buf.String())
	}
	res := doJSON(t, http.MethodGet, srv.URL+"/api/collections/doodles/records", tokenB, nil)
	if got := decodeJSON(t, res)["totalItems"].(float64); got != 1 {
		t.Fatalf("B sees %v doodles, want 1", got)
	}

	// B cannot forge a doodle authored as A.
	if res := postDoodle(t, srv.URL, tokenB, coupleID, idA); res.StatusCode == http.StatusOK {
		t.Fatal("B created a doodle impersonating A")
	}

	// Outsider couple sees nothing and cannot post into A+B's couple.
	tokenC, _, _ := pairedCouple(t, srv.URL)
	res = doJSON(t, http.MethodGet, srv.URL+"/api/collections/doodles/records", tokenC, nil)
	if got := decodeJSON(t, res)["totalItems"].(float64); got != 0 {
		t.Fatalf("outsider sees %v doodles", got)
	}
	if res := postDoodle(t, srv.URL, tokenC, coupleID, idA); res.StatusCode == http.StatusOK {
		t.Fatal("outsider posted a doodle into another couple")
	}
}
