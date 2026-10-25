package ru.milionchik.app.widget

import android.content.SharedPreferences
import android.graphics.Color
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import org.json.JSONTokener

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

internal class WidgetDataException(message: String) : Exception(message)

internal object WidgetDataReader {
    private val atCharacter = Regex(" at character ([0-9]+)")
    private val moodName = Regex("^[a-z][a-zA-Z]{0,31}$")
    private const val UNKNOWN_MOOD = "unknown"

    fun read(prefs: SharedPreferences): WidgetData {
        val stored = prefs.all[WIDGET_DATA_KEY] ?: return WidgetData.Missing
        val raw =
            stored as? String
                ?: throw WidgetDataException("key=$WIDGET_DATA_KEY holds ${typeName(stored)}, expected a string")
        return parse(raw)
    }

    fun parse(raw: String): WidgetData {
        val bytes = raw.toByteArray(Charsets.UTF_8).size
        val json = root(raw, bytes)
        val version = integer(json, "v", bytes)
        if (version != WIDGET_DATA_VERSION) {
            throw WidgetDataException("data version v=$version, this build reads v=$WIDGET_DATA_VERSION ($bytes bytes)")
        }
        val themeKey = text(json, "theme", "theme", bytes)
        val theme =
            WidgetTheme.entries.firstOrNull { it.key == themeKey }
                ?: throw WidgetDataException("field theme holds an unknown theme ($bytes bytes)")
        val mood = text(json, "mood", "mood", bytes).takeIf { moodName.matches(it) } ?: UNKNOWN_MOOD
        val colors = obj(json, "colors", "colors", bytes)
        val light = palette(obj(colors, "light", "colors.light", bytes), "colors.light", bytes)
        val dark = palette(obj(colors, "dark", "colors.dark", bytes), "colors.dark", bytes)
        return when (text(json, "state", "state", bytes)) {
            "month" ->
                WidgetData.Month(
                    bytes = bytes,
                    theme = theme,
                    mood = mood,
                    light = light,
                    dark = dark,
                    emoji = text(json, "emoji", "emoji", bytes),
                    month = text(json, "month", "month", bytes),
                    total = text(json, "total", "total", bytes),
                    today = text(json, "today", "today", bytes),
                    label = text(json, "label", "label", bytes),
                    addLabel = text(json, "addLabel", "addLabel", bytes),
                )
            "signedOut" -> WidgetData.SignedOut(bytes, theme, mood, light, dark)
            else -> throw WidgetDataException("field state holds an unknown state ($bytes bytes)")
        }
    }

    private fun root(raw: String, bytes: Int): JSONObject {
        val value =
            try {
                JSONTokener(raw).nextValue()
            } catch (e: JSONException) {
                throw failure("data is not JSON, syntax error${position(e)} ($bytes bytes)", e)
            }
        return value as? JSONObject
            ?: throw WidgetDataException("data root is ${typeName(value)}, expected an object ($bytes bytes)")
    }

    private fun palette(json: JSONObject, path: String, bytes: Int) =
        WidgetPalette(
            bgSurface = color(json, "bgSurface", "$path.bgSurface", bytes),
            textPrimary = color(json, "textPrimary", "$path.textPrimary", bytes),
            textSecondary = color(json, "textSecondary", "$path.textSecondary", bytes),
            onSoft = color(json, "onSoft", "$path.onSoft", bytes),
            accent = color(json, "accent", "$path.accent", bytes),
            onAccent = color(json, "onAccent", "$path.onAccent", bytes),
        )

    private fun color(json: JSONObject, key: String, path: String, bytes: Int): Int {
        val value = text(json, key, path, bytes)
        return try {
            Color.parseColor(value)
        } catch (e: RuntimeException) {
            throw failure("field $path is not a #AARRGGBB color ($bytes bytes)", e)
        }
    }

    private fun text(json: JSONObject, key: String, path: String, bytes: Int): String {
        val value = field(json, key, path, bytes)
        return value as? String
            ?: throw WidgetDataException("field $path is ${typeName(value)}, expected a string ($bytes bytes)")
    }

    private fun integer(json: JSONObject, key: String, bytes: Int): Int {
        val value = field(json, key, key, bytes)
        val number = (value as? Number)?.toDouble()
        if (number == null || number % 1.0 != 0.0 || number < Int.MIN_VALUE || number > Int.MAX_VALUE) {
            throw WidgetDataException("field $key is ${typeName(value)}, expected an integer ($bytes bytes)")
        }
        return number.toInt()
    }

    private fun obj(json: JSONObject, key: String, path: String, bytes: Int): JSONObject {
        val value = field(json, key, path, bytes)
        return value as? JSONObject
            ?: throw WidgetDataException("field $path is ${typeName(value)}, expected an object ($bytes bytes)")
    }

    private fun field(json: JSONObject, key: String, path: String, bytes: Int): Any {
        val value = json.opt(key)
        if (value == null || value == JSONObject.NULL) {
            throw WidgetDataException("field $path is missing ($bytes bytes)")
        }
        return value
    }

    private fun typeName(value: Any?): String =
        when (value) {
            null, JSONObject.NULL -> "null"
            is String -> "a string"
            is Boolean -> "a boolean"
            is Number -> "a number"
            is JSONObject -> "an object"
            is JSONArray -> "an array"
            else -> value.javaClass.simpleName
        }

    private fun position(e: JSONException): String {
        val character = atCharacter.find(e.message.orEmpty())?.groupValues?.get(1) ?: return ""
        return " at character $character"
    }

    private fun failure(message: String, cause: Throwable): WidgetDataException =
        WidgetDataException(message).also { it.stackTrace = cause.stackTrace }
}
