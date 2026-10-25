package ru.milionchik.app.widget

import android.util.Log
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter

internal object WidgetLog {
    private const val TAG = "milionchik"
    private const val MODULE = "widget"
    private const val MAX_ENTRY_CHARS = 1800
    private val time = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSSxxx")

    val debugEnabled: Boolean
        get() = Log.isLoggable(TAG, Log.DEBUG)

    fun debug(message: () -> String) {
        if (debugEnabled) write(Log.DEBUG, "DEBUG", message(), null)
    }

    fun info(message: String) = write(Log.INFO, "INFO", message, null)

    fun warn(message: String, error: Throwable? = null) = write(Log.WARN, "WARN", message, error)

    fun error(message: String, error: Throwable) = write(Log.ERROR, "ERROR", message, error)

    fun describe(error: Throwable): String {
        val parts = mutableListOf("${error.javaClass.name}: ${error.message}")
        var cause = error.cause
        while (cause != null && parts.size < 5) {
            parts.add("cause ${cause.javaClass.name}: ${cause.message}")
            cause = cause.cause
        }
        return parts.joinToString(" | ")
    }

    private fun write(priority: Int, label: String, message: String, error: Throwable?) {
        val lines = mutableListOf("${OffsetDateTime.now().format(time)} ${label.padEnd(5)} [$MODULE] $message")
        if (error != null) {
            val description = describe(error)
            if (!message.contains(description)) lines.add("  error: $description")
            lines.add("  stack:")
            Log.getStackTraceString(error).trimEnd().lines().forEach { lines.add("    ${it.trim()}") }
        }
        for (line in lines) {
            line.chunked(MAX_ENTRY_CHARS).forEach { Log.println(priority, TAG, it) }
        }
    }
}
