package app.kehai.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import app.kehai.MainActivity
import es.antonborri.home_widget.HomeWidgetGlanceState
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition
import es.antonborri.home_widget.actionStartActivity

/**
 * Glance rendering of design-language.md's "signature element" — the
 * partner window — shrunk to a home-screen widget: partner name, mood
 * kaomoji (large), ambient line, and "updated Xm ago".
 *
 * This class owns zero business logic, exactly like the ongoing
 * notification's Kotlin side (see `KehaiForegroundTask`/
 * `partner_notification.dart`): it only reads the four keys the Dart side
 * last wrote via `home_widget` (`lib/data/services/background/
 * partner_widget.dart`) and renders them. `mood`/`ambient` precedence and
 * "waiting for your person" copy live in exactly one place — Dart — so
 * this file never drifts from the notification or the in-app partner
 * card.
 *
 * Tap-anywhere just opens the app ([MainActivity]); there are
 * deliberately no `actionRunCallback`s here.
 */
class PartnerWidgetAppWidget : GlanceAppWidget() {

    // Backed by the same `HomeWidgetPreferences` SharedPreferences file
    // `HomeWidget.saveWidgetData` writes to, via home_widget's own state
    // definition — see HomeWidgetGlanceStateDefinition.
    override val stateDefinition = HomeWidgetGlanceStateDefinition()

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent { PartnerWidgetContent(context, currentState()) }
    }
}

private val BgColor = Color(0xFFFDF3F8)
private val ChromeColor = Color(0xFFF4CBDC)
private val InkColor = Color(0xFF362D3B)

private const val KEY_PARTNER_NAME = "partner_name"
private const val KEY_MOOD_KAOMOJI = "mood_kaomoji"
private const val KEY_AMBIENT_LINE = "ambient_line"
private const val KEY_UPDATED_EPOCH_MS = "updated_epoch_ms"

@Composable
private fun PartnerWidgetContent(context: Context, currentState: HomeWidgetGlanceState) {
    val prefs = currentState.preferences
    val partnerName = prefs.getString(KEY_PARTNER_NAME, null)
    val kaomoji = prefs.getString(KEY_MOOD_KAOMOJI, null)
    val ambientLine = prefs.getString(KEY_AMBIENT_LINE, null)
    val updatedEpochMs =
        if (prefs.contains(KEY_UPDATED_EPOCH_MS)) prefs.getLong(KEY_UPDATED_EPOCH_MS, 0L)
        else null

    Column(
        modifier =
            GlanceModifier.fillMaxSize()
                .background(BgColor)
                .cornerRadius(16.dp)
                .clickable(actionStartActivity<MainActivity>(context)),
    ) {
        // chrome-pink header strip
        Box(
            modifier =
                GlanceModifier.fillMaxWidth()
                    .background(ChromeColor)
                    .padding(horizontal = 12.dp, vertical = 6.dp),
        ) {
            Text(
                text = partnerName ?: "kehai",
                style =
                    TextStyle(
                        color = ColorProvider(InkColor),
                        fontWeight = FontWeight.Bold,
                        fontSize = 14.sp,
                    ),
                maxLines = 1,
            )
        }

        if (partnerName == null) {
            EmptyState()
        } else {
            Column(
                modifier = GlanceModifier.fillMaxSize().padding(12.dp),
                horizontalAlignment = Alignment.Horizontal.CenterHorizontally,
                verticalAlignment = Alignment.Vertical.CenterVertically,
            ) {
                Text(
                    text = kaomoji ?: "",
                    style = TextStyle(color = ColorProvider(InkColor), fontSize = 28.sp),
                    maxLines = 1,
                )
                if (!ambientLine.isNullOrEmpty()) {
                    Spacer(modifier = GlanceModifier.height(4.dp))
                    Text(
                        text = ambientLine,
                        style = TextStyle(color = ColorProvider(InkColor), fontSize = 13.sp),
                        maxLines = 1,
                    )
                }
                if (updatedEpochMs != null) {
                    Spacer(modifier = GlanceModifier.height(4.dp))
                    Text(
                        text = formatUpdated(updatedEpochMs),
                        style = TextStyle(color = ColorProvider(InkColor), fontSize = 11.sp),
                        maxLines = 1,
                    )
                }
            }
        }
    }
}

@Composable
private fun EmptyState() {
    Column(
        modifier = GlanceModifier.fillMaxSize().padding(12.dp),
        horizontalAlignment = Alignment.Horizontal.CenterHorizontally,
        verticalAlignment = Alignment.Vertical.CenterVertically,
    ) {
        Text(
            text = "waiting for them ( . .)",
            style = TextStyle(color = ColorProvider(InkColor), fontSize = 13.sp),
        )
    }
}

/** "updated Xm ago" / "updated Xh ago" / "updated just now", from an epoch millis. */
private fun formatUpdated(epochMs: Long): String {
    val deltaMs = System.currentTimeMillis() - epochMs
    val minutes = deltaMs / 60_000
    return when {
        minutes < 1 -> "updated just now"
        minutes < 60 -> "updated ${minutes}m ago"
        else -> "updated ${minutes / 60}h ago"
    }
}
