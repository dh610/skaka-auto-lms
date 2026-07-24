package com.ddhhyy.skala_attendance

import android.content.ActivityNotFoundException
import android.content.Intent
import android.app.NotificationManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.media.RingtoneManager
import android.content.pm.verify.domain.DomainVerificationManager
import android.content.pm.verify.domain.DomainVerificationUserState
import androidx.browser.customtabs.CustomTabsIntent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import com.ddhhyy.skala_attendance.alarm.AlarmBridge
import com.ddhhyy.skala_attendance.alarm.AlarmContract
import com.ddhhyy.skala_attendance.alarm.AlarmData
import com.ddhhyy.skala_attendance.alarm.AlarmScheduler

class MainActivity : FlutterActivity() {
    private val callbackHost = "att.skala-ai.com"
    private val alarmSoundRequestCode = 7101
    private var pendingAlarmSoundResult: MethodChannel.Result? = null
    private var alarmChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "skala_attendance/browser")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openCustomTab" -> openCustomTab(call.argument("url"), result)
                    "isAppLinkEnabled" -> result.success(isAppLinkEnabled())
                    "openAppLinkSettings" -> openAppLinkSettings(result)
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "skala_attendance/settings")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openNotificationSettings" -> openNotificationSettings(result)
                    "openExactAlarmSettings" -> openExactAlarmSettings(result)
                    else -> result.notImplemented()
                }
            }
        alarmChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "skala_attendance/alarm")
        alarmChannel?.setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickAlarmSound" -> pickAlarmSound(call.argument("uri"), result)
                    "syncAlarms" -> syncAlarms(call.arguments, result)
                    "takeLaunchPayload" -> result.success(AlarmBridge.takePayload())
                    "canUseFullScreenIntent" -> result.success(canUseFullScreenIntent())
                    "openFullScreenIntentSettings" ->
                        openFullScreenIntentSettings(result)
                    else -> result.notImplemented()
                }
            }
        handleAlarmIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleAlarmIntent(intent)
    }

    private fun syncAlarms(arguments: Any?, result: MethodChannel.Result) {
        val alarms = (arguments as? List<*>)
            ?.mapNotNull { AlarmData.fromMap(it as? Map<*, *> ?: return@mapNotNull null) }
            ?: emptyList()
        runCatching { AlarmScheduler.sync(this, alarms) }
            .onSuccess { result.success(null) }
            .onFailure {
                result.error("ALARM_SYNC_FAILED", it.message, null)
            }
    }

    private fun handleAlarmIntent(intent: Intent?) {
        val payload = intent?.getStringExtra(AlarmContract.extraAttendancePayload) ?: return
        AlarmBridge.pendingAttendancePayload = payload
        alarmChannel?.invokeMethod("alarmAction", payload)
        intent.removeExtra(AlarmContract.extraAttendancePayload)
    }

    private fun canUseFullScreenIntent(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return true
        return getSystemService(NotificationManager::class.java).canUseFullScreenIntent()
    }

    private fun openFullScreenIntentSettings(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            result.success(null)
            return
        }
        val intent = Intent(
            Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
            Uri.parse("package:$packageName"),
        )
        openSettingsWithAppDetailsFallback(intent, result)
    }

    @Suppress("DEPRECATION")
    private fun pickAlarmSound(currentUri: String?, result: MethodChannel.Result) {
        if (pendingAlarmSoundResult != null) {
            result.error("ALREADY_PICKING", "Alarm sound picker is already open", null)
            return
        }
        pendingAlarmSoundResult = result
        val selected = currentUri?.let(Uri::parse)
            ?: Settings.System.DEFAULT_ALARM_ALERT_URI
        val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER)
            .putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, RingtoneManager.TYPE_ALARM)
            .putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
            .putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
            .putExtra(RingtoneManager.EXTRA_RINGTONE_EXISTING_URI, selected)
        try {
            startActivityForResult(intent, alarmSoundRequestCode)
        } catch (error: ActivityNotFoundException) {
            pendingAlarmSoundResult = null
            result.error("PICKER_UNAVAILABLE", error.message, null)
        }
    }

    @Deprecated("Deprecated in Android")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != alarmSoundRequestCode) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = pendingAlarmSoundResult ?: return
        pendingAlarmSoundResult = null
        if (resultCode != RESULT_OK) {
            result.success(null)
            return
        }
        val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            data?.getParcelableExtra(
                RingtoneManager.EXTRA_RINGTONE_PICKED_URI,
                Uri::class.java,
            )
        } else {
            @Suppress("DEPRECATION")
            data?.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
        }
        val normalized = uri ?: Settings.System.DEFAULT_ALARM_ALERT_URI
        val label = runCatching {
            RingtoneManager.getRingtone(this, normalized)?.getTitle(this)
        }.getOrNull().orEmpty().ifBlank { "시스템 기본 알람음" }
        result.success(mapOf("uri" to normalized.toString(), "label" to label))
    }

    private fun openCustomTab(rawUrl: String?, result: MethodChannel.Result) {
        if (rawUrl.isNullOrBlank()) {
            result.error("INVALID_URL", "URL is required", null)
            return
        }
        val customTab = CustomTabsIntent.Builder()
            .setShowTitle(true)
            .build()
        customTab.intent.setPackage("com.android.chrome")
        try {
            customTab.launchUrl(this, Uri.parse(rawUrl))
            result.success(true)
        } catch (_: ActivityNotFoundException) {
            customTab.intent.setPackage(null)
            customTab.launchUrl(this, Uri.parse(rawUrl))
            result.success(false)
        }
    }

    private fun isAppLinkEnabled(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        val manager = getSystemService(DomainVerificationManager::class.java)
        val userState = manager.getDomainVerificationUserState(packageName) ?: return false
        if (!userState.isLinkHandlingAllowed) return false
        val hostState = userState.hostToStateMap[callbackHost]
        return hostState == DomainVerificationUserState.DOMAIN_STATE_SELECTED ||
            hostState == DomainVerificationUserState.DOMAIN_STATE_VERIFIED
    }

    private fun openAppLinkSettings(result: MethodChannel.Result) {
        val packageUri = Uri.parse("package:$packageName")
        val appLinkIntent = Intent(Settings.ACTION_APP_OPEN_BY_DEFAULT_SETTINGS, packageUri)
        try {
            startActivity(appLinkIntent)
            result.success(null)
        } catch (_: ActivityNotFoundException) {
            startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, packageUri))
            result.success(null)
        }
    }

    private fun openNotificationSettings(result: MethodChannel.Result) {
        val notificationIntent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        openSettingsWithAppDetailsFallback(notificationIntent, result)
    }

    private fun openExactAlarmSettings(result: MethodChannel.Result) {
        val packageUri = Uri.parse("package:$packageName")
        val exactAlarmIntent = Intent(
            Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
            packageUri,
        )
        openSettingsWithAppDetailsFallback(exactAlarmIntent, result)
    }

    private fun openSettingsWithAppDetailsFallback(
        intent: Intent,
        result: MethodChannel.Result,
    ) {
        try {
            startActivity(intent)
        } catch (_: ActivityNotFoundException) {
            startActivity(
                Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:$packageName"),
                ),
            )
        }
        result.success(null)
    }
}
