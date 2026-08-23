package main

import (
	"time"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/types"
)

// touches are the ephemeral fingertip positions behind the thumb-kiss
// feature (kb/features.md "Thumb-kiss") — nobody ever reads one more than a
// second or two old, so they're purged well before they'd otherwise expire
// naturally. Mirrors owntracks.go's purgeOldLocations.
const touchRetention = 1 * time.Hour

func purgeOldTouches(app core.App) error {
	cutoff, err := types.ParseDateTime(time.Now().Add(-touchRetention).UTC())
	if err != nil {
		return err
	}
	_, err = app.DB().NewQuery("DELETE FROM touches WHERE created < {:cutoff}").
		Bind(map[string]any{"cutoff": cutoff.String()}).Execute()
	return err
}
