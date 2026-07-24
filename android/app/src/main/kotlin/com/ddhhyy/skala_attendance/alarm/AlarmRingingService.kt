package com.ddhhyy.skala_attendance.alarm

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat
import com.ddhhyy.skala_attendance.R

class AlarmRingingService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val occurrenceKey =
            intent?.getStringExtra(AlarmContract.extraOccurrenceKey)
                ?: return START_NOT_STICKY
        val alarm = AlarmStore.find(this, occurrenceKey) ?: return START_NOT_STICKY
        acquireWakeLock()
        createNotificationChannel()
        startForeground(
            AlarmContract.notificationId,
            buildNotification(alarm),
        )
        startSound(alarm)
        startVibration(alarm)
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        mediaPlayer?.runCatching {
            stop()
            release()
        }
        mediaPlayer = null
        vibrator?.cancel()
        vibrator = null
        wakeLock?.takeIf { it.isHeld }?.release()
        wakeLock = null
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            channelId,
            "출결 알람",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "설정한 시간에 전체 화면 출결 알람을 표시합니다."
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            setSound(null, null)
            enableVibration(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(alarm: AlarmData): Notification {
        val fullScreenIntent = PendingIntent.getActivity(
            this,
            alarm.occurrenceKey.hashCode(),
            Intent(this, AlarmActivity::class.java)
                .putExtra(AlarmContract.extraOccurrenceKey, alarm.occurrenceKey)
                .setData(AlarmScheduler.alarmUri(alarm.occurrenceKey, "ring")),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("${alarm.actionLabel} 시간입니다")
            .setContentText("알람을 끄거나 출결 확인을 진행하세요.")
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(fullScreenIntent)
            .setFullScreenIntent(fullScreenIntent, true)
            .addAction(
                0,
                "출결 확인",
                actionPendingIntent(alarm, AlarmContract.actionOpenAttendance, 1),
            )
        if (alarm.canSnooze()) {
            builder.addAction(
                0,
                "${alarm.snoozeMinutes}분 뒤 다시 알림",
                actionPendingIntent(alarm, AlarmContract.actionSnooze, 2),
            )
        }
        builder.addAction(
            0,
            "끄기",
            actionPendingIntent(alarm, AlarmContract.actionDismiss, 3),
        )
        return builder.build()
    }

    private fun actionPendingIntent(
        alarm: AlarmData,
        action: String,
        offset: Int,
    ): PendingIntent = PendingIntent.getBroadcast(
        this,
        alarm.occurrenceKey.hashCode() + offset,
        Intent(this, AlarmActionReceiver::class.java)
            .setAction(action)
            .putExtra(AlarmContract.extraOccurrenceKey, alarm.occurrenceKey)
            .setData(AlarmScheduler.alarmUri(alarm.occurrenceKey, action)),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun startSound(alarm: AlarmData) {
        val targetVolume = alarm.volumePercent / 100f
        if (targetVolume <= 0f) return
        val sound = alarm.soundUri?.let(android.net.Uri::parse)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
        mediaPlayer = MediaPlayer().apply {
            setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            setDataSource(this@AlarmRingingService, sound)
            isLooping = true
            val initialVolume = if (alarm.gradualVolumeEnabled) 0f else targetVolume
            setVolume(initialVolume, initialVolume)
            prepare()
            start()
        }
        if (alarm.gradualVolumeEnabled) {
            for (step in 1..30) {
                handler.postDelayed({
                    val volume = targetVolume * step / 30f
                    mediaPlayer?.setVolume(volume, volume)
                }, step * 1_000L)
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun startVibration(alarm: AlarmData) {
        if (!alarm.vibrationEnabled) return
        vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService(VibratorManager::class.java).defaultVibrator
        } else {
            getSystemService(VIBRATOR_SERVICE) as Vibrator
        }
        val pattern = longArrayOf(0, 700, 300, 700, 800)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
        } else {
            vibrator?.vibrate(pattern, 0)
        }
    }

    private fun acquireWakeLock() {
        val powerManager = getSystemService(PowerManager::class.java)
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "$packageName:attendance-alarm",
        ).apply { acquire(10 * 60_000L) }
    }

    companion object {
        private const val channelId = "attendance_full_screen_alarm"
    }
}
