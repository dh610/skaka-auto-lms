package com.ddhhyy.skala_attendance

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.content.pm.verify.domain.DomainVerificationManager
import android.content.pm.verify.domain.DomainVerificationUserState
import androidx.browser.customtabs.CustomTabsIntent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val callbackHost = "att.skala-ai.com"

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
        val state = manager.getDomainVerificationUserState(packageName)
            ?.hostToStateMap
            ?.get(callbackHost)
        return state == DomainVerificationUserState.DOMAIN_STATE_SELECTED ||
            state == DomainVerificationUserState.DOMAIN_STATE_VERIFIED
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
}
