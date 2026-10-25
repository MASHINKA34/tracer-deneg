package ru.milionchik.app.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import kotlin.math.min
import ru.milionchik.app.MainActivity
import ru.milionchik.app.R

internal const val MONTH_LINK = "milionchik://month"
internal const val ADD_LINK = "milionchik://add"

internal class WidgetDrawing(
    val views: RemoteViews,
    val sizes: List<SizeF>,
    val night: Boolean,
    val textScale: Float,
    val missingFonts: Set<String>,
)

internal object WidgetSizes {
    val fallback = SizeF(272f, 150f)

    fun of(manager: AppWidgetManager, id: Int): List<SizeF> {
        val options = manager.getAppWidgetOptions(id) ?: return emptyList()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            @Suppress("DEPRECATION")
            val exact = options.getParcelableArrayList<SizeF>(AppWidgetManager.OPTION_APPWIDGET_SIZES)
            if (!exact.isNullOrEmpty()) return exact.distinct()
        }
        val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
        val maxWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 0)
        val minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
        val maxHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0)
        if (minWidth <= 0 || maxWidth <= 0 || minHeight <= 0 || maxHeight <= 0) return emptyList()
        val portrait = SizeF(minWidth.toFloat(), maxHeight.toFloat())
        val landscape = SizeF(maxWidth.toFloat(), minHeight.toFloat())
        return if (portrait == landscape) listOf(portrait) else listOf(portrait, landscape)
    }

    fun describe(sizes: List<SizeF>): String =
        sizes.joinToString(",") { "${it.width.toInt()}x${it.height.toInt()}dp" }
}

