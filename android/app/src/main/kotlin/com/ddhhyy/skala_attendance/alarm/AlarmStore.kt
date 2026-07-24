package com.ddhhyy.skala_attendance.alarm

import android.content.Context
import org.json.JSONArray

object AlarmStore {
    private const val preferencesName = "native_alarm_store"
    private const val alarmsKey = "alarms"

    @Synchronized
    fun all(context: Context): List<AlarmData> {
        val raw = preferences(context).getString(alarmsKey, "[]") ?: "[]"
        return runCatching {
            val array = JSONArray(raw)
            buildList {
                for (index in 0 until array.length()) {
                    AlarmData.fromJson(array.getJSONObject(index))?.let(::add)
                }
            }
        }.getOrDefault(emptyList())
    }

    @Synchronized
    fun find(context: Context, occurrenceKey: String): AlarmData? =
        all(context).firstOrNull { it.occurrenceKey == occurrenceKey }

    @Synchronized
    fun replaceAll(context: Context, alarms: List<AlarmData>) {
        write(context, alarms)
    }

    @Synchronized
    fun upsert(context: Context, alarm: AlarmData) {
        val alarms = all(context)
            .filterNot { it.occurrenceKey == alarm.occurrenceKey }
            .plus(alarm)
        write(context, alarms)
    }

    @Synchronized
    fun remove(context: Context, occurrenceKey: String) {
        write(context, all(context).filterNot { it.occurrenceKey == occurrenceKey })
    }

    private fun write(context: Context, alarms: List<AlarmData>) {
        val array = JSONArray()
        alarms.forEach { array.put(it.toJson()) }
        preferences(context).edit().putString(alarmsKey, array.toString()).apply()
    }

    private fun preferences(context: Context) =
        context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
}
