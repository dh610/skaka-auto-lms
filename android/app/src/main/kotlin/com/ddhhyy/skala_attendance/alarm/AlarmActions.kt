package com.ddhhyy.skala_attendance.alarm

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import com.ddhhyy.skala_attendance.MainActivity

object AlarmActions {
    fun perform(context: Context, action: String, occurrenceKey: String) {
        val alarm = AlarmStore.find(context, occurrenceKey)
        when (action) {
            AlarmContract.actionSnooze -> {
                val snoozed = alarm?.let { AlarmScheduler.snooze(context, it) }
                if (snoozed != null) SnoozeNotification.show(context, snoozed)
            }
            AlarmContract.actionOpenAttendance -> {
                if (alarm != null) {
                    AlarmScheduler.cancel(context, alarm)
                    SnoozeNotification.cancel(context, alarm)
                    AlarmBridge.pendingAttendancePayload = alarm.attendancePayload
                    context.startActivity(
                        Intent(context, MainActivity::class.java)
                            .putExtra(
                                AlarmContract.extraAttendancePayload,
                                alarm.attendancePayload,
                            )
                            .addFlags(
                                Intent.FLAG_ACTIVITY_NEW_TASK or
                                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                                    Intent.FLAG_ACTIVITY_SINGLE_TOP,
                            ),
                    )
                }
            }
            AlarmContract.actionDismiss -> {
                if (alarm != null) {
                    AlarmScheduler.cancel(context, alarm)
                    SnoozeNotification.cancel(context, alarm)
                }
            }
        }
        AlarmStore.remove(context, occurrenceKey)
        context.stopService(Intent(context, AlarmRingingService::class.java))
        context.getSystemService(NotificationManager::class.java)
            .cancel(AlarmContract.notificationId)
    }
}

class AlarmActionReceiver : android.content.BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val occurrenceKey = intent.getStringExtra(AlarmContract.extraOccurrenceKey) ?: return
        AlarmActions.perform(context, intent.action.orEmpty(), occurrenceKey)
    }
}
