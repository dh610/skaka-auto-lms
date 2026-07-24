package com.ddhhyy.skala_attendance.alarm

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri

object AlarmScheduler {
    fun sync(context: Context, alarms: List<AlarmData>) {
        AlarmStore.all(context).forEach { cancel(context, it) }
        AlarmStore.replaceAll(context, alarms)
        alarms.filter { it.scheduledAtMillis > System.currentTimeMillis() }
            .forEach { schedule(context, it) }
    }

    fun restore(context: Context) {
        AlarmStore.all(context)
            .filter { it.scheduledAtMillis > System.currentTimeMillis() }
            .forEach { schedule(context, it) }
    }

    fun snooze(context: Context, alarm: AlarmData) {
        if (!alarm.canSnooze()) return
        AlarmStore.remove(context, alarm.occurrenceKey)
        val snoozed = alarm.snoozed(System.currentTimeMillis())
        AlarmStore.upsert(context, snoozed)
        schedule(context, snoozed)
    }

    private fun schedule(context: Context, alarm: AlarmData) {
        val manager = context.getSystemService(AlarmManager::class.java)
        val operation =
            alarmPendingIntent(context, alarm, PendingIntent.FLAG_UPDATE_CURRENT)
                ?: error("알람 PendingIntent를 만들 수 없습니다.")
        val showIntent = PendingIntent.getActivity(
            context,
            alarm.occurrenceKey.hashCode(),
            Intent(context, AlarmActivity::class.java)
                .putExtra(AlarmContract.extraOccurrenceKey, alarm.occurrenceKey)
                .setData(alarmUri(alarm.occurrenceKey, "show")),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        manager.setAlarmClock(
            AlarmManager.AlarmClockInfo(alarm.scheduledAtMillis, showIntent),
            operation,
        )
    }

    private fun cancel(context: Context, alarm: AlarmData) {
        val manager = context.getSystemService(AlarmManager::class.java)
        val operation = alarmPendingIntent(context, alarm, PendingIntent.FLAG_NO_CREATE)
        if (operation != null) {
            manager.cancel(operation)
            operation.cancel()
        }
    }

    private fun alarmPendingIntent(
        context: Context,
        alarm: AlarmData,
        lookupFlag: Int,
    ): PendingIntent? = PendingIntent.getBroadcast(
        context,
        alarm.occurrenceKey.hashCode(),
        Intent(context, AlarmReceiver::class.java)
            .putExtra(AlarmContract.extraOccurrenceKey, alarm.occurrenceKey)
            .setData(alarmUri(alarm.occurrenceKey, "trigger")),
        lookupFlag or PendingIntent.FLAG_IMMUTABLE,
    )

    fun alarmUri(occurrenceKey: String, purpose: String): Uri =
        Uri.Builder()
            .scheme("skala-alarm")
            .authority(purpose)
            .appendPath(occurrenceKey)
            .build()
}
