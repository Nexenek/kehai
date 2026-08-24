package main

import (
	"time"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/types"
)

// The mood jar's write side (see migrations/15_moodjar.go for the read
// side and the why): whenever a user's status lands with a mood that's
// actually NEW, one `mood_entries` bead is appended on their couple.
//
// The dedupe matters: statuses are also saved for note-only edits, and the
// jar should hold feelings, not keystrokes. e.Record.Original() carries the
// pre-save copy, so "changed" is a plain string compare.

// How long beads stay in the jar. A season of feelings, not an archive.
const moodEntryRetention = 90 * 24 * time.Hour

func bindMoodJar(app core.App) {
	app.OnRecordAfterCreateSuccess("statuses").BindFunc(func(e *core.RecordEvent) error {
		appendMoodEntry(e.App, e.Record, "")
		return e.Next()
	})
	app.OnRecordAfterUpdateSuccess("statuses").BindFunc(func(e *core.RecordEvent) error {
		appendMoodEntry(e.App, e.Record, e.Record.Original().GetString("mood"))
		return e.Next()
	})
}

// appendMoodEntry drops a bead unless the mood is empty or unchanged.
// Failures are logged, never returned: a full jar is not worth a failed
// mood save (same stance as the webhooks fired off these events).
func appendMoodEntry(app core.App, status *core.Record, previousMood string) {
	mood := status.GetString("mood")
	if mood == "" || mood == previousMood {
		return
	}

	user, err := app.FindRecordById("users", status.GetString("user"))
	if err != nil {
		app.Logger().Warn("mood jar: status without a loadable user", "error", err)
		return
	}
	coupleId := user.GetString("couple")
	if coupleId == "" {
		// Not paired yet — moods exist, the jar doesn't.
		return
	}

	entries, err := app.FindCollectionByNameOrId("mood_entries")
	if err != nil {
		app.Logger().Warn("mood jar: collection missing", "error", err)
		return
	}
	entry := core.NewRecord(entries)
	entry.Set("couple", coupleId)
	entry.Set("user", user.Id)
	entry.Set("mood", mood)
	entry.Set("note", status.GetString("note"))
	if err := app.Save(entry); err != nil {
		app.Logger().Warn("mood jar: could not append entry", "error", err)
	}
}

func purgeOldMoodEntries(app core.App) error {
	cutoff, err := types.ParseDateTime(time.Now().Add(-moodEntryRetention).UTC())
	if err != nil {
		return err
	}
	_, err = app.DB().NewQuery("DELETE FROM mood_entries WHERE created < {:cutoff}").
		Bind(map[string]any{"cutoff": cutoff.String()}).Execute()
	return err
}
