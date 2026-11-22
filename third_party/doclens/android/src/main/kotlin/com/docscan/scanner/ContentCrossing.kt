package com.docscan.scanner

import org.opencv.core.Point
import kotlin.math.abs
import kotlin.math.hypot

/**
 * Where a candidate outline lies relative to the printed writing of the
 * frame. Pure geometry over a row-major mask (non-zero = writing) so it is
 * unit-tested on the JVM.
 *
 * A page border runs through its blank margin. A table, a text block, or
 * Hough lines that mixed several sheets run through the writing or hug it
 * (386769.mp4, 386799.mp4).
 */
object ContentCrossing {
    /** Black-hat contrast (grey levels) that counts as printing. */
    const val INK_CONTRAST = 28.0
    /** Brightest grey nearby must reach this for the mark to lie on paper. */
    const val PAPER_LUMA = 140.0
    /** Least saturation nearby must stay below this (neutral paper). */
    const val PAPER_SATURATION = 60.0
    /** A side with writing on both of its sides this often runs through print. */
    const val MAX_SIDE_FRACTION = 0.30
    /** A side with writing against its inner margin this often is not a page edge. */
    const val MAX_INSIDE_FRACTION = 0.30

    /** Live frames are ~384 px; stills are larger. Pixel offsets scale with it. */
    fun scale(width: Int, height: Int): Double =
        (maxOf(width, height) / 384.0).coerceAtLeast(1.0)

    /**
     * True for a table, a text block or lines drawn through the writing:
     * a side runs through the print, or three sides have no blank margin.
     */
    fun isInnerContentBox(crossing: Double, inside: DoubleArray): Boolean =
        crossing > MAX_SIDE_FRACTION ||
            inside.count { it >= MAX_INSIDE_FRACTION } >= 3 ||
            inside.count { it >= CLOSE_INSIDE_FRACTION } >= 2

    /** Two sides this crowded by writing are never both page edges. */
    const val CLOSE_INSIDE_FRACTION = 0.45

    /** Worst side: fraction of it with writing just inside AND just outside. */
    fun maxSideFraction(corners: Array<Point>, mask: ByteArray?, width: Int,
                        height: Int): Double {
        if (mask == null || corners.size != 4 || mask.size < width * height) return 0.0
        val k = scale(width, height)
        var worst = 0.0
        for (i in 0 until 4) {
            val both = sideHits(corners, i, mask, width, height, 1.0 * k, 4.0 * k,
                .08, .92, bothSides = true)
            worst = maxOf(worst, both)
        }
        return worst
    }

    /**
     * Per side: fraction whose inner margin holds writing. The margin is
     * measured relative to the outline's own size (1.5–4 %), so a small
     * receipt and a full page are judged alike.
     */
    fun insideFractions(corners: Array<Point>, mask: ByteArray?, width: Int,
                        height: Int): DoubleArray {
        val out = DoubleArray(4)
        if (mask == null || corners.size != 4 || mask.size < width * height) return out
        val size = (hypot(corners[1].x - corners[0].x, corners[1].y - corners[0].y) +
            hypot(corners[2].x - corners[1].x, corners[2].y - corners[1].y) +
            hypot(corners[3].x - corners[2].x, corners[3].y - corners[2].y) +
            hypot(corners[0].x - corners[3].x, corners[0].y - corners[3].y)) / 4
        val near = maxOf(1.5, size * .015)
        val far = maxOf(near + 2, size * .04)
        for (i in 0 until 4) {
            out[i] = sideHits(corners, i, mask, width, height, near, far,
                .10, .90, bothSides = false)
        }
        return out
    }

