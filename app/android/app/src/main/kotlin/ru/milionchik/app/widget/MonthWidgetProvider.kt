package ru.milionchik.app.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Bundle
import android.os.SystemClock
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider

class MonthWidgetProvider : HomeWidgetProvider() {
    private var reason = "system"

    override fun onReceive(context: Context, intent: Intent) {
        reason =
            when {
                intent.getBooleanExtra(HomeWidgetPlugin.TRIGGERED_FROM_HOME_WIDGET, false) -> "app"
                intent.action == AppWidgetManager.ACTION_APPWIDGET_UPDATE -> "system"
                else -> intent.action?.substringAfterLast('.') ?: "unknown"
            }
        WidgetLog.debug { "widget broadcast action=${intent.action} reason=$reason" }
        super.onReceive(context, intent)
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        WidgetLog.debug { "widget update reason=$reason ids=${appWidgetIds.joinToString(",")}" }
        val data = read(widgetData)
        for (id in appWidgetIds) draw(context, appWidgetManager, id, data, reason)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        WidgetLog.debug { "widget $appWidgetId options changed → redrawing for the new size" }
        draw(context, appWidgetManager, appWidgetId, read(HomeWidgetPlugin.getData(context)), "resize")
    }

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        WidgetLog.info("widget enabled: the first month widget is on the home screen")
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        WidgetLog.info("widget removed from the home screen ids=${appWidgetIds.joinToString(",")}")
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        WidgetLog.info("widget disabled: no month widget is left on the home screen")
    }

    private fun read(prefs: SharedPreferences): WidgetData {
        val started = SystemClock.elapsedRealtime()
        return try {
            WidgetDataReader.read(prefs).also {
                if (it == WidgetData.Missing) {
                    WidgetLog.info(
                        "widget data: key=$WIDGET_DATA_KEY not saved yet → «sign in» state on the fallback colors",
                    )
                } else {
                    WidgetLog.debug {
                        "widget data read: ${it.javaClass.simpleName} ${it.bytes} bytes " +
                            "in ${SystemClock.elapsedRealtime() - started}ms"
                    }
                }
            }
        } catch (e: Exception) {
            WidgetLog.error(
                "widget data unreadable key=$WIDGET_DATA_KEY: ${WidgetLog.describe(e)} → " +
                    "«sign in» state on the fallback colors until the app saves new data",
                e,
            )
            WidgetData.Missing
        }
    }

    private fun draw(context: Context, manager: AppWidgetManager, id: Int, data: WidgetData, reason: String) {
        val started = SystemClock.elapsedRealtime()
        val fontScale = context.resources.configuration.fontScale
        var sizes = "unknown"
        try {
            val reported = WidgetSizes.of(manager, id)
            sizes = if (reported.isEmpty()) "unknown" else WidgetSizes.describe(reported)
            if (reported.isEmpty()) {
                WidgetLog.warn(
                    "widget $id: the launcher reported no size → drawing for " +
                        WidgetSizes.describe(listOf(WidgetSizes.fallback)),
                )
            }
            val drawing = MonthWidgetViews(context).draw(data, reported)
            if (drawing.missingFonts.isNotEmpty()) {
                WidgetLog.warn(
                    "widget $id: fonts ${drawing.missingFonts.joinToString(", ")} not found in " +
                        "flutter_assets/FontManifest.json → system font instead",
                )
            }
            manager.updateAppWidget(id, drawing.views)
            WidgetLog.info(
                "widget $id drawn reason=$reason ${describe(data)} night=${drawing.night} " +
                    "size=${WidgetSizes.describe(drawing.sizes)} fontScale=$fontScale " +
                    "textScale=${"%.2f".format(java.util.Locale.ROOT, drawing.textScale)} " +
                    "in ${SystemClock.elapsedRealtime() - started}ms",
            )
        } catch (e: Exception) {
            WidgetLog.error(
                "widget $id not drawn reason=$reason ${describe(data)} size=$sizes fontScale=$fontScale " +
                    "after ${SystemClock.elapsedRealtime() - started}ms: ${WidgetLog.describe(e)} → " +
                    "trying the «sign in» state",
                e,
            )
            if (data != WidgetData.Missing) drawFallback(context, manager, id)
        }
    }

    private fun drawFallback(context: Context, manager: AppWidgetManager, id: Int) {
        try {
            manager.updateAppWidget(id, MonthWidgetViews(context).draw(WidgetData.Missing, emptyList()).views)
            WidgetLog.warn("widget $id: drew the «sign in» state on the fallback colors instead")
        } catch (e: Exception) {
            WidgetLog.error("widget $id: the «sign in» state did not draw either: ${WidgetLog.describe(e)}", e)
        }
    }

    private fun describe(data: WidgetData): String =
        when (data) {
            is WidgetData.Month -> "state=month theme=${data.theme.key} mood=${data.mood}"
            is WidgetData.SignedOut -> "state=signedOut theme=${data.theme.key} mood=${data.mood}"
            WidgetData.Missing -> "state=missing theme=system"
        }
}
