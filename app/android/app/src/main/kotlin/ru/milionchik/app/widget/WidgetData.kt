package ru.milionchik.app.widget

import android.content.SharedPreferences
import android.graphics.Color
import org.json.JSONException
import org.json.JSONObject

internal const val WIDGET_DATA_KEY = "milionchik.widget"
internal const val WIDGET_DATA_VERSION = 1

internal enum class WidgetTheme(val key: String) {
    SYSTEM("system"),
    LIGHT("light"),
    DARK("dark"),
}

internal class WidgetPalette(
    val bgSurface: Int,
    val textPrimary: Int,
    val textSecondary: Int,
    val onSoft: Int,
    val accent: Int,
    val onAccent: Int,
)

internal sealed interface WidgetData {
    val bytes: Int

    data class Month(
        override val bytes: Int,
        val theme: WidgetTheme,
        val mood: String,
        val light: WidgetPalette,
        val dark: WidgetPalette,
        val emoji: String,
        val month: String,
        val total: String,
        val today: String,
        val label: String,
        val addLabel: String,
    ) : WidgetData

    data class SignedOut(
        override val bytes: Int,
        val theme: WidgetTheme,
        val mood: String,
        val light: WidgetPalette,
        val dark: WidgetPalette,
    ) : WidgetData

    data object Missing : WidgetData {
        override val bytes = 0
    }
}

internal class WidgetDataException(message: String, cause: Throwable? = null) :
    Exception(message, cause)

internal object WidgetDataReader {
    fun read(prefs: SharedPreferences): WidgetData {
        val raw =
            try {
                prefs.getString(WIDGET_DATA_KEY, null)
            } catch (e: ClassCastException) {
                throw WidgetDataException("key=$WIDGET_DATA_KEY holds a value that is not a string", e)
            }
        return if (raw == null) WidgetData.Missing else parse(raw)
    }

    fun parse(raw: String): WidgetData {
        val bytes = raw.toByteArray(Charsets.UTF_8).size
        try {
            val json = JSONObject(raw)
            val version = json.getInt("v")
            if (version != WIDGET_DATA_VERSION) {
                throw WidgetDataException(
                    "data version v=$version, this build reads v=$WIDGET_DATA_VERSION ($bytes bytes)",
                )
            }
            val themeKey = json.getString("theme")
            val theme =
                WidgetTheme.entries.firstOrNull { it.key == themeKey }
                    ?: throw WidgetDataException("unknown theme=$themeKey ($bytes bytes)")
            val mood = json.getString("mood")
            val colors = json.getJSONObject("colors")
            val light = palette(colors.getJSONObject("light"), "light")
            val dark = palette(colors.getJSONObject("dark"), "dark")
            return when (val state = json.getString("state")) {
                "month" ->
                    WidgetData.Month(
                        bytes = bytes,
                        theme = theme,
                        mood = mood,
                        light = light,
                        dark = dark,
                        emoji = json.getString("emoji"),
                        month = json.getString("month"),
                        total = json.getString("total"),
                        today = json.getString("today"),
                        label = json.getString("label"),
                        addLabel = json.getString("addLabel"),
                    )
                "signedOut" -> WidgetData.SignedOut(bytes, theme, mood, light, dark)
                else -> throw WidgetDataException("unknown state=$state ($bytes bytes)")
            }
        } catch (e: JSONException) {
            throw WidgetDataException("data is not the v=$WIDGET_DATA_VERSION JSON ($bytes bytes): ${e.message}", e)
        }
    }

    private fun palette(json: JSONObject, name: String) =
        WidgetPalette(
            bgSurface = color(json, name, "bgSurface"),
            textPrimary = color(json, name, "textPrimary"),
            textSecondary = color(json, name, "textSecondary"),
            onSoft = color(json, name, "onSoft"),
            accent = color(json, name, "accent"),
            onAccent = color(json, name, "onAccent"),
        )

    private fun color(json: JSONObject, palette: String, key: String): Int {
        val value = json.getString(key)
        return try {
            Color.parseColor(value)
        } catch (e: IllegalArgumentException) {
            throw WidgetDataException("colors.$palette.$key=$value is not a #AARRGGBB color", e)
        }
    }
}
