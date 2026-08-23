package main

import (
	"time"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/types"
)

// pings are the one-tap "thinking of you" nudges (kb/features.md). Unlike
// touches — which nobody reads a second after they land — a ping is worth
// glancing back at for a day or two ("she sent three hugs yesterday"), so
// they keep a week before the cron sweeps them. Mirrors purgeOldTouches in
// touches.go / purgeOldLocations in owntracks.go.
const pingRetention = 7 * 24 * time.Hour

func purgeOldPings(app core.App) error {
	cutoff, err := types.ParseDateTime(time.Now().Add(-pingRetention).UTC())
	if err != nil {
		return err
	}
	_, err = app.DB().NewQuery("DELETE FROM pings WHERE created < {:cutoff}").
		Bind(map[string]any{"cutoff": cutoff.String()}).Execute()
	return err
}
