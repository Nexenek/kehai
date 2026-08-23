package main

import (
	"net/http"
	"time"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/types"
)

// owntracksPayload is the subset of the OwnTracks JSON we care about.
// https://owntracks.org/booklet/tech/json/
type owntracksPayload struct {
	Type     string  `json:"_type"`
	Lat      float64 `json:"lat"`
	Lon      float64 `json:"lon"`
	Acc      float64 `json:"acc"`
	Batt     float64 `json:"batt"`
	Vel      float64 `json:"vel"`
	Tst      int64   `json:"tst"`
}

// owntracksAuth resolves the posting user from HTTP Basic auth: the password
// slot accepts either a PocketBase auth token (preferred — no bcrypt cost per
// ping) or the account password (what the OwnTracks app UI naturally asks
// for). kb/contracts.md "Location".
func owntracksAuth(app core.App, r *http.Request) *core.Record {
	identity, secret, ok := r.BasicAuth()
	if !ok || secret == "" {
		return nil
	}
	if record, err := app.FindAuthRecordByToken(secret, core.TokenTypeAuth); err == nil {
		return record
	}
	record, err := app.FindAuthRecordByEmail("users", identity)
	if err != nil || !record.ValidatePassword(secret) {
		return nil
	}
	return record
}

func owntracksIngest(e *core.RequestEvent) error {
	user := owntracksAuth(e.App, e.Request)
	if user == nil {
		// 401 with the WWW-Authenticate header so the OwnTracks app surfaces
		// a credentials problem instead of silently retrying forever.
		e.Response.Header().Set("WWW-Authenticate", `Basic realm="kehai"`)
		return e.UnauthorizedError("Who's there? (・_・;)", nil)
	}

	var body owntracksPayload
	if err := e.BindBody(&body); err != nil {
		return e.BadRequestError("Invalid payload.", err)
	}

	// Anything that isn't a location fix (waypoints, transitions, status…)
	// is acknowledged and ignored.
	if body.Type != "location" {
		return e.JSON(http.StatusOK, []any{})
	}

	// Honest ghost mode: while paused, points are dropped, not stored. The
	// tracker keeps running and the partner can see sharing is paused via
	// the visible ghost_until field.
	if ghost := user.GetDateTime("ghost_until"); !ghost.IsZero() && ghost.Time().After(time.Now()) {
		return e.JSON(http.StatusOK, []any{})
	}

	if body.Lat < -90 || body.Lat > 90 || body.Lon < -180 || body.Lon > 180 {
		return e.BadRequestError("Coordinates out of range.", nil)
	}

	recorded := types.NowDateTime()
	if body.Tst > 0 {
		recorded, _ = types.ParseDateTime(time.Unix(body.Tst, 0).UTC())
	}

	locations, err := e.App.FindCollectionByNameOrId("locations")
	if err != nil {
		return e.InternalServerError("", err)
	}
	point := core.NewRecord(locations)
	point.Set("user", user.Id)
	point.Set("lat", body.Lat)
	point.Set("lon", body.Lon)
	point.Set("accuracy", body.Acc)
	point.Set("battery", body.Batt)
	point.Set("velocity", body.Vel)
	point.Set("recorded", recorded)
	if err := e.App.Save(point); err != nil {
		return e.InternalServerError("Could not store location.", err)
	}

	// OwnTracks expects an array of (optional) response messages.
	return e.JSON(http.StatusOK, []any{})
}

const locationRetention = 30 * 24 * time.Hour

// purgeOldLocations deletes stored points older than the retention window.
func purgeOldLocations(app core.App) error {
	cutoff, err := types.ParseDateTime(time.Now().Add(-locationRetention).UTC())
	if err != nil {
		return err
	}
	_, err = app.DB().NewQuery("DELETE FROM locations WHERE recorded < {:cutoff}").
		Bind(map[string]any{"cutoff": cutoff.String()}).Execute()
	return err
}
