package com.ddhhyy.skala_attendance.alarm

import android.app.Activity
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.Space
import android.widget.TextView
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
            when (current.volumeButtonAction) {
                "snooze" -> perform(AlarmContract.actionSnooze)
                "dismiss" -> perform(AlarmContract.actionDismiss)
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
            setBackgroundColor(Color.rgb(12, 20, 34))

            addView(Space(context), LinearLayout.LayoutParams(1, 0, 1f))
            addView(textView(currentTime(), 58f, Color.WHITE))
            addView(textView("${alarm.actionLabel} 시간입니다", 28f, Color.WHITE).apply {
                setPadding(0, padding, 0, padding)
            })
            addView(
                button("Google 인증 후 출결 확인") {
                    perform(AlarmContract.actionOpenAttendance)
                },
                matchWidth(),
            )
            if (alarm.canSnooze()) {
                addView(
                    button("${alarm.snoozeMinutes}분 뒤 다시 알림") {
                        perform(AlarmContract.actionSnooze)
                    },
                    matchWidth(),
                )
            }
            addView(
                button("끄기") { perform(AlarmContract.actionDismiss) },
                matchWidth(),
            )
            addView(Space(context), LinearLayout.LayoutParams(1, 0, 1f))
        }
    }

    private fun textView(value: String, size: Float, color: Int) =
        TextView(this).apply {
            text = value
            textSize = size
            setTextColor(color)
            gravity = Gravity.CENTER
        }

    private fun button(label: String, onClick: () -> Unit) =
        Button(this).apply {
            text = label
            textSize = 17f
            setOnClickListener { onClick() }
        }

    private fun matchWidth() = LinearLayout.LayoutParams(
        LinearLayout.LayoutParams.MATCH_PARENT,
        LinearLayout.LayoutParams.WRAP_CONTENT,
    ).apply {
        val margin = (6 * resources.displayMetrics.density).toInt()
        setMargins(0, margin, 0, margin)
    }

    private fun currentTime() =
        SimpleDateFormat("a h:mm", Locale.KOREAN).format(Date())

    private fun perform(action: String) {
        val current = alarm ?: return
        AlarmActions.perform(this, action, current.occurrenceKey)
        finishAndRemoveTask()
    }
}
