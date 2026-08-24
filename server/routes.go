package main

import (
	"crypto/rand"
	"math/big"
	"net/http"
	"regexp"
	"time"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/types"
)

// timezonePattern accepts both IANA zone names ("Europe/Warsaw") and the
// UTC-offset strings the current Flutter client actually sends
// ("UTC+02:00") — see the client-side note in heartbeat_service.dart for
// why we don't require a real IANA name yet.
var timezonePattern = regexp.MustCompile(`^[A-Za-z0-9_+:/-]+$`)

// unambiguous alphabet: no 0/O, 1/I/L — the code gets read out loud between partners
const inviteAlphabet = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"

func newInviteCode() (string, error) {
	code := make([]byte, 6)
	for i := range code {
		n, err := rand.Int(rand.Reader, big.NewInt(int64(len(inviteAlphabet))))
		if err != nil {
			return "", err
		}
		code[i] = inviteAlphabet[n.Int64()]
	}
	return string(code), nil
}

// bindRoutes registers our custom endpoints on top of PocketBase's own API.
//
// It takes the core.App interface (rather than the concrete *pocketbase.PocketBase)
// so it can be exercised against a tests.TestApp in routes_test.go without booting
// a real PocketBase instance.
func bindRoutes(app core.App) {
	// Outbound webhooks (server/webhooks.go) — registered directly on the
	// app rather than inside OnServe since they're plain record hooks, not
	// HTTP routes. No-op when KEHAI_WEBHOOK_URLS is unset.
	bindWebhooks(app)
	bindMoodJar(app)

	app.OnServe().BindFunc(func(se *core.ServeEvent) error {
		g := se.Router.Group("/api/couple")
		g.Bind(apis.RequireAuth("users"))
		g.POST("/create", createCouple)
		g.POST("/join", joinCouple)

		se.Router.POST("/api/heartbeat", heartbeat).Bind(apis.RequireAuth("users"))

		gQuestion := se.Router.Group("/api/question")
		gQuestion.Bind(apis.RequireAuth("users"))
		gQuestion.GET("/today", questionToday)
		gQuestion.POST("/answer", questionAnswer)

		// OwnTracks ingest does its own HTTP Basic auth (the tracker app
		// can't hold a PB session) — no RequireAuth middleware here.
		se.Router.POST("/api/owntracks", owntracksIngest)

		// Portal mode: time-limited coturn credentials (portal.go).
		se.Router.GET("/api/turn", turnCredentials).Bind(apis.RequireAuth("users"))

		se.App.Cron().MustAdd("locations_purge", "0 4 * * *", func() {
			if err := purgeOldLocations(se.App); err != nil {
				se.App.Logger().Error("locations purge failed", "error", err)
			}
		})

		se.App.Cron().MustAdd("touches_purge", "0 * * * *", func() {
			if err := purgeOldTouches(se.App); err != nil {
				se.App.Logger().Error("touches purge failed", "error", err)
			}
		})

		// Portal signals share the touches lifecycle: gone within the hour.
		se.App.Cron().MustAdd("portal_signals_purge", "0 * * * *", func() {
			if err := purgeOldPortalSignals(se.App); err != nil {
				se.App.Logger().Error("portal signals purge failed", "error", err)
			}
		})

		// Pings keep a week (see pings.go), so hourly would be wasted work
		// — once a day, in the same quiet hours as the locations sweep.
		se.App.Cron().MustAdd("pings_purge", "0 4 * * *", func() {
			if err := purgeOldPings(se.App); err != nil {
				se.App.Logger().Error("pings purge failed", "error", err)
			}
		})

		// Mood-jar beads keep a season (90d, see moodjar.go) — daily sweep.
		se.App.Cron().MustAdd("mood_entries_purge", "0 4 * * *", func() {
			if err := purgeOldMoodEntries(se.App); err != nil {
				se.App.Logger().Error("mood entries purge failed", "error", err)
			}
		})

		return se.Next()
	})
}

