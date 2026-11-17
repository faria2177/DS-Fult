package dev.doclens.doclens

import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sin
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class PerspectiveAspectTest {
    private fun photo(w: Double, h: Double, rx: Double, ry: Double, distance: Double): DoubleArray {
        val f = 0.75 * 4000
        val out = DoubleArray(8)
        val signs = arrayOf(intArrayOf(-1, -1), intArrayOf(1, -1), intArrayOf(1, 1), intArrayOf(-1, 1))
        for ((i, s) in signs.withIndex()) {
            val x = s[0] * w / 2
            var y = s[1] * h / 2
            var z = 0.0
            val y1 = y * cos(rx) - z * sin(rx)
            val z1 = y * sin(rx) + z * cos(rx)
            y = y1; z = z1
            val x2 = x * cos(ry) + z * sin(ry)
            val z2 = -x * sin(ry) + z * cos(ry)
            out[2 * i] = f * x2 / (z2 + distance) + 1500
            out[2 * i + 1] = f * y / (z2 + distance) + 2000
        }
        return out
    }

    private fun side(c: DoubleArray, a: Int, b: Int) =
        hypot(c[2 * a] - c[2 * b], c[2 * a + 1] - c[2 * b + 1])

    @Test
    fun tiltedA4MatchesDartAndComesOutA4() {
        val c = photo(210.0, 297.0, 0.55, 0.2, 650.0)
        val naiveW = maxOf(side(c, 0, 1), side(c, 3, 2))
        val naiveH = maxOf(side(c, 0, 3), side(c, 1, 2))
        assertTrue(abs(naiveW / naiveH / (210.0 / 297.0) - 1) > 0.05)
        val (w, h) = PerspectiveAspect.outputSize(c, 3000, 4000, naiveW, naiveH)
        assertEquals(1 / 1.41421, w / h, 0.002)
        assertEquals(naiveW * naiveH, w * h, naiveW * naiveH * 1e-9)
    }

    @Test
    fun frontOnRectangleIsUnchanged() {
        val c = doubleArrayOf(500.0, 600.0, 2300.0, 600.0, 2300.0, 3000.0, 500.0, 3000.0)
        val (w, h) = PerspectiveAspect.outputSize(c, 3000, 4000, 1800.0, 2400.0)
        assertEquals(0.75, w / h, 1e-6)
    }
}
