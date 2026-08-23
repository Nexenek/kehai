package app.kehai.widget

import es.antonborri.home_widget.HomeWidgetGlanceWidgetReceiver

/**
 * The manifest-declared `AppWidgetProvider` for the partner widget.
 * `home_widget`'s [HomeWidgetGlanceWidgetReceiver] handles pulling the
 * latest `HomeWidgetPreferences` into Glance state before every
 * `PartnerWidgetAppWidget.provideGlance` call — see that base class for
 * why plain `GlanceAppWidgetReceiver` isn't enough here.
 *
 * The fully-qualified name of this class (`app.kehai.widget.
 * PartnerWidgetReceiver`) is what `HomeWidget.updateWidget(
 * qualifiedAndroidName: ...)` targets from Dart — see
 * `lib/data/services/background/partner_widget.dart`'s
 * `partnerWidgetReceiver` constant. Keep them in sync.
 */
class PartnerWidgetReceiver : HomeWidgetGlanceWidgetReceiver<PartnerWidgetAppWidget>() {
    override val glanceAppWidget = PartnerWidgetAppWidget()
}
