package ru.milionchik.app.widget

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.Typeface
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.util.TypedValue
import es.antonborri.home_widget.HomeWidgetFonts
import kotlin.math.ceil
import kotlin.math.max

internal class TextStyleSpec(
    val name: String,
    val family: String?,
    val weight: Int,
    val sizeSp: Float,
    val lineHeightSp: Float,
)

internal object WidgetStyles {
    val labelM = TextStyleSpec("Label/M", "Manrope", 700, 14f, 18f)
    val displayM = TextStyleSpec("Display/M", "Unbounded", 600, 22f, 28f)
    val caption = TextStyleSpec("Caption", "Manrope", 500, 12f, 16f)
    val titleM = TextStyleSpec("Title/M", "Manrope", 700, 18f, 24f)
    val emoji = TextStyleSpec("Emoji", null, 400, 14f, 18f)
}

internal class TextLine(
    val bitmap: Bitmap,
    val widthPx: Int,
    val heightPx: Int,
)

internal class WidgetText(private val context: Context) {
    private val metrics = context.resources.displayMetrics
    private val missingFonts = mutableSetOf<String>()

    val missing: Set<String>
        get() = missingFonts

    fun sizePx(style: TextStyleSpec): Float =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, style.sizeSp, metrics)

    fun lineHeightPx(style: TextStyleSpec, scale: Float): Float =
        sizePx(style) * scale * style.lineHeightSp / style.sizeSp

    fun width(text: String, style: TextStyleSpec, scale: Float): Float {
        val paint = paint(style, scale)
        return max(paint.measureText(text), inkRight(paint, text))
    }

    fun widestWord(text: String, style: TextStyleSpec, scale: Float): Float {
        val paint = paint(style, scale)
        return text.split(' ').maxOfOrNull { paint.measureText(it) } ?: 0f
    }

    fun line(text: String, style: TextStyleSpec, scale: Float): TextLine {
        val paint = paint(style, scale)
        val lineHeight = lineHeightPx(style, scale)
        val width = ceil(max(paint.measureText(text), inkRight(paint, text))).toInt().coerceAtLeast(1)
        val height = ceil(lineHeight).toInt().coerceAtLeast(1)
        val bitmap = Bitmap.createBitmap(metrics, width, height, Bitmap.Config.ARGB_8888)
        Canvas(bitmap).drawText(text, 0f, baseline(paint, lineHeight), paint)
        return TextLine(bitmap, width, height)
    }

    fun emWidth(style: TextStyleSpec, scale: Float): Float = sizePx(style) * scale

    fun emoji(text: String, style: TextStyleSpec, scale: Float): TextLine {
        val paint = paint(style, scale)
        val lineHeight = lineHeightPx(style, scale)
        val width = ceil(emWidth(style, scale)).toInt().coerceAtLeast(1)
        val height = ceil(lineHeight).toInt().coerceAtLeast(1)
        val bitmap = Bitmap.createBitmap(metrics, width, height, Bitmap.Config.ARGB_8888)
        val x = (width - paint.measureText(text)) / 2f
        Canvas(bitmap).drawText(text, x, baseline(paint, lineHeight), paint)
        return TextLine(bitmap, width, height)
    }

    fun lines(text: String, style: TextStyleSpec, scale: Float, maxWidthPx: Int): List<String> {
        val paint = paint(style, scale)
        val layout =
            StaticLayout.Builder.obtain(text, 0, text.length, paint, maxWidthPx.coerceAtLeast(1))
                .setAlignment(Layout.Alignment.ALIGN_NORMAL)
                .setIncludePad(false)
                .build()
        return (0 until layout.lineCount).map {
            text.substring(layout.getLineStart(it), layout.getLineEnd(it)).trimEnd()
        }
    }

    fun paragraph(lines: List<String>, style: TextStyleSpec, scale: Float): TextLine {
        val paint = paint(style, scale)
        val lineHeight = lineHeightPx(style, scale)
        val width =
            ceil(lines.maxOf { max(paint.measureText(it), inkRight(paint, it)) }).toInt().coerceAtLeast(1)
        val height = ceil(lineHeight * lines.size).toInt().coerceAtLeast(1)
        val bitmap = Bitmap.createBitmap(metrics, width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val baseline = baseline(paint, lineHeight)
        lines.forEachIndexed { index, line -> canvas.drawText(line, 0f, baseline + lineHeight * index, paint) }
        return TextLine(bitmap, width, height)
    }

    private fun paint(style: TextStyleSpec, scale: Float): TextPaint =
        TextPaint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG).apply {
            typeface = typeface(style)
            textSize = sizePx(style) * scale
            color = Color.WHITE
        }

    private fun typeface(style: TextStyleSpec): Typeface {
        val family = style.family ?: return Typeface.DEFAULT
        val typeface = HomeWidgetFonts.typeface(context, family, style.weight)
        if (typeface == null) missingFonts.add("$family ${style.weight}")
        return typeface ?: Typeface.create(Typeface.DEFAULT, style.weight, false)
    }

    private fun baseline(paint: Paint, lineHeight: Float): Float {
        val fm = paint.fontMetrics
        return (lineHeight - (fm.descent - fm.ascent)) / 2f - fm.ascent
    }

    private fun inkRight(paint: Paint, text: String): Float {
        if (text.isEmpty()) return 0f
        val bounds = Rect()
        paint.getTextBounds(text, 0, text.length, bounds)
        return bounds.right.toFloat()
    }
}
