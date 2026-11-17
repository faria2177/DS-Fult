package dev.doclens.doclens

import android.graphics.PointF
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Removes a cast shadow from the edge of a captured document.
 *
 * Light from one side makes a card or page cast a dark band on the surface
 * along its opposite edges. Edge detectors often take the shadow's outer
 * border as the document's edge, so the crop keeps a strip of shadow and
 * table. For each side this looks just inside the outline: if a band of
 * "surface, only darker" is followed by the much brighter document, the side
 * is moved inward onto the document's real edge.
 *
 * Sides only ever move inward, by at most ~5% of the document's size, and
 * only when most of the side shows the same shadow. A document darker than
 * its surface is left alone, and so is a printed border (its colour is not
 * the surface's colour).
 */
internal object ShadowEdgeTrim {
    private const val SAMPLES = 28
    private const val MIN_VOTE = 0.6

    /** Pixel-space quad in, pixel-space quad out (unchanged if no shadow). */
    fun trimQuad(quad: Quad, width: Int, height: Int, pixelAt: (Int, Int) -> Int): Quad {
        val corners = doubleArrayOf(
            quad.topLeft.x.toDouble(), quad.topLeft.y.toDouble(),
            quad.topRight.x.toDouble(), quad.topRight.y.toDouble(),
            quad.bottomRight.x.toDouble(), quad.bottomRight.y.toDouble(),
            quad.bottomLeft.x.toDouble(), quad.bottomLeft.y.toDouble(),
        )
        val out = trim(corners, width, height, pixelAt)
        if (out === corners) return quad
        return Quad(
            PointF(out[0].toFloat(), out[1].toFloat()),
            PointF(out[2].toFloat(), out[3].toFloat()),
            PointF(out[4].toFloat(), out[5].toFloat()),
            PointF(out[6].toFloat(), out[7].toFloat()),
        )
    }

    /**
     * [corners]: top-left, top-right, bottom-right, bottom-left as x,y pairs
     * in pixels. Returns the same array instance when nothing is trimmed.
     */
    fun trim(corners: DoubleArray, width: Int, height: Int,
             pixelAt: (Int, Int) -> Int): DoubleArray {
        if (corners.size != 8 || width < 32 || height < 32) return corners
        val cx = (corners[0] + corners[2] + corners[4] + corners[6]) / 4
        val cy = (corners[1] + corners[3] + corners[5] + corners[7]) / 4
        fun side(i: Int): Double {
            val j = (i + 1) % 4
            return hypot(corners[2 * j] - corners[2 * i], corners[2 * j + 1] - corners[2 * i + 1])
        }
        val docMin = min((side(0) + side(2)) / 2, (side(1) + side(3)) / 2)
        if (docMin < 40) return corners
        val maxShift = (0.05 * docMin).roundToInt().coerceIn(4, 90)

        val lines = Array(4) { DoubleArray(4) }
        var moved = false
        for (i in 0 until 4) {
            val j = (i + 1) % 4
            var ax = corners[2 * i]; var ay = corners[2 * i + 1]
            var bx = corners[2 * j]; var by = corners[2 * j + 1]
            val length = hypot(bx - ax, by - ay)
            val ux = (bx - ax) / length; val uy = (by - ay) / length
            var nx = -uy; var ny = ux
            val mx = (ax + bx) / 2; val my = (ay + by) / 2
            if ((cx - mx) * nx + (cy - my) * ny < 0) { nx = -nx; ny = -ny }
            val shift = sideShadow(ax, ay, bx, by, ux, uy, nx, ny, maxShift,
                width, height, pixelAt)
            if (shift != null) {
                ax += nx * shift.first; ay += ny * shift.first
                bx += nx * shift.second; by += ny * shift.second
                moved = true
            }
            lines[i] = doubleArrayOf(ax, ay, bx, by)
        }
        if (!moved) return corners
        val result = DoubleArray(8)
        for (i in 0 until 4) {
            val p = intersect(lines[(i + 3) % 4], lines[i]) ?: return corners
            result[2 * i] = p.first.coerceIn(0.0, width.toDouble())
            result[2 * i + 1] = p.second.coerceIn(0.0, height.toDouble())
        }
        // A trim may never eat into the document noticeably.
        if (area(result) < 0.80 * area(corners)) return corners
        return result
    }

    /** Inward shift at the a-end and b-end, or null when there is no shadow. */
    private fun sideShadow(
        ax: Double, ay: Double, bx: Double, by: Double,
        ux: Double, uy: Double, nx: Double, ny: Double, maxShift: Int,
        width: Int, height: Int, pixelAt: (Int, Int) -> Int,
    ): Pair<Double, Double>? {
        val lo = -8
        val hi = maxShift + 12
        val count = hi - lo + 1
        val lum = Array(SAMPLES) { DoubleArray(count) }
        val red = Array(SAMPLES) { DoubleArray(count) }
        val green = Array(SAMPLES) { DoubleArray(count) }
        val blue = Array(SAMPLES) { DoubleArray(count) }
        val valid = BooleanArray(SAMPLES) { true }
        for (s in 0 until SAMPLES) {
            val t = 0.12 + 0.76 * s / (SAMPLES - 1)
            val px = ax + (bx - ax) * t; val py = ay + (by - ay) * t
            for (k in lo..hi) {
                var r = 0.0; var g = 0.0; var b = 0.0; var n = 0
                for (along in intArrayOf(-2, 0, 2)) {
                    val x = (px + nx * k + ux * along).roundToInt()
                    val y = (py + ny * k + uy * along).roundToInt()
                    if (x < 0 || y < 0 || x >= width || y >= height) continue
                    val c = pixelAt(x, y)
                    r += (c shr 16) and 0xFF; g += (c shr 8) and 0xFF; b += c and 0xFF; n++
                }
                if (n == 0) { valid[s] = false; break }
                val idx = k - lo
                red[s][idx] = r / n; green[s][idx] = g / n; blue[s][idx] = b / n
                lum[s][idx] = (0.299 * red[s][idx] + 0.587 * green[s][idx] + 0.114 * blue[s][idx])
            }
        }
        fun mean(a: DoubleArray, from: Int, to: Int): Double {
            var sum = 0.0
            for (k in from..to) sum += a[k - lo]
            return sum / (to - from + 1)
        }
        // The document's own brightness just inside the edge (median over the
        // side so text and logos do not matter).
        val interior = (0 until SAMPLES).filter { valid[it] }
            .map { mean(lum[it], maxShift + 6, maxShift + 12) }.sorted()
        if (interior.size < SAMPLES / 2) return null
        val paper = interior[interior.size / 2]

        val shifts = ArrayList<Pair<Double, Double>>() // (t, shift)
        var usable = 0
        for (s in 0 until SAMPLES) {
            if (!valid[s]) continue
            usable++
            val outsideLum = mean(lum[s], -8, -3)
            // Only a document brighter than its surface casts a visible band.
            if (paper < outsideLum + 25) continue
            var edge = -1
            for (k in 1..maxShift + 2) {
                if (lum[s][k - lo] >= 0.85 * paper) { edge = k; break }
            }
            if (edge < 3) continue
            val bandLum = mean(lum[s], 0, edge - 2)
            if (bandLum > 0.70 * paper) continue
            // Shadow = the surface, darker: never brighter than it…
            if (bandLum > outsideLum * 1.15 + 8) continue
            // …and the same hue (skip the hue test on near-black surfaces).
            if (outsideLum >= 35) {
                val oR = mean(red[s], -8, -3); val oG = mean(green[s], -8, -3)
                val oB = mean(blue[s], -8, -3)
                val bR = mean(red[s], 0, edge - 2); val bG = mean(green[s], 0, edge - 2)
                val bB = mean(blue[s], 0, edge - 2)
                val oSum = oR + oG + oB + 1; val bSum = bR + bG + bB + 1
                if (abs(oR / oSum - bR / bSum) > 0.06 || abs(oG / oSum - bG / bSum) > 0.06) {
                    continue
                }
            }
            val t = 0.12 + 0.76 * s / (SAMPLES - 1)
            shifts.add(t to edge - 0.5)
        }
        if (usable == 0 || shifts.size < MIN_VOTE * usable) return null
        // Straight line through the shadow widths: a tilted shadow is wider
        // at one end.
        val n = shifts.size.toDouble()
        val mt = shifts.sumOf { it.first } / n
        val ms = shifts.sumOf { it.second } / n
        var cov = 0.0; var vt = 0.0
        for ((t, e) in shifts) { cov += (t - mt) * (e - ms); vt += (t - mt) * (t - mt) }
        val slope = if (vt > 1e-9) cov / vt else 0.0
        val atA = (ms - slope * mt).coerceIn(0.0, maxShift + 2.0)
        val atB = (ms + slope * (1 - mt)).coerceIn(0.0, maxShift + 2.0)
        if (max(atA, atB) < 2.0) return null
        return atA to atB
    }

    private fun intersect(l1: DoubleArray, l2: DoubleArray): Pair<Double, Double>? {
        val rx = l1[2] - l1[0]; val ry = l1[3] - l1[1]
        val sx = l2[2] - l2[0]; val sy = l2[3] - l2[1]
        val den = rx * sy - ry * sx
        if (abs(den) < 1e-9) return null
        val t = ((l2[0] - l1[0]) * sy - (l2[1] - l1[1]) * sx) / den
        return (l1[0] + t * rx) to (l1[1] + t * ry)
    }

    private fun area(c: DoubleArray): Double {
        var s = 0.0
        for (i in 0 until 4) {
            val j = (i + 1) % 4
            s += c[2 * i] * c[2 * j + 1] - c[2 * j] * c[2 * i + 1]
        }
        return abs(s) / 2
    }
}
