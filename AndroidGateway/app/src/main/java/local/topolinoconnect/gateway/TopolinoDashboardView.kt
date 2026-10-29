package local.topolinoconnect.gateway

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.view.View
import org.json.JSONObject
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

/** Vector-rendered electric dashboard, styled after the supplied twin-dial cluster. */
class TopolinoDashboardView(context: Context) : View(context) {
    private data class PaintKey(val color: Int, val strokeWidth: Float, val style: Paint.Style)
    private val paintCache = HashMap<PaintKey, Paint>()
    private val panelOuter = RectF(20f, 25f, 1180f, 625f)
    private val panelEdge = RectF(32f, 32f, 1168f, 612f)
    private val panelInner = RectF(43f, 43f, 1157f, 601f)
    private val panelInset = RectF(52f, 51f, 1148f, 592f)
    private val arcRect = RectF()
    private val powerNeedle = Path()
    private val batteryNeedle = Path()
    private val normalTypeface = android.graphics.Typeface.create("sans-serif", android.graphics.Typeface.NORMAL)
    private val boldTypeface = android.graphics.Typeface.create("sans-serif", android.graphics.Typeface.BOLD)
    var fillsViewport: Boolean = false
        set(value) { field = value; invalidate() }
    private var gear = "—"
    private var batteryPercent: Float? = null
    private var rangeKm: Float? = null
    private var odometerKm: Float? = null
    private var batteryPowerKw: Float? = null
    private var rangeEstimated = false

    init { setBackgroundColor(0xFF090F20.toInt()) }

    fun refreshFromRuntime() {
        val can = GatewayRuntime.espCan
        gear = can?.optString("gear")?.takeIf { !it.isNullOrBlank() && it != "null" && it != "NA" } ?: "—"
        batteryPercent = can?.number("batteryPercent")?.takeIf { it in 0f..100f }
        val liveRange = can?.number("rangeKm")?.takeIf { it > 0f }
        val useLiveRange = GatewayRuntime.hasFreshTelemetry() && can?.optBoolean("canLive", true) == true && liveRange != null
        val classicRange = ClassicRangeEstimateStore.estimate(context)
        rangeKm = if (useLiveRange) liveRange else classicRange?.rangeKm?.toFloat() ?: liveRange
        rangeEstimated = !useLiveRange && classicRange != null
        odometerKm = can?.number("odometerKm")?.takeIf { it >= 0f }
        batteryPowerKw = can?.number("batteryPowerKw")?.takeIf { can.optBoolean("canLive", true) }
        invalidate()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = MeasureSpec.getSize(widthMeasureSpec)
        val desiredHeight = (width / (1200f / 650f)).toInt()
        setMeasuredDimension(resolveSize(width, widthMeasureSpec), resolveSize(desiredHeight, heightMeasureSpec))
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val scaleX = if (fillsViewport) width / 1200f else min(width / 1200f, height / 650f)
        val scaleY = if (fillsViewport) height / 650f else scaleX
        val save = canvas.save()
        canvas.translate((width - 1200f * scaleX) / 2f, (height - 650f * scaleY) / 2f)
        canvas.scale(scaleX, scaleY)

        // Wide, dark instrument panel with a slim metallic edge.
        canvas.drawRoundRect(panelOuter, 120f, 120f, p(0xFF000000.toInt()))
        canvas.drawRoundRect(panelEdge, 112f, 112f, p(0xFF111619.toInt(), 3f, Paint.Style.STROKE))
        canvas.drawRoundRect(panelInner, 102f, 102f, p(0xFF05080A.toInt()))
        canvas.drawRoundRect(panelInset, 96f, 96f, p(0xFF070A0D.toInt(), 2f, Paint.Style.STROKE).apply { alpha = 190 })

        text(canvas, "TOPOLINO", 600f, 112f, 24f, 0xFFB8C5CA.toInt(), Paint.Align.CENTER, bold = true, spacing = 2f)
        drawPowerDial(canvas)
        drawBatteryDial(canvas)
        drawCenterDisplay(canvas)
        drawBottomInformation(canvas)
        drawPowerFlow(canvas)
        drawStatusIndicators(canvas)

        canvas.restoreToCount(save)
    }