func createCouple(e *core.RequestEvent) error {
	if e.Auth.GetString("couple") != "" {
		return e.BadRequestError("You are already part of a couple.", nil)
	}

	body := struct {
		Name string `json:"name"`
	}{}
	if err := e.BindBody(&body); err != nil {
		return e.BadRequestError("Invalid request body.", err)
	}
	if body.Name == "" {
		body.Name = "us ♡"
	}

	couples, err := e.App.FindCollectionByNameOrId("couples")
	if err != nil {
		return e.InternalServerError("", err)
	}
	code, err := newInviteCode()
	if err != nil {
		return e.InternalServerError("", err)
	}

	couple := core.NewRecord(couples)
	couple.Set("name", body.Name)
	couple.Set("invite_code", code)
	if err := e.App.Save(couple); err != nil {
		return e.InternalServerError("Could not create couple.", err)
	}

	e.Auth.Set("couple", couple.Id)
	if err := e.App.Save(e.Auth); err != nil {
		return e.InternalServerError("Could not link you to the couple.", err)
	}

	return e.JSON(http.StatusOK, map[string]any{
		"couple_id":   couple.Id,
		"name":        couple.GetString("name"),
		"invite_code": code,
	})
}

func joinCouple(e *core.RequestEvent) error {
	if e.Auth.GetString("couple") != "" {
		return e.BadRequestError("You are already part of a couple.", nil)
	}

	body := struct {
		Code string `json:"code"`
	}{}
	if err := e.BindBody(&body); err != nil || body.Code == "" {
		return e.BadRequestError("An invite code is required.", err)
	}

	couple, err := e.App.FindFirstRecordByFilter(
		"couples",
		"invite_code = {:code}",
		dbx.Params{"code": body.Code},
	)
	if err != nil {
		return e.BadRequestError("That invite code doesn't match any couple.", nil)
	}

	members, err := e.App.FindRecordsByFilter(
		"users",
		"couple = {:id}",
		"", 0, 0,
		dbx.Params{"id": couple.Id},
	)
	if err != nil {
		return e.InternalServerError("", err)
	}
	if len(members) >= 2 {
		return e.BadRequestError("This couple is already complete (it's just for two ♡).", nil)
	}

	e.Auth.Set("couple", couple.Id)
	if err := e.App.Save(e.Auth); err != nil {
		return e.InternalServerError("Could not join the couple.", err)
	}

	return e.JSON(http.StatusOK, map[string]any{
		"couple_id": couple.Id,
		"name":      couple.GetString("name"),
	})
}

