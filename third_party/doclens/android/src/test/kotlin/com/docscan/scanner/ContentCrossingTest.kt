package com.docscan.scanner

import org.opencv.core.Point
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ContentCrossingTest {
    private val w = 288
    private val h = 384

    /** A page (40..248 x 40..344) whose writing sits inside a 20 px margin. */
    private fun page(): ByteArray {
        val mask = ByteArray(w * h)
        for (y in 60 until 324 step 4) for (x in 60 until 228) {
            if (x % 6 < 4) {
                mask[y * w + x] = 1
                mask[(y + 1) * w + x] = 1
            }
        }
        return mask
    }

    private fun quad(l: Double, t: Double, r: Double, b: Double) =
        arrayOf(Point(l, t), Point(r, t), Point(r, b), Point(l, b))

    @Test
    fun pageBorderRunsThroughItsBlankMargin() {
        val q = quad(40.0, 40.0, 248.0, 344.0)
        val mask = page()
        assertEquals(0.0, ContentCrossing.maxSideFraction(q, mask, w, h))
        val inside = ContentCrossing.insideFractions(q, mask, w, h)
        assertFalse(ContentCrossing.isInnerContentBox(0.0, inside))
    }

    @Test
    fun lineThroughTheWritingIsRejected() {
        // Left side at x = 140 cuts every text line.
        val q = quad(140.0, 40.0, 248.0, 344.0)
        val mask = page()
        val crossing = ContentCrossing.maxSideFraction(q, mask, w, h)
        assertTrue(crossing > ContentCrossing.MAX_SIDE_FRACTION, "crossing=$crossing")
        assertTrue(ContentCrossing.isInnerContentBox(crossing,
            ContentCrossing.insideFractions(q, mask, w, h)))
    }

    @Test
    fun textBlockOutlineHugsTheWritingAndIsRejected() {
        val q = quad(57.0, 57.0, 231.0, 327.0)
        val mask = page()
        val inside = ContentCrossing.insideFractions(q, mask, w, h)
        assertTrue(ContentCrossing.isInnerContentBox(
            ContentCrossing.maxSideFraction(q, mask, w, h), inside),
            inside.joinToString())
    }

    @Test
    fun withoutAWritingMaskNothingIsRejected() {
        val q = quad(140.0, 40.0, 248.0, 344.0)
        assertEquals(0.0, ContentCrossing.maxSideFraction(q, null, w, h))
        assertFalse(ContentCrossing.isInnerContentBox(0.0,
            ContentCrossing.insideFractions(q, null, w, h)))
    }

    @Test
    fun oppositeSidesOfAPhotographedPageAreNearlyParallel() {
        val tilted = arrayOf(Point(50.0, 40.0), Point(240.0, 50.0),
            Point(250.0, 340.0), Point(40.0, 330.0))
        assertTrue(ContentCrossing.maxOppositeAngle(tilted) < ContentCrossing.MAX_OPPOSITE_ANGLE)
        // 386799.mp4: a bottom "side" from one sheet's corner across the paper.
        val diagonal = arrayOf(Point(13.0, 50.0), Point(245.0, 65.0),
            Point(267.0, 355.0), Point(40.0, 250.0))
        assertTrue(ContentCrossing.maxOppositeAngle(diagonal) > ContentCrossing.MAX_OPPOSITE_ANGLE)
    }

    @Test
    fun countsWritingInsideAQuad() {
        val mask = page()
        val all = ContentCrossing.countInside(quad(40.0, 40.0, 248.0, 344.0), mask, w, h)
        val half = ContentCrossing.countInside(quad(40.0, 40.0, 144.0, 344.0), mask, w, h)
        assertTrue(all > 0 && half in (all / 3)..(all * 2 / 3), "all=$all half=$half")
    }
}
