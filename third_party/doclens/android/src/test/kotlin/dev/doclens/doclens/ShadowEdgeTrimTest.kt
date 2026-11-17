package dev.doclens.doclens

import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertSame
import kotlin.test.assertTrue

class ShadowEdgeTrimTest {
    private val w = 600
    private val h = 800

    private fun rgb(r: Int, g: Int, b: Int) = (0xFF shl 24) or (r shl 16) or (g shl 8) or b

    /** Dark blue cloth with yellow-green dots, like the user's video. */
    private fun cloth(x: Int, y: Int): Int =
        if ((x / 3 + y / 4) % 4 == 0) rgb(150, 170, 60) else rgb(40, 45, 95)

    private fun darker(c: Int, f: Double) = rgb(
        (((c shr 16) and 0xFF) * f).toInt(), (((c shr 8) and 0xFF) * f).toInt(),
        ((c and 0xFF) * f).toInt())

    /** Card from (150,250) to (450,450); shadow 12 px to the right and below. */
    private fun scene(shadow: Boolean, border: Boolean = false,
                      table: ((Int, Int) -> Int)? = null): IntArray {
        val px = IntArray(w * h)
        for (y in 0 until h) for (x in 0 until w) {
            val surface = table?.invoke(x, y) ?: cloth(x, y)
            val inCard = x in 150..450 && y in 250..450
            val inShadow = shadow && !inCard && x in 162..462 && y in 262..462
            px[y * w + x] = when {
                inCard && border && (x < 158 || x > 442 || y < 258 || y > 442) ->
                    rgb(30, 60, 160)
                inCard -> if ((x + y) % 41 == 0) rgb(40, 40, 40) else rgb(238, 238, 232)
                inShadow -> darker(surface, 0.5)
                else -> surface
            }
        }
        return px
    }

    private fun trim(px: IntArray, c: DoubleArray) =
        ShadowEdgeTrim.trim(c, w, h) { x, y -> px[y * w + x] }

    @Test
    fun outlineAroundTheShadowIsPulledOntoTheCard() {
        val px = scene(shadow = true)
        val outline = doubleArrayOf(150.0, 250.0, 462.0, 250.0, 462.0, 462.0, 150.0, 462.0)
        val out = trim(px, outline)
        // Right and bottom move in by the 12 px shadow; top and left stay.
        assertTrue(abs(out[2] - 450.5) <= 2.5, "right ${out[2]}")
        assertTrue(abs(out[5] - 450.5) <= 2.5, "bottom ${out[5]}")
        assertTrue(abs(out[0] - 150.0) <= 1.0, "left ${out[0]}")
        assertTrue(abs(out[1] - 250.0) <= 1.0, "top ${out[1]}")
    }

    @Test
    fun exactOutlineIsLeftAlone() {
        val px = scene(shadow = true)
        val outline = doubleArrayOf(150.0, 250.0, 450.0, 250.0, 450.0, 450.0, 150.0, 450.0)
        assertSame(outline, trim(px, outline))
    }

    @Test
    fun printedCardBorderIsNotMistakenForShadow() {
        val px = scene(shadow = false, border = true) { _, _ -> rgb(185, 180, 175) }
        val outline = doubleArrayOf(150.0, 250.0, 450.0, 250.0, 450.0, 450.0, 150.0, 450.0)
        assertSame(outline, trim(px, outline))
    }

    @Test
    fun cardDarkerThanTheTableIsLeftAlone() {
        val px = IntArray(w * h) { i ->
            val x = i % w; val y = i / w
            if (x in 150..450 && y in 250..450) rgb(60, 80, 120) else rgb(220, 220, 215)
        }
        val outline = doubleArrayOf(150.0, 250.0, 462.0, 250.0, 462.0, 462.0, 150.0, 462.0)
        assertSame(outline, trim(px, outline))
    }
}