// heartbeat upserts a device record and stamps last_seen; the client derives
// the partner's phone/pc/both indicator from devices with a recent last_seen.
//
// It also accepts the Phase 2a telemetry keys (battery, charging,
// idle_seconds, now_playing, activity) per the "only provided keys are
// written" contract in kb/platform-desktop.md: a key that's absent from the
// request body is left untouched, while a key sent as explicit null/empty
// clears it back to its zero value. `timezone` (added for the dual-clock
// feature, kb/features.md) follows the exact same only-present contract.
func heartbeat(e *core.RequestEvent) error {
	body := struct {
		Kind string `json:"kind"`
		Name string `json:"name"`
	}{}
	if err := e.BindBody(&body); err != nil {
		return e.BadRequestError("Invalid request body.", err)
	}
	switch body.Kind {
	case "phone", "desktop", "tablet", "portal":
	default:
		return e.BadRequestError("kind must be one of: phone, desktop, tablet, portal.", nil)
	}
	if body.Name == "" {
		body.Name = body.Kind
	}

	// re-parsed as a raw map (the underlying request body is rereadable) so
	// we can tell "key absent" apart from "key sent as null" for the
	// optional telemetry fields below.
	info, err := e.RequestInfo()
	if err != nil {
		return e.BadRequestError("Invalid request body.", err)
	}
	raw := info.Body

	device, err := e.App.FindFirstRecordByFilter(
		"devices",
		"owner = {:owner} && kind = {:kind} && name = {:name}",
		dbx.Params{"owner": e.Auth.Id, "kind": body.Kind, "name": body.Name},
	)
	if err != nil {
		devices, cerr := e.App.FindCollectionByNameOrId("devices")
		if cerr != nil {
			return e.InternalServerError("", cerr)
		}
		device = core.NewRecord(devices)
		device.Set("owner", e.Auth.Id)
		device.Set("kind", body.Kind)
		device.Set("name", body.Name)
	}
	device.Set("last_seen", types.NowDateTime())

	if v, present := raw["battery"]; present {
		if v == nil {
			device.Set("battery", 0)
		} else {
			n, ok := v.(float64)
			if !ok || n < 0 || n > 100 {
				return e.BadRequestError("battery must be a number between 0 and 100.", nil)
			}
			device.Set("battery", n)
		}
	}

	if v, present := raw["charging"]; present {
		if v == nil {
			device.Set("charging", false)
		} else {
			b, ok := v.(bool)
			if !ok {
				return e.BadRequestError("charging must be a boolean.", nil)
			}
			device.Set("charging", b)
		}
	}

	if v, present := raw["idle_seconds"]; present {
		if v == nil {
			device.Set("idle_seconds", 0)
		} else {
			n, ok := v.(float64)
			if !ok || n < 0 {
				return e.BadRequestError("idle_seconds must be a non-negative number.", nil)
			}
			device.Set("idle_seconds", n)
		}
	}

	if v, present := raw["now_playing"]; present {
		if v == nil {
			device.Set("now_playing", nil)
		} else if m, ok := v.(map[string]any); ok {
			device.Set("now_playing", m)
		} else {
			return e.BadRequestError("now_playing must be an object or null.", nil)
		}
	}

	if v, present := raw["activity"]; present {
		if v == nil {
			device.Set("activity", "")
		} else {
			s, ok := v.(string)
			if !ok || len(s) > 100 {
				return e.BadRequestError("activity must be a string of at most 100 characters.", nil)
			}
			device.Set("activity", s)
		}
	}

	if v, present := raw["steps_today"]; present {
		if v == nil {
			device.Set("steps_today", 0)
		} else {
			n, ok := v.(float64)
			if !ok || n < 0 || n > 200000 {
				return e.BadRequestError("steps_today must be a number between 0 and 200000.", nil)
			}
			device.Set("steps_today", n)
		}
	}

	// heart_rate is the one telemetry object whose shape the server checks
	// strictly (unlike now_playing's pass-through): the client renders a
	// heart beating at this bpm, so a garbage number would animate garbage,
	// and `at` must parse for the client's freshness gate to work at all.
	if v, present := raw["heart_rate"]; present {
		if v == nil {
			device.Set("heart_rate", nil)
		} else if m, ok := v.(map[string]any); ok {
			bpm, bpmOk := m["bpm"].(float64)
			at, atOk := m["at"].(string)
			if !bpmOk || bpm < 20 || bpm > 250 || !atOk {
				return e.BadRequestError("heart_rate must be {bpm: 20-250, at: RFC3339} or null.", nil)
			}
			if _, terr := time.Parse(time.RFC3339, at); terr != nil {
				return e.BadRequestError("heart_rate.at must be an RFC3339 timestamp.", nil)
			}
			device.Set("heart_rate", map[string]any{"bpm": bpm, "at": at})
		} else {
			return e.BadRequestError("heart_rate must be {bpm: 20-250, at: RFC3339} or null.", nil)
		}
	}

	if v, present := raw["timezone"]; present {
		if v == nil {
			device.Set("timezone", "")
		} else {
			s, ok := v.(string)
			if !ok || s == "" || len(s) > 64 || !timezonePattern.MatchString(s) {
				return e.BadRequestError("timezone must be a non-empty string of at most 64 characters (letters, digits, '_+:/-' only).", nil)
			}
			device.Set("timezone", s)
		}
	}

	if err := e.App.Save(device); err != nil {
		return e.InternalServerError("Could not record heartbeat.", err)
	}

	return e.JSON(http.StatusOK, map[string]any{
		"device_id": device.Id,
		"last_seen": device.GetDateTime("last_seen"),
	})
}