    private fun drawPowerDial(canvas: Canvas) {
        val cx = 300f; val cy = 326f; val radius = 220f
        canvas.drawCircle(cx, cy, radius - 16f, p(0xFF0A1015.toInt()))
        canvas.drawCircle(cx, cy, radius - 17f, p(0xFF27333A.toInt(), 2f, Paint.Style.STROKE))
        drawArc(canvas, cx, cy, radius, 135f, 270f, 0xFF252D32.toInt(), 8f)
        drawArc(canvas, cx, cy, radius, 135f, 270f, 0xFFD7E2E5.toInt(), 3f, inset = 3f)
        val power = batteryPowerKw?.coerceIn(-15f, 15f)
        power?.let {
            val sweep = ((it + 15f) / 30f) * 270f
            drawArc(canvas, cx, cy, radius, 135f, sweep, if (it < 0f) 0xFF6EA8FF.toInt() else 0xFF24C8B8.toInt(), 8f)
        }
        for (value in -15..15 step 5) {
            val angle = 135f + (value + 15f) / 30f * 270f
            val major = value % 10 == 0
            tick(canvas, cx, cy, radius - 8f, if (major) 27f else 14f, angle,
                if (major) 0xFFE3EAEC.toInt() else 0xFF849196.toInt(), if (major) 3f else 2f)
            if (major) {
                val point = polar(cx, cy, radius - 58f, angle)
                text(canvas, if (value > 0) "+$value" else value.toString(), point.first, point.second + 8f, 25f, 0xFFD8E0E3.toInt(), Paint.Align.CENTER)
            }
        }
        text(canvas, "kW", cx, cy + 91f, 19f, 0xFF8E9A9E.toInt(), Paint.Align.CENTER)
        power?.let {
            val angle = 135f + (it + 15f) / 30f * 270f
            val tip = polar(cx, cy, radius - 25f, angle)
            val tail = polar(cx, cy, 30f, angle + 180f)
            val needle = powerNeedle.apply { reset(); moveTo(tail.first, tail.second); lineTo(tip.first, tip.second) }
            canvas.drawPath(needle, p(0xFFF1F4F5.toInt(), 5f, Paint.Style.STROKE).apply { strokeCap = Paint.Cap.ROUND })
            canvas.drawCircle(cx, cy, 10f, p(0xFFDFE5E7.toInt()))
            canvas.drawCircle(cx, cy, 4f, p(0xFF333A3E.toInt()))
        }
    }

    private fun drawBatteryDial(canvas: Canvas) {
        val cx = 900f; val cy = 326f; val radius = 220f
        canvas.drawCircle(cx, cy, radius - 16f, p(0xFF0A1015.toInt()))
        canvas.drawCircle(cx, cy, radius - 17f, p(0xFF27333A.toInt(), 2f, Paint.Style.STROKE))
        drawArc(canvas, cx, cy, radius, 135f, 270f, 0xFF252D32.toInt(), 8f)
        drawArc(canvas, cx, cy, radius, 135f, 270f, 0xFFD7E2E5.toInt(), 3f, inset = 3f)
        batteryPercent?.let { drawArc(canvas, cx, cy, radius, 135f, (it.coerceIn(0f, 100f) / 100f) * 270f, 0xFF36D8C4.toInt(), 8f) }
        for (value in 0..100 step 5) {
            val angle = 135f + value / 100f * 270f
            val major = value % 25 == 0
            tick(canvas, cx, cy, radius - 8f, if (major) 27f else 14f, angle,
                if (major) 0xFFE3EAEC.toInt() else 0xFF849196.toInt(), if (major) 3f else 2f)
            if (major) {
                val point = polar(cx, cy, radius - 58f, angle)
                text(canvas, value.toString(), point.first, point.second + 8f, 25f, 0xFFD8E0E3.toInt(), Paint.Align.CENTER)
            }
        }
        text(canvas, "BATARYA", cx, cy + 93f, 18f, 0xFF89969A.toInt(), Paint.Align.CENTER, spacing = 1f)
        val level = batteryPercent
        if (level != null) {
            val angle = 135f + level / 100f * 270f
            val tip = polar(cx, cy, radius - 28f, angle)
            val tail = polar(cx, cy, 28f, angle + 180f)
            val needle = batteryNeedle.apply { reset(); moveTo(tail.first, tail.second); lineTo(tip.first, tip.second) }
            canvas.drawPath(needle, p(0xFFF1F4F5.toInt(), 5f, Paint.Style.STROKE).apply { strokeCap = Paint.Cap.ROUND })
            canvas.drawCircle(cx, cy, 10f, p(0xFFDFE5E7.toInt()))
            canvas.drawCircle(cx, cy, 4f, p(0xFF333A3E.toInt()))
        }
    }

