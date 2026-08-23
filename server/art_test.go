package main

import (
	"bytes"
	"encoding/json"
	"image"
	"image/color"
	"image/jpeg"
	"mime/multipart"
	"net/http"
	"strconv"
	"testing"
)

// tinyJPEG is a deliberately *wrong* upload for the art system: a real
// image, but opaque JPEG rather than the transparent PNG a paper-doll layer
// has to be. The collection's MimeTypes must reject it.
func tinyJPEG(t *testing.T) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, 8, 8))
	img.Set(3, 3, color.RGBA{B: 255, A: 255})
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, img, nil); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

// postArtLayer uploads one art layer via multipart (a file field can't ride
// a JSON body) — same shape as postDoodle/postBoardPhoto.
func postArtLayer(t *testing.T, baseURL, token, coupleID, slot, name string, sort float64, conditions map[string]any, imageBytes []byte, filename string) *http.Response {
	t.Helper()
	var body bytes.Buffer
	w := multipart.NewWriter(&body)
	_ = w.WriteField("couple", coupleID)
	_ = w.WriteField("slot", slot)
	_ = w.WriteField("name", name)
	_ = w.WriteField("sort", strconv.FormatFloat(sort, 'f', -1, 64))
	if conditions != nil {
		encoded, err := json.Marshal(conditions)
		if err != nil {
			t.Fatal(err)
		}
		_ = w.WriteField("conditions", string(encoded))
	}
	fw, err := w.CreateFormFile("image", filename)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := fw.Write(imageBytes); err != nil {
		t.Fatal(err)
	}
	_ = w.Close()

	req, err := http.NewRequest(http.MethodPost, baseURL+"/api/collections/art_layers/records", &body)
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

func postPNGLayer(t *testing.T, baseURL, token, coupleID, slot, name string, sort float64, conditions map[string]any) *http.Response {
	t.Helper()
	return postArtLayer(t, baseURL, token, coupleID, slot, name, sort, conditions, tinyPNG(t), "layer.png")
}

func TestArtLayerRules(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	tokenA, tokenB, coupleID := pairedCouple(t, srv.URL)

	// A (the artist) uploads one layer per slot — the full paper-doll
	// stack from ADR-13.
	slots := []string{"background", "base", "outfit", "expression", "prop"}
	ids := map[string]string{}
	for i, slot := range slots {
		res := postPNGLayer(t, srv.URL, tokenA, coupleID, slot, slot+" one", float64(i), map[string]any{
			"default": true,
		})
		if res.StatusCode != http.StatusOK {
			var buf bytes.Buffer
			_, _ = buf.ReadFrom(res.Body)
			t.Fatalf("A create %s layer: %d — %s", slot, res.StatusCode, buf.String())
		}
		ids[slot] = decodeJSON(t, res)["id"].(string)
	}

	// A conditioned layer: the mood/ambient JSON round-trips intact.
	res := postPNGLayer(t, srv.URL, tokenA, coupleID, "expression", "sleepy face", 1, map[string]any{
		"moods":   []string{"sleepy", "cozy"},
		"ambient": []string{"away"},
	})
	if res.StatusCode != http.StatusOK {
		t.Fatalf("A create conditioned layer: %d", res.StatusCode)
	}
	conditioned := decodeJSON(t, res)
	conditionedID := conditioned["id"].(string)
	conds, ok := conditioned["conditions"].(map[string]any)
	if !ok {
		t.Fatalf("conditions came back as %T, want an object", conditioned["conditions"])
	}
	moods, ok := conds["moods"].([]any)
	if !ok || len(moods) != 2 || moods[0].(string) != "sleepy" {
		t.Fatalf("conditions.moods round-tripped as %v", conds["moods"])
	}

	// An invalid slot is refused — the select field is the whole contract
	// between the artist and the compositor's paint order.
	if res := postPNGLayer(t, srv.URL, tokenA, coupleID, "hat", "nope", 0, nil); res.StatusCode == http.StatusOK {
		t.Fatal("server accepted a layer in an unknown slot")
	}

	// Non-PNG is refused: an opaque JPEG would paint over every layer under
	// it, so the collection only accepts transparent-capable PNGs.
	if res := postArtLayer(t, srv.URL, tokenA, coupleID, "outfit", "jpeg outfit", 0, nil, tinyJPEG(t), "layer.jpg"); res.StatusCode == http.StatusOK {
		t.Fatal("server accepted a JPEG art layer")
	}
	// Even with a .png filename — mime sniffing, not the extension, decides.
	if res := postArtLayer(t, srv.URL, tokenA, coupleID, "outfit", "liar", 0, nil, tinyJPEG(t), "layer.png"); res.StatusCode == http.StatusOK {
		t.Fatal("server accepted a JPEG disguised with a .png filename")
	}

	// B sees everything A drew (shared, couple-scoped).
	res = doJSON(t, http.MethodGet, srv.URL+"/api/collections/art_layers/records", tokenB, nil)
	if got := decodeJSON(t, res)["totalItems"].(float64); got != 6 {
		t.Fatalf("B sees %v art layers, want 6", got)
	}

	// B (who did NOT draw it) can rename, re-condition and re-sort a layer:
	// the art belongs to the couple, not to its uploader.
	res = doJSON(t, http.MethodPatch, srv.URL+"/api/collections/art_layers/records/"+conditionedID, tokenB, map[string]any{
		"name":       "very sleepy face",
		"sort":       7,
		"conditions": map[string]any{"moods": []string{"sleepy"}, "default": false},
	})
	if res.StatusCode != http.StatusOK {
		t.Fatalf("B update art layer: %d", res.StatusCode)
	}
	updated := decodeJSON(t, res)
	if updated["name"].(string) != "very sleepy face" {
		t.Fatalf("B's rename didn't stick: %v", updated["name"])
	}
	if updated["sort"].(float64) != 7 {
		t.Fatalf("B's re-sort didn't stick: %v", updated["sort"])
	}

	// ...and B can delete one too.
	res = doJSON(t, http.MethodDelete, srv.URL+"/api/collections/art_layers/records/"+ids["prop"], tokenB, nil)
	if res.StatusCode != http.StatusNoContent {
		t.Fatalf("B delete art layer: %d", res.StatusCode)
	}
	res = doJSON(t, http.MethodGet, srv.URL+"/api/collections/art_layers/records", tokenA, nil)
	if got := decodeJSON(t, res)["totalItems"].(float64); got != 5 {
		t.Fatalf("A sees %v art layers after B's delete, want 5", got)
	}

	// Outsider isolation: another couple can neither see nor touch this art.
	tokenC, _, _ := pairedCoupleC(t, srv.URL)
	res = doJSON(t, http.MethodGet, srv.URL+"/api/collections/art_layers/records", tokenC, nil)
	if got := decodeJSON(t, res)["totalItems"].(float64); got != 0 {
		t.Fatalf("outsider sees %v art layers", got)
	}
	if res := postPNGLayer(t, srv.URL, tokenC, coupleID, "base", "sneaky", 0, nil); res.StatusCode == http.StatusOK {
		t.Fatal("outsider uploaded art into another couple")
	}
	res = doJSON(t, http.MethodPatch, srv.URL+"/api/collections/art_layers/records/"+ids["base"], tokenC, map[string]any{"name": "defaced"})
	if res.StatusCode == http.StatusOK {
		t.Fatal("outsider edited another couple's art")
	}
	res = doJSON(t, http.MethodDelete, srv.URL+"/api/collections/art_layers/records/"+ids["base"], tokenC, nil)
	if res.StatusCode == http.StatusOK {
		t.Fatal("outsider deleted another couple's art")
	}

	// An unpaired user has no couple to scope to, so they can't upload at all.
	_, tokenLoner := registerAndLogin(t, srv.URL, uniqueEmail(t), "password1234")
	if res := postPNGLayer(t, srv.URL, tokenLoner, coupleID, "base", "loner", 0, nil); res.StatusCode == http.StatusOK {
		t.Fatal("unpaired user uploaded an art layer")
	}
	res = doJSON(t, http.MethodGet, srv.URL+"/api/collections/art_layers/records", tokenLoner, nil)
	if got := decodeJSON(t, res)["totalItems"].(float64); got != 0 {
		t.Fatalf("unpaired user sees %v art layers", got)
	}

	// Anonymous sees nothing (a non-nil ListRule filters rather than 403s,
	// so the honest assertion is "zero rows") and cannot upload.
	res = doJSON(t, http.MethodGet, srv.URL+"/api/collections/art_layers/records", "", nil)
	if got := decodeJSON(t, res)["totalItems"].(float64); got != 0 {
		t.Fatalf("anonymous sees %v art layers", got)
	}
	if res := postPNGLayer(t, srv.URL, "", coupleID, "base", "anon", 0, nil); res.StatusCode == http.StatusOK {
		t.Fatal("anonymous uploaded an art layer")
	}
}
