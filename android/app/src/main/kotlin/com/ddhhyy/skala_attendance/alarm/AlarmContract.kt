package com.ddhhyy.skala_attendance.alarm

object AlarmContract {
    const val extraOccurrenceKey = "alarmOccurrenceKey"
    const val extraAttendancePayload = "alarmAttendancePayload"
    const val actionDismiss = "com.ddhhyy.skala_attendance.alarm.DISMISS"
    const val actionSnooze = "com.ddhhyy.skala_attendance.alarm.SNOOZE"
    const val actionOpenAttendance = "com.ddhhyy.skala_attendance.alarm.OPEN_ATTENDANCE"
    const val actionSilence = "com.ddhhyy.skala_attendance.alarm.SILENCE"
    const val notificationId = 7401
}

object AlarmBridge {
    @Volatile
    var pendingAttendancePayload: String? = null

    fun takePayload(): String? {
        val payload = pendingAttendancePayload
        pendingAttendancePayload = null
        return payload
    }
}
