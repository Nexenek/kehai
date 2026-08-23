package main

import (
	"bytes"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"testing"
)

// postSharedFile uploads [content] as [filename] into shared_files, exactly
// like a real multipart client — same shape as postDoodle/postInstant.
func postSharedFile(
	t *testing.T,
	baseURL, token, coupleID, uploadedBy, label string,
	content []byte,
	filename string,
) *http.Response {
	t.Helper()
	var body bytes.Buffer
	w := multipart.NewWriter(&body)
	_ = w.WriteField("couple", coupleID)
	_ = w.WriteField("uploaded_by", uploadedBy)
	if label != "" {
		_ = w.WriteField("label", label)
	}
	fw, err := w.CreateFormFile("file", filename)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := fw.Write(content); err != nil {
		t.Fatal(err)
	}
	_ = w.Close()

	req, err := http.NewRequest(http.MethodPost, baseURL+"/api/collections/shared_files/records", &body)
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

func TestSharedFileRules(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	idA, tokenA, idB, tokenB, coupleID := pairedCoupleWithIDs(t, srv.URL)

	// A uploads a file (arbitrary, non-image mime type — the field allows
	// ANY mime type); both partners can list it, and the label round-trips.
	res := postSharedFile(t, srv.URL, tokenA, coupleID, idA, "vacation photos.zip", []byte("hello shared file"), "archive.zip")
	if res.StatusCode != http.StatusOK {
		var buf bytes.Buffer
		_, _ = buf.ReadFrom(res.Body)
		t.Fatalf("A upload file: %d — %s", res.StatusCode, buf.String())
	}
	created := decodeJSON(t, res)
	fileID, _ := created["id"].(string)
	if fileID == "" {
		t.Fatalf("upload response missing id: %v", created)
	}
	if got, _ := created["label"].(string); got != "vacation photos.zip" {
		t.Fatalf("expected label 'vacation photos.zip', got %q", got)
	}

	listRes := doJSON(t, http.MethodGet, srv.URL+"/api/collections/shared_files/records", tokenB, nil)
	listBody := decodeJSON(t, listRes)
	if got := listBody["totalItems"].(float64); got != 1 {
		t.Fatalf("B sees %v files, want 1", got)
	}

	// Forgery blocked: B cannot upload a file stamped as uploaded_by A.
	if res := postSharedFile(t, srv.URL, tokenB, coupleID, idA, "sneaky", []byte("x"), "sneaky.txt"); res.StatusCode == http.StatusOK {
		t.Fatal("B forged a file as uploaded_by A")
	}

	// B uploads their own file...
	res = postSharedFile(t, srv.URL, tokenB, coupleID, idB, "", []byte("b's file"), "notes.txt")
	if res.StatusCode != http.StatusOK {
		t.Fatalf("B upload file: %d", res.StatusCode)
	}
	bCreated := decodeJSON(t, res)
	bFileID, _ := bCreated["id"].(string)
	// ...and label defaults sensibly when omitted app-side didn't happen
	// here (empty label sent) — the server just stores whatever it's given;
	// defaulting to the picked filename is the app's job (see
	// shared_file_repository.dart), not the schema's.
	if got, _ := bCreated["label"].(string); got != "" {
		t.Fatalf("expected empty label to round-trip empty, got %q", got)
	}

	// ...and either partner may delete any file in the couple (shared
	// ownership, same as doodles/instants — delete is couple-scoped, not
	// author-scoped).
	res = doJSON(t, http.MethodDelete, srv.URL+"/api/collections/shared_files/records/"+fileID, tokenB, nil)
	if res.StatusCode != http.StatusNoContent {
		t.Fatalf("B delete A's file: %d", res.StatusCode)
	}

	// No update rule at all — immutable v1, not even the uploader can edit;
	// re-upload instead.
	res = doJSON(t, http.MethodPatch, srv.URL+"/api/collections/shared_files/records/"+bFileID, tokenB, map[string]any{
		"label": "renamed",
	})
	if res.StatusCode == http.StatusOK {
		t.Fatal("expected the immutable collection to reject an update")
	}

	// Outsider isolation: a third couple sees none of A+B's files and
	// cannot upload into their couple by naming its id.
	tokenC, _, _ := pairedCouple(t, srv.URL)
	res = doJSON(t, http.MethodGet, srv.URL+"/api/collections/shared_files/records", tokenC, nil)
	if got := decodeJSON(t, res)["totalItems"].(float64); got != 0 {
		t.Fatalf("outsider sees %v files", got)
	}
	if res := postSharedFile(t, srv.URL, tokenC, coupleID, idA, "sneaky", []byte("x"), "sneaky.txt"); res.StatusCode == http.StatusOK {
		t.Fatal("outsider uploaded a file into another couple")
	}
}

// TestSharedFileProtectedAccess exercises PocketBase's real protected-file
// flow end to end: an unauthenticated (and a merely-authenticated-but-
// tokenless) fetch of the file URL must fail, a file token minted via
// POST /api/files/token for a couple member must succeed and return the
// exact uploaded bytes, and a file token minted for an unrelated outsider
// must still fail (the protected check re-validates the collection's
// ViewRule against the token's auth record, not just "any valid token").
func TestSharedFileProtectedAccess(t *testing.T) {
	app := newTestApp(t)
	srv := newTestServer(t, app)

	idA, tokenA, _, _, coupleID := pairedCoupleWithIDs(t, srv.URL)

	content := []byte("these bytes are private")
	res := postSharedFile(t, srv.URL, tokenA, coupleID, idA, "", content, "secret.txt")
	if res.StatusCode != http.StatusOK {
		var buf bytes.Buffer
		_, _ = buf.ReadFrom(res.Body)
		t.Fatalf("upload: %d — %s", res.StatusCode, buf.String())
	}
	created := decodeJSON(t, res)
	fileID, _ := created["id"].(string)
	collectionID, _ := created["collectionId"].(string)
	filename, _ := created["file"].(string)
	if fileID == "" || collectionID == "" || filename == "" {
		t.Fatalf("upload response missing id/collectionId/file: %v", created)
	}
	downloadURL := fmt.Sprintf("%s/api/files/%s/%s/%s", srv.URL, collectionID, fileID, filename)

	// Completely unauthenticated fetch (no Authorization header, no
	// ?token=) must fail — PocketBase 404s a protected file it can't
	// authorize rather than leaking existence via a 401/403.
	unauthRes, err := http.Get(downloadURL)
	if err != nil {
		t.Fatal(err)
	}
	defer unauthRes.Body.Close()
	if unauthRes.StatusCode == http.StatusOK {
		t.Fatal("expected a protected file to be unreachable without a file token")
	}

	// A valid *session* auth header alone isn't enough either — the
	// protected-file check is purely the ?token= query param (a distinct,
	// short-lived file token), not the regular Authorization header.
	authedNoTokenReq, err := http.NewRequest(http.MethodGet, downloadURL, nil)
	if err != nil {
		t.Fatal(err)
	}
	authedNoTokenReq.Header.Set("Authorization", tokenA)
	authedNoTokenRes, err := http.DefaultClient.Do(authedNoTokenReq)
	if err != nil {
		t.Fatal(err)
	}
	defer authedNoTokenRes.Body.Close()
	if authedNoTokenRes.StatusCode == http.StatusOK {
		t.Fatal("expected a protected file to be unreachable via Authorization header alone")
	}

	// Mint a real file token for A (POST /api/files/token, auth required)
	// and use it — this is the actual client flow
	// (shared_file_repository.dart's downloadUrl).
	tokenRes := doJSON(t, http.MethodPost, srv.URL+"/api/files/token", tokenA, nil)
	tokenBody := decodeJSON(t, tokenRes)
	if tokenRes.StatusCode != http.StatusOK {
		t.Fatalf("mint file token: %d — %v", tokenRes.StatusCode, tokenBody)
	}
	fileToken, _ := tokenBody["token"].(string)
	if fileToken == "" {
		t.Fatalf("file token response missing token: %v", tokenBody)
	}

	okRes, err := http.Get(downloadURL + "?token=" + fileToken)
	if err != nil {
		t.Fatal(err)
	}
	defer okRes.Body.Close()
	if okRes.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 downloading with a valid file token, got %d", okRes.StatusCode)
	}
	got, err := io.ReadAll(okRes.Body)
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != string(content) {
		t.Fatalf("downloaded bytes mismatch: got %q, want %q", got, content)
	}

	// An outsider's own (perfectly valid) file token still can't open A+B's
	// file — the couple-scoped ViewRule is re-checked against the token's
	// auth record.
	tokenC, _, _ := pairedCouple(t, srv.URL)
	cTokenBody := decodeJSON(t, doJSON(t, http.MethodPost, srv.URL+"/api/files/token", tokenC, nil))
	cFileToken, _ := cTokenBody["token"].(string)
	if cFileToken == "" {
		t.Fatalf("outsider file token response missing token: %v", cTokenBody)
	}
	outsiderRes, err := http.Get(downloadURL + "?token=" + cFileToken)
	if err != nil {
		t.Fatal(err)
	}
	defer outsiderRes.Body.Close()
	if outsiderRes.StatusCode == http.StatusOK {
		t.Fatal("outsider's own file token accessed another couple's protected file")
	}
}
