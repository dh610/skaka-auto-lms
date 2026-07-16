package com.ddhhyy.skala_attendance

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "skala_attendance/browser")
            .setMethodCallHandler { call, result ->
                if (call.method != "openChrome") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val rawUrl = call.argument<String>("url")
                if (rawUrl.isNullOrBlank()) {
                    result.error("INVALID_URL", "URL is required", null)
                    return@setMethodCallHandler
                }
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(rawUrl)).apply {
                    addCategory(Intent.CATEGORY_BROWSABLE)
                    setPackage("com.android.chrome")
                }
                try {
                    startActivity(intent)
                    result.success(true)
                } catch (_: ActivityNotFoundException) {
                    intent.setPackage(null)
                    startActivity(intent)
                    result.success(false)
                }
            }
    }
}