    private fun sideHits(corners: Array<Point>, side: Int, mask: ByteArray,
                         width: Int, height: Int, near: Double, far: Double,
                         from: Double, to: Double, bothSides: Boolean): Double {
        val a = corners[side]
        val b = corners[(side + 1) % 4]
        val cx = corners.sumOf { it.x } / 4
        val cy = corners.sumOf { it.y } / 4
        val dx = b.x - a.x
        val dy = b.y - a.y
        val len = hypot(dx, dy).coerceAtLeast(1.0)
        var nx = -dy / len
        var ny = dx / len
        if ((cx - (a.x + b.x) / 2) * nx + (cy - (a.y + b.y) / 2) * ny < 0) {
            nx = -nx; ny = -ny
        }
        val samples = 48
        var counted = 0
        var hits = 0
        for (k in 0..samples) {
            val t = from + (to - from) * k / samples
            val px = a.x + dx * t
            val py = a.y + dy * t
            val inner = probe(mask, width, height, px, py, nx, ny, near, far)
            if (inner == null) continue
            if (bothSides) {
                val outer = probe(mask, width, height, px, py, -nx, -ny, near, far)
                    ?: continue
                counted++
                if (inner && outer) hits++
            } else {
                counted++
                if (inner) hits++
            }
        }
        return if (counted < samples / 3) 0.0 else hits.toDouble() / counted
    }

    /** Any writing between [near] and [far] px along (nx, ny); null when off-frame. */
    private fun probe(mask: ByteArray, width: Int, height: Int, px: Double, py: Double,
                      nx: Double, ny: Double, near: Double, far: Double): Boolean? {
        var valid = false
        var o = near
        while (o <= far) {
            val x = (px + nx * o).toInt()
            val y = (py + ny * o).toInt()
            if (x in 0 until width && y in 0 until height) {
                valid = true
                if (mask[y * width + x].toInt() != 0) return true
            }
            o += 1.0
        }
        return if (valid) false else null
    }

    /** Degrees: the largest angle between the two pairs of opposite sides. */
    const val MAX_OPPOSITE_ANGLE = 16.0

    fun maxOppositeAngle(q: Array<Point>): Double {
        fun dir(a: Point, b: Point) = kotlin.math.atan2(b.y - a.y, b.x - a.x)
        fun between(a: Double, b: Double): Double {
            // Opposite sides run in opposite directions around the quad.
            var d = abs(a - b + Math.PI) % (2 * Math.PI)
            if (d > Math.PI) d = 2 * Math.PI - d
            return Math.toDegrees(d)
        }
        return maxOf(between(dir(q[0], q[1]), dir(q[2], q[3])),
            between(dir(q[1], q[2]), dir(q[3], q[0])))
    }

    /** True when [p] lies inside the convex quad, with [tolerance] px. */
    fun inside(p: Point, quad: Array<Point>, tolerance: Double = 0.0): Boolean {
        var sign = 0
        for (i in 0 until 4) {
            val a = quad[i]
            val b = quad[(i + 1) % 4]
            val len = hypot(b.x - a.x, b.y - a.y).coerceAtLeast(1e-6)
            val cross = ((b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)) / len
            if (abs(cross) <= tolerance) continue
            val s = if (cross > 0) 1 else -1
            if (sign == 0) sign = s else if (s != sign) return false
        }
        return true
    }

    /** Writing pixels (sampled every 2 px) inside [quad]. */
    fun countInside(quad: Array<Point>, mask: ByteArray, width: Int, height: Int): Int {
        val minX = quad.minOf { it.x }.toInt().coerceIn(0, width - 1)
        val maxX = quad.maxOf { it.x }.toInt().coerceIn(0, width - 1)
        val minY = quad.minOf { it.y }.toInt().coerceIn(0, height - 1)
        val maxY = quad.maxOf { it.y }.toInt().coerceIn(0, height - 1)
        var count = 0
        var y = minY
        while (y <= maxY) {
            var x = minX
            while (x <= maxX) {
                if (mask[y * width + x].toInt() != 0 &&
                    inside(Point(x.toDouble(), y.toDouble()), quad)) count++
                x += 2
            }
            y += 2
        }
        return count
    }
}
