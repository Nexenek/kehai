package app.kehai

import android.service.notification.NotificationListenerService

/**
 * Intentionally empty.
 *
 * We don't want to read notifications — we want
 * `MediaSessionManager.getActiveSessions()`, and Android gates that behind
 * "you must pass the ComponentName of an *enabled* NotificationListener"
 * (kb/platform-android.md, "Now-playing"). So this class exists purely as
 * the component the user ticks in Settings > Notification access; it
 * overrides nothing, stores nothing, and forwards nothing.
 *
 * That asymmetry — a broad-sounding grant used for a narrow purpose — is
 * why the "phone superpowers" screen says so out loud instead of glossing
 * it as "for music" (design-language.md: "Privacy controls use honest
 * language").
 *
 * If a future phase needs the media-notification fallback for players with
 * odd MediaSessions, `onNotificationPosted` is the hook — and the copy in
 * AppStrings has to be updated in the same change.
 */
class KehaiNotificationListenerService : NotificationListenerService()
