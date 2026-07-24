package com.ddhhyy.skala_attendance.alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val occurrenceKey = intent.getStringExtra(AlarmContract.extraOccurrenceKey) ?: return
        if (AlarmStore.find(context, occurrenceKey) == null) return
        ContextCompat.startForegroundService(
            context,
            Intent(context, AlarmRingingService::class.java)
                .putExtra(AlarmContract.extraOccurrenceKey, occurrenceKey),
        )
    }
}
