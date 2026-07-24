package com.ddhhyy.skala_attendance.alarm

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.ddhhyy.skala_attendance.R

object SnoozeNotification {
    private const val channelId = "attendance_snooze_status"

    fun show(context: Context, alarm: AlarmData) {
        createChannel(context)
        val notification = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("${alarm.snoozeMinutes}분 뒤 알람이 다시 울립니다")
            .setContentText("${alarm.actionLabel} 출결 알람")
            .setWhen(alarm.scheduledAtMillis)
            .setShowWhen(true)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .addAction(
                0,
                "출결 확인",
                action(context, alarm, AlarmContract.actionOpenAttendance, 1),
            )
            .addAction(
                0,
                "다시 알림 해제",
                action(context, alarm, AlarmContract.actionDismiss, 2),
            )
            .build()
        context.getSystemService(NotificationManager::class.java)
            .notify(notificationId(alarm), notification)
    }

    fun cancel(context: Context, alarm: AlarmData) {
        context.getSystemService(NotificationManager::class.java)
            .cancel(notificationId(alarm))
    }

    private fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        context.getSystemService(NotificationManager::class.java)
            .createNotificationChannel(
                NotificationChannel(
                    channelId,
                    "다시 알림 대기",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "다시 울릴 출결 알람과 남은 동작을 표시합니다."
                    setSound(null, null)
                    enableVibration(false)
                },
            )
    }

    private fun action(
        context: Context,
        alarm: AlarmData,
        action: String,
        offset: Int,
    ): PendingIntent = PendingIntent.getBroadcast(
        context,
        alarm.occurrenceKey.hashCode() + offset,
        Intent(context, AlarmActionReceiver::class.java)
            .setAction(action)
            .putExtra(AlarmContract.extraOccurrenceKey, alarm.occurrenceKey)
            .setData(AlarmScheduler.alarmUri(alarm.occurrenceKey, action)),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun notificationId(alarm: AlarmData): Int =
        8_100 + (alarm.occurrenceKey.hashCode() and 0x0fffffff)
}