internal class MonthWidgetViews(private val context: Context) {
    private val resources = context.resources
    private val text = WidgetText(context)
    private val night =
        (resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
            Configuration.UI_MODE_NIGHT_YES

    fun draw(data: WidgetData, sizes: List<SizeF>): WidgetDrawing {
        val drawn = sizes.ifEmpty { listOf(WidgetSizes.fallback) }
        var textScale = 1f
        val bySize =
            drawn.map { size ->
                val (views, scale) = build(data, size)
                textScale = min(textScale, scale)
                size to views
            }
        val views =
            when {
                bySize.size == 1 -> bySize[0].second
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> RemoteViews(bySize.toMap())
                else -> RemoteViews(bySize[1].second, bySize[0].second)
            }
        return WidgetDrawing(views, drawn, night, textScale, text.missing)
    }

    private fun build(data: WidgetData, size: SizeF): Pair<RemoteViews, Float> {
        val views = RemoteViews(context.packageName, R.layout.widget_month)
        views.setOnClickPendingIntent(R.id.widget_root, link(MONTH_LINK, 0))
        val scale =
            when (data) {
                is WidgetData.Month -> month(views, data, size)
                is WidgetData.SignedOut ->
                    signedOut(views, size) { id, surface ->
                        tint(views, id, data.theme, data.light, data.dark) {
                            if (surface) it.bgSurface else it.textPrimary
                        }
                    }
                WidgetData.Missing ->
                    signedOut(views, size) { id, surface ->
                        fallbackTint(views, id, if (surface) R.color.widget_fallback_surface else R.color.widget_fallback_text)
                    }
            }
        return views to scale
    }

    private fun month(views: RemoteViews, data: WidgetData.Month, size: SizeF): Float {
        views.setViewVisibility(R.id.widget_month_content, View.VISIBLE)
        views.setViewVisibility(R.id.widget_sign_in_content, View.GONE)
        views.setContentDescription(R.id.widget_root, data.label)
        views.setContentDescription(R.id.widget_add, data.addLabel)
        views.setOnClickPendingIntent(R.id.widget_add, link(ADD_LINK, 1))

        val density = resources.displayMetrics.density
        val columnWidth =
            (size.width * density - px(R.dimen.widget_padding_start) - px(R.dimen.widget_padding_end) -
                    px(R.dimen.widget_add_gap) - px(R.dimen.widget_add_size))
                .coerceAtLeast(1f)
        val columnHeight =
            (size.height * density - px(R.dimen.widget_padding_top) - px(R.dimen.widget_padding_bottom))
                .coerceAtLeast(1f)
        val gaps = px(R.dimen.widget_column_gap) + px(R.dimen.widget_total_gap)
        val natural =
            text.lineHeightPx(WidgetStyles.labelM, 1f) + text.lineHeightPx(WidgetStyles.displayM, 1f) +
                text.lineHeightPx(WidgetStyles.caption, 1f)
        val scale = min(1f, (columnHeight - gaps) / natural).coerceAtLeast(MIN_SCALE)

        val monthGap = px(R.dimen.widget_month_gap)
        val rowWidth =
            text.emWidth(WidgetStyles.emoji, scale) + monthGap +
                text.width(data.month, WidgetStyles.labelM, scale)
        val rowScale =
            if (rowWidth <= columnWidth) scale
            else (scale * (columnWidth - monthGap - 1f) / (rowWidth - monthGap)).coerceAtLeast(MIN_SCALE)
        val totalScale = fit(data.total, WidgetStyles.displayM, scale, columnWidth)
        val todayScale = fit(data.today, WidgetStyles.caption, scale, columnWidth)

        views.setImageViewBitmap(R.id.widget_emoji, text.emoji(data.emoji, WidgetStyles.emoji, rowScale).bitmap)
        views.setImageViewBitmap(R.id.widget_month, text.line(data.month, WidgetStyles.labelM, rowScale).bitmap)
        views.setImageViewBitmap(R.id.widget_total, text.line(data.total, WidgetStyles.displayM, totalScale).bitmap)
        views.setImageViewBitmap(R.id.widget_today, text.line(data.today, WidgetStyles.caption, todayScale).bitmap)

        tint(views, R.id.widget_card, data.theme, data.light, data.dark) { it.bgSurface }
        tint(views, R.id.widget_month, data.theme, data.light, data.dark) { it.onSoft }
        tint(views, R.id.widget_total, data.theme, data.light, data.dark) { it.textPrimary }
        tint(views, R.id.widget_today, data.theme, data.light, data.dark) { it.textSecondary }
        tint(views, R.id.widget_add_circle, data.theme, data.light, data.dark) { it.accent }
        tint(views, R.id.widget_add_icon, data.theme, data.light, data.dark) { it.onAccent }
        return minOf(rowScale, totalScale, todayScale)
    }

    private fun signedOut(
        views: RemoteViews,
        size: SizeF,
        colors: (Int, Boolean) -> Unit,
    ): Float {
        views.setViewVisibility(R.id.widget_month_content, View.GONE)
        views.setViewVisibility(R.id.widget_sign_in_content, View.VISIBLE)
        val label = resources.getString(R.string.widget_sign_in)
        views.setContentDescription(R.id.widget_root, label)

        val density = resources.displayMetrics.density
        val width =
            (size.width * density - px(R.dimen.widget_padding_start) - px(R.dimen.widget_padding_end))
                .coerceAtLeast(1f)
        val height =
            (size.height * density - px(R.dimen.widget_padding_top) - px(R.dimen.widget_padding_bottom))
                .coerceAtLeast(1f)
        var scale = 1f
        var lines = text.lines(label, WidgetStyles.titleM, scale, width.toInt())
        while (scale > MIN_SCALE &&
            (text.widestWord(label, WidgetStyles.titleM, scale) > width ||
                lines.size * text.lineHeightPx(WidgetStyles.titleM, scale) > height)
        ) {
            scale -= SCALE_STEP
            lines = text.lines(label, WidgetStyles.titleM, scale, width.toInt())
        }
        views.setImageViewBitmap(R.id.widget_sign_in, text.paragraph(lines, WidgetStyles.titleM, scale).bitmap)
        colors(R.id.widget_card, true)
        colors(R.id.widget_sign_in, false)
        return scale
    }

    private fun fit(value: String, style: TextStyleSpec, scale: Float, width: Float): Float {
        val natural = text.width(value, style, scale)
        if (natural <= width) return scale
        return (scale * (width - 1f) / natural).coerceAtLeast(MIN_SCALE)
    }

    private fun tint(
        views: RemoteViews,
        id: Int,
        theme: WidgetTheme,
        light: WidgetPalette,
        dark: WidgetPalette,
        pick: (WidgetPalette) -> Int,
    ) {
        when {
            theme == WidgetTheme.LIGHT -> views.setInt(id, COLOR_FILTER, pick(light))
            theme == WidgetTheme.DARK -> views.setInt(id, COLOR_FILTER, pick(dark))
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ->
                views.setColorInt(id, COLOR_FILTER, pick(light), pick(dark))
            else -> views.setInt(id, COLOR_FILTER, pick(if (night) dark else light))
        }
    }

    private fun fallbackTint(views: RemoteViews, id: Int, color: Int) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            views.setColor(id, COLOR_FILTER, color)
        } else {
            views.setInt(id, COLOR_FILTER, context.getColor(color))
        }
    }

    private fun link(uri: String, requestCode: Int): PendingIntent {
        val intent =
            Intent(Intent.ACTION_VIEW, Uri.parse(uri), context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun px(id: Int): Float = resources.getDimension(id)

    private companion object {
        const val COLOR_FILTER = "setColorFilter"
        const val MIN_SCALE = 0.3f
        const val SCALE_STEP = 0.05f
    }
}
