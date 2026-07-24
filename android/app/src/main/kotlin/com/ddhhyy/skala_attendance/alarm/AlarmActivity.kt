package com.ddhhyy.skala_attendance.alarm

import android.app.Activity
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.Space
import android.widget.TextView
import android.widget.Toast
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class AlarmActivity : Activity() {
    private var alarm: AlarmData? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        val occurrenceKey =
            intent.getStringExtra(AlarmContract.extraOccurrenceKey)
                ?: return finish()
        alarm = AlarmStore.find(this, occurrenceKey) ?: return finish()
        setContentView(buildContent(alarm!!))
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (keyCode == KeyEvent.KEYCODE_VOLUME_UP ||
            keyCode == KeyEvent.KEYCODE_VOLUME_DOWN
        ) {
            val current = alarm ?: return true
            if (current.shouldSnoozeFromVolumeButton()) {
                perform(AlarmContract.actionSnooze)
            } else {
                startService(
                    android.content.Intent(this, AlarmRingingService::class.java)
                        .setAction(AlarmContract.actionSilence),
                )
                Toast.makeText(
                    this,
                    "알람음과 진동을 껐습니다.",
                    Toast.LENGTH_SHORT,
                ).show()
            }
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    private fun buildContent(alarm: AlarmData): View {
        val padding = (28 * resources.displayMetrics.density).toInt()
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(padding, padding, padding, padding)
            background = GradientDrawable(
                GradientDrawable.Orientation.TOP_BOTTOM,
                intArrayOf(
                    Color.rgb(8, 16, 31),
                    Color.rgb(15, 29, 51),
                ),
            )

            addView(Space(context), LinearLayout.LayoutParams(1, 0, 1f))
            addView(textView(currentTime(), 64f, Color.WHITE))
            addView(
                textView(
                    "${alarm.actionLabel} 시간입니다",
                    29f,
                    Color.WHITE,
                ).apply {
                    setPadding(0, padding / 2, 0, 0)
                },
            )
            addView(
                textView(
                    "손잡이를 끝까지 밀면 Google 인증 화면으로 이동합니다.",
                    14f,
                    Color.rgb(181, 195, 219),
                ).apply {
                    setPadding(0, padding / 2, 0, padding)
                },
            )

            addView(Space(context), LinearLayout.LayoutParams(1, 0, 1f))

            addView(
                SwipeToAuthenticateView(context).apply {
                    setOnConfirmedListener {
                        perform(AlarmContract.actionOpenAttendance)
                    }
                },
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    (104 * resources.displayMetrics.density).toInt(),
                ),
            )
            addView(
                textView(
                    if (alarm.shouldSnoozeFromVolumeButton()) {
                        "볼륨 버튼 · ${alarm.snoozeMinutes}분 뒤 다시 알림"
                    } else {
                        "볼륨 버튼 · 알람음과 진동 끄기"
                    },
                    13f,
                    Color.rgb(151, 169, 199),
                ).apply {
                    setPadding(0, padding / 2, 0, 0)
                },
            )
        }
    }

    private fun textView(value: String, size: Float, color: Int) =
        TextView(this).apply {
            text = value
            textSize = size
            setTextColor(color)
            gravity = Gravity.CENTER
        }

    private fun currentTime() =
        SimpleDateFormat("a h:mm", Locale.KOREAN).format(Date())

    private fun perform(action: String) {
        val current = alarm ?: return
        AlarmActions.perform(this, action, current.occurrenceKey)
        finishAndRemoveTask()
    }
}
