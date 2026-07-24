package com.ddhhyy.skala_attendance.alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class AlarmRestoreReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        AlarmScheduler.restore(context)
    }
}