    private fun drawCenterDisplay(canvas: Canvas) {
        text(canvas, gear, 600f, 318f, 82f, 0xFFF3F6F7.toInt(), Paint.Align.CENTER, bold = true)
        text(canvas, "VİTES", 600f, 357f, 18f, 0xFFAEB9BD.toInt(), Paint.Align.CENTER)
        text(canvas, "ANLIK GÜÇ DENGESİ", 600f, 402f, 14f, 0xFF8E9A9E.toInt(), Paint.Align.CENTER, spacing = 1.2f)
    }

    private fun drawBottomInformation(canvas: Canvas) {
        val y = 535f
        text(canvas, odometerKm?.let { "%.0f km".format(it) } ?: "— km", 245f, y, 24f, 0xFFD5DEE0.toInt(), Paint.Align.CENTER)
        text(canvas, "ODO", 245f, y + 24f, 13f, 0xFF819095.toInt(), Paint.Align.CENTER, spacing = 1f)
        text(canvas, batteryPercent?.let { "${it.toInt()}%" } ?: "—%", 600f, y, 25f, 0xFFD5DEE0.toInt(), Paint.Align.CENTER)
        text(canvas, "BATARYA", 600f, y + 24f, 13f, 0xFF819095.toInt(), Paint.Align.CENTER, spacing = 1f)
        text(canvas, rangeKm?.let { "%.0f km".format(it) } ?: "— km", 955f, y, 24f, 0xFFD5DEE0.toInt(), Paint.Align.CENTER)
        text(canvas, if (rangeEstimated) "TAHMİNİ MENZİL" else "MENZİL", 955f, y + 24f, 13f, 0xFF819095.toInt(), Paint.Align.CENTER, spacing = 1f)
        canvas.drawLine(420f, 514f, 420f, 575f, p(0xFF283238.toInt(), 2f, Paint.Style.STROKE))
        canvas.drawLine(780f, 514f, 780f, 575f, p(0xFF283238.toInt(), 2f, Paint.Style.STROKE))
    }

    private fun drawStatusIndicators(canvas: Canvas) {
        val handbrake = GatewayRuntime.espCan?.optBoolean("handbrake") == true
        if (handbrake) {
            text(canvas, "P", 105f, 345f, 23f, 0xFFFF5656.toInt(), Paint.Align.CENTER, bold = true)
        }
        val simulation = GatewayRuntime.vehicleSnapshot?.simulation == true
        canvas.drawCircle(600f, 488f, 5f, p(if (simulation) 0xFFFFB74D.toInt() else if (GatewayRuntime.hasFreshTelemetry()) 0xFF43D7C3.toInt() else 0xFF68727A.toInt()))
        text(canvas, if (simulation) "TEST" else if (GatewayRuntime.hasFreshTelemetry()) "CANLI" else "SON VERİ", 617f, 493f, 13f,
            if (simulation) 0xFFFFB74D.toInt() else if (GatewayRuntime.hasFreshTelemetry()) 0xFF70D9C9.toInt() else 0xFF8E9A9E.toInt())
    }

