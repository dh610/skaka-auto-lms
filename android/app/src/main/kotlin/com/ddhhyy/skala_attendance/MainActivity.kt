package com.ddhhyy.skala_attendance

import android.content.ActivityNotFoundException
import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "skala_attendance/browser")
            .setMethodCallHandler { call, result ->
                if (call.method != "openCustomTab") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val rawUrl = call.argument<String>("url")
                if (rawUrl.isNullOrBlank()) {
                    result.error("INVALID_URL", "URL is required", null)
                    return@setMethodCallHandler
                }
                val uri = Uri.parse(rawUrl)
                val customTab = CustomTabsIntent.Builder()
                    .setShowTitle(true)
                    .build()
                customTab.intent.setPackage("com.android.chrome")
                try {
                    customTab.launchUrl(this, uri)
                    result.success(true)
                } catch (_: ActivityNotFoundException) {
                    customTab.intent.setPackage(null)
                    customTab.launchUrl(this, uri)
                    result.success(false)
                }
            }
    }
}
