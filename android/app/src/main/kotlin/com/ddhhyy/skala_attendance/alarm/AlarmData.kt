package com.ddhhyy.skala_attendance.alarm

import org.json.JSONObject

data class AlarmData(
    val occurrenceKey: String,
    val scheduleId: String,
    val action: String,
    val actionLabel: String,
    val scheduledAtMillis: Long,
    val soundUri: String?,
    val volumePercent: Int,
    val vibrationEnabled: Boolean,
    val gradualVolumeEnabled: Boolean,
    val snoozeMinutes: Int,
    val maximumSnoozeCount: Int?,
    val snoozeCount: Int,
    val attendancePayload: String,
) {
    fun toJson(): JSONObject = JSONObject()
        .put("occurrenceKey", occurrenceKey)
        .put("scheduleId", scheduleId)
        .put("action", action)
        .put("actionLabel", actionLabel)
        .put("scheduledAtMillis", scheduledAtMillis)
        .put("soundUri", soundUri ?: JSONObject.NULL)
        .put("volumePercent", volumePercent)
        .put("vibrationEnabled", vibrationEnabled)
        .put("gradualVolumeEnabled", gradualVolumeEnabled)
        .put("snoozeMinutes", snoozeMinutes)
        .put("maximumSnoozeCount", maximumSnoozeCount ?: JSONObject.NULL)
        .put("snoozeCount", snoozeCount)
        .put("attendancePayload", attendancePayload)

    fun snoozed(now: Long): AlarmData {
        val nextCount = snoozeCount + 1
        return copy(
            occurrenceKey = "$occurrenceKey#snooze$nextCount",
            scheduledAtMillis = now + snoozeMinutes * 60_000L,
            snoozeCount = nextCount,
        )
    }

    fun canSnooze(): Boolean =
        maximumSnoozeCount == null || snoozeCount < maximumSnoozeCount

    fun shouldSnoozeFromVolumeButton(): Boolean {
        val repeatConfigured =
            maximumSnoozeCount == null || maximumSnoozeCount > 1
        return repeatConfigured && canSnooze()
    }

    companion object {
        fun fromMap(value: Map<*, *>): AlarmData? = runCatching {
            AlarmData(
                occurrenceKey = value.string("occurrenceKey"),
                scheduleId = value.string("scheduleId"),
                action = value.string("action"),
                actionLabel = value.string("actionLabel"),
                scheduledAtMillis = value.long("scheduledAtMillis"),
                soundUri = value["soundUri"] as? String,
                volumePercent = value.int("volumePercent").coerceIn(0, 100),
                vibrationEnabled = value.boolean("vibrationEnabled"),
                gradualVolumeEnabled = value.boolean("gradualVolumeEnabled"),
                snoozeMinutes = value.int("snoozeMinutes"),
                maximumSnoozeCount = (value["maximumSnoozeCount"] as? Number)?.toInt(),
                snoozeCount = value.int("snoozeCount"),
                attendancePayload = value.string("attendancePayload"),
            )
        }.getOrNull()

        fun fromJson(value: JSONObject): AlarmData? = runCatching {
            AlarmData(
                occurrenceKey = value.getString("occurrenceKey"),
                scheduleId = value.getString("scheduleId"),
                action = value.getString("action"),
                actionLabel = value.getString("actionLabel"),
                scheduledAtMillis = value.getLong("scheduledAtMillis"),
                soundUri = value.optString("soundUri").takeIf { it.isNotBlank() },
                volumePercent = value.getInt("volumePercent").coerceIn(0, 100),
                vibrationEnabled = value.getBoolean("vibrationEnabled"),
                gradualVolumeEnabled = value.getBoolean("gradualVolumeEnabled"),
                snoozeMinutes = value.getInt("snoozeMinutes"),
                maximumSnoozeCount = if (value.isNull("maximumSnoozeCount")) {
                    null
                } else {
                    value.getInt("maximumSnoozeCount")
                },
                snoozeCount = value.getInt("snoozeCount"),
                attendancePayload = value.getString("attendancePayload"),
            )
        }.getOrNull()

        private fun Map<*, *>.string(key: String) =
            (this[key] as? String).orEmpty().also { require(it.isNotBlank()) }

        private fun Map<*, *>.int(key: String) = (this[key] as Number).toInt()
        private fun Map<*, *>.long(key: String) = (this[key] as Number).toLong()
        private fun Map<*, *>.boolean(key: String) = this[key] as Boolean
    }
}
