package com.docscan.scanner

import org.opencv.core.Mat
import org.opencv.core.Point
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

/**
 * The frame geometry and contrast tuning from the supplied Kotlin scanner.
 * Only the detector-facing operations are retained here: the reference file's
 * Compose Offset tracking routines belong to its Android UI and would require
 * adding the Compose runtime to this standalone Flutter plugin.
 */
object ScannerTuning {
    const val A4_RATIO = 1.41421356237
    const val LETTER_RATIO = 1.29411764706
    const val LEGAL_RATIO = 1.64705882353
    const val ID_CARD_RATIO = 1.5857725
    const val RECEIPT_RATIO = 2.20

    const val MIN_LIVE_AREA_RATIO = 0.035
    const val MAX_LIVE_AREA_RATIO = 0.985
    const val MIN_AVG_EDGE_SUPPORT = 0.15
    const val MIN_BOUNDARY_CONTRAST = 2.5

    fun normalizedLongRatio(q: Array<Point>): Double {
        if (q.size != 4) return 0.0
        val w = (distance(q[0], q[1]) + distance(q[3], q[2])) * 0.5
        val h = (distance(q[0], q[3]) + distance(q[1], q[2])) * 0.5
        return if (w <= 1.0 || h <= 1.0) 0.0 else max(w, h) / min(w, h)
    }

    fun paperRatioScore(ratio: Double): Double {
        if (!ratio.isFinite() || ratio <= 0.0) return 0.0
        fun closeness(target: Double, tolerance: Double): Double =
            (1.0 - abs(ratio - target) / tolerance).coerceIn(0.0, 1.0)
        return maxOf(
            closeness(A4_RATIO, 0.32),
            closeness(LETTER_RATIO, 0.28),
            closeness(LEGAL_RATIO, 0.35),
            closeness(ID_CARD_RATIO, 0.28),
            closeness(RECEIPT_RATIO, 1.20),
        )
    }

    fun boundaryContrast(gray: Mat, q: Array<Point>): Double {
        if (gray.empty() || q.size != 4) return 0.0
        val cx = q.sumOf { it.x } / 4.0
        val cy = q.sumOf { it.y } / 4.0
        val step = (min(gray.width(), gray.height()) * 0.012).coerceIn(3.0, 10.0)
        var total = 0.0
        var count = 0
        for (i in 0..3) {
            val a = q[i]
            val b = q[(i + 1) % 4]
            val mx = (a.x + b.x) * 0.5
            val my = (a.y + b.y) * 0.5
            var vx = cx - mx
            var vy = cy - my
            val len = hypot(vx, vy).coerceAtLeast(1.0)
            vx /= len
            vy /= len
            for (t in doubleArrayOf(0.25, 0.5, 0.75)) {
                val sx = a.x + (b.x - a.x) * t
                val sy = a.y + (b.y - a.y) * t
                val inside = sample(gray, sx + vx * step, sy + vy * step)
                val outside = sample(gray, sx - vx * step, sy - vy * step)
                if (inside != null && outside != null) {
                    total += abs(inside - outside)
                    count++
                }
            }
        }
        return if (count == 0) 0.0 else total / count
    }

    private fun sample(gray: Mat, x: Double, y: Double): Double? {
        val ix = x.toInt()
        val iy = y.toInt()
        if (ix !in 0 until gray.cols() || iy !in 0 until gray.rows()) return null
        return gray.get(iy, ix)?.firstOrNull()
    }

    private fun distance(a: Point, b: Point): Double = hypot(a.x - b.x, a.y - b.y)
}
