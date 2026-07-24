package com.ddhhyy.skala_attendance.alarm

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.View
import kotlin.math.abs

class SwipeToAuthenticateView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : View(context, attrs) {
    private val density = resources.displayMetrics.density
    private val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(28, 43, 66)
    }
    private val progressPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(45, 72, 116)
    }
    private val handlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(102, 130, 255)
    }
    private val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textSize = 16f * resources.configuration.fontScale * density
        textAlign = Paint.Align.CENTER
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
    }
    private val arrowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textSize = 28f * density
        textAlign = Paint.Align.CENTER
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
    }
    private var handleCenterX = 0f
    private var dragging = false
    private var completed = false
    private var onConfirmed: (() -> Unit)? = null

    init {
        isClickable = true
        isFocusable = true
        contentDescription = "밀어서 Google 인증 후 출결 확인"
        minimumHeight = (104f * density).toInt()
    }

    fun setOnConfirmedListener(listener: () -> Unit) {
        onConfirmed = listener
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val desiredHeight = (104f * density).toInt()
        setMeasuredDimension(
            MeasureSpec.getSize(widthMeasureSpec),
            resolveSize(desiredHeight, heightMeasureSpec),
        )
    }

    override fun onSizeChanged(width: Int, height: Int, oldWidth: Int, oldHeight: Int) {
        handleCenterX = startX()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val padding = 8f * density
        val track = RectF(
            padding,
            padding,
            width - padding,
            height - padding,
        )
        val corner = track.height() / 2f
        canvas.drawRoundRect(track, corner, corner, trackPaint)

        val progress = RectF(track.left, track.top, handleCenterX, track.bottom)
        canvas.drawRoundRect(progress, corner, corner, progressPaint)

        val baseline = height / 2f - (labelPaint.ascent() + labelPaint.descent()) / 2f
        canvas.drawText(
            "밀어서 출결 확인",
            width / 2f + 20f * density,
            baseline,
            labelPaint,
        )

        canvas.drawCircle(
            handleCenterX,
            height / 2f,
            handleRadius(),
            handlePaint,
        )
        val arrowBaseline =
            height / 2f - (arrowPaint.ascent() + arrowPaint.descent()) / 2f
        canvas.drawText("›", handleCenterX, arrowBaseline, arrowPaint)
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (completed) return true
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                if (abs(event.x - handleCenterX) > handleRadius() * 1.5f) {
                    return false
                }
                dragging = true
                parent?.requestDisallowInterceptTouchEvent(true)
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                if (!dragging) return false
                handleCenterX = event.x.coerceIn(startX(), endX())
                invalidate()
                return true
            }
            MotionEvent.ACTION_UP -> {
                if (!dragging) return false
                dragging = false
                parent?.requestDisallowInterceptTouchEvent(false)
                if (progress() >= completionThreshold) {
                    confirm()
                } else {
                    animateBack()
                }
                return true
            }
            MotionEvent.ACTION_CANCEL -> {
                dragging = false
                parent?.requestDisallowInterceptTouchEvent(false)
                animateBack()
                return true
            }
        }
        return super.onTouchEvent(event)
    }

    override fun performClick(): Boolean {
        super.performClick()
        confirm()
        return true
    }

    private fun confirm() {
        if (completed) return
        completed = true
        handleCenterX = endX()
        invalidate()
        onConfirmed?.invoke()
    }

    private fun animateBack() {
        ValueAnimator.ofFloat(handleCenterX, startX()).apply {
            duration = 180
            addUpdateListener {
                handleCenterX = it.animatedValue as Float
                invalidate()
            }
            start()
        }
    }

    private fun progress(): Float =
        ((handleCenterX - startX()) / (endX() - startX())).coerceIn(0f, 1f)

    private fun handleRadius() = height / 2f - 14f * density
    private fun startX() = 8f * density + handleRadius()
    private fun endX() = width - 8f * density - handleRadius()

    companion object {
        private const val completionThreshold = 0.78f
    }
}