    private fun drawPowerFlow(canvas: Canvas) {
        val left = 535f; val right = 665f; val center = 600f; val y = 589f
        canvas.drawLine(left, y, right, y, p(0xFF283238.toInt(), 5f, Paint.Style.STROKE).apply { strokeCap = Paint.Cap.ROUND })
        canvas.drawLine(center, y - 6f, center, y + 6f, p(0xFF9AA8AC.toInt(), 2f, Paint.Style.STROKE))
        val power = batteryPowerKw
        if (power != null) {
            val end = center + (power.coerceIn(-15f, 15f) / 15f) * 62f
            canvas.drawLine(center, y, end, y, p(if (power < 0f) 0xFF6EA8FF.toInt() else 0xFF36D8C4.toInt(), 7f, Paint.Style.STROKE).apply { strokeCap = Paint.Cap.ROUND })
            text(canvas, "ANLIK GÜÇ DENGESİ  %+.2f kW".format(java.util.Locale.US, power), 600f, 578f, 12f, 0xFFE4EAEC.toInt(), Paint.Align.CENTER, bold = true)
        } else {
            text(canvas, "ANLIK GÜÇ DENGESİ  — kW", 600f, 578f, 12f, 0xFF8E9A9E.toInt(), Paint.Align.CENTER)
        }
        text(canvas, "− GERİ KAZANIM ADAYI", 510f, 608f, 9f, 0xFF9DBEFF.toInt(), Paint.Align.RIGHT)
        text(canvas, "+ ÇEKİŞ / TÜKETİM ADAYI", 690f, 608f, 9f, 0xFF75DDC9.toInt(), Paint.Align.LEFT)
        text(canvas, "İşaret araçta doğrulanmalı · güç = V × A", 600f, 621f, 9f, 0xFF8E9A9E.toInt(), Paint.Align.CENTER)
    }

    private fun drawArc(canvas: Canvas, cx: Float, cy: Float, radius: Float, start: Float, sweep: Float,
                        color: Int, width: Float, inset: Float = 0f) {
        arcRect.set(cx - radius + inset, cy - radius + inset, cx + radius - inset, cy + radius - inset)
        canvas.drawArc(arcRect, start, sweep, false, p(color, width, Paint.Style.STROKE).apply { strokeCap = Paint.Cap.ROUND })
    }

    private fun tick(canvas: Canvas, cx: Float, cy: Float, radius: Float, length: Float, angle: Float, color: Int, width: Float) {
        val outer = polar(cx, cy, radius, angle)
        val inner = polar(cx, cy, radius - length, angle)
        canvas.drawLine(inner.first, inner.second, outer.first, outer.second,
            p(color, width, Paint.Style.STROKE).apply { strokeCap = Paint.Cap.ROUND })
    }

    private fun polar(cx: Float, cy: Float, radius: Float, degrees: Float): Pair<Float, Float> {
        val radians = degrees * Math.PI / 180.0
        return Pair(cx + cos(radians).toFloat() * radius, cy + sin(radians).toFloat() * radius)
    }

    private fun text(canvas: Canvas, value: String, x: Float, y: Float, size: Float, color: Int,
                     align: Paint.Align = Paint.Align.LEFT, bold: Boolean = false, spacing: Float = 0f) {
        val paint = p(color).apply {
            textSize = size
            textAlign = align
            typeface = if (bold) boldTypeface else normalTypeface
            letterSpacing = spacing / size
        }
        canvas.drawText(value, x, y, paint)
    }

    private fun p(color: Int, strokeWidth: Float = 1f, style: Paint.Style = Paint.Style.FILL): Paint {
        val key = PaintKey(color, strokeWidth, style)
        val paint = paintCache.getOrPut(key) { Paint(Paint.ANTI_ALIAS_FLAG) }
        paint.color = color
        paint.strokeWidth = strokeWidth
        paint.style = style
        paint.alpha = 255
        paint.strokeCap = Paint.Cap.BUTT
        return paint
    }

    private fun JSONObject.number(key: String): Float? =
        if (has(key) && !isNull(key)) optDouble(key).toFloat().takeIf { it.isFinite() } else null
}
