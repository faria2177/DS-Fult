package dev.doclens.doclens

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class CaptureOrientationMatcherTest {
    private fun document(): CaptureOrientationMatcher.Image {
        val w = 120
        val h = 160
        val data = ByteArray(w * h)
        for (y in 0 until h) {
            for (x in 0 until w) {
                val paper = x in 17..105 && y in 16..143
                val value = when {
                    !paper -> 105 + (x * 3 + y) % 21
                    y in 20..29 && x in 23..95 -> 46 // asymmetric title
                    y in 36..124 && x in 26..96 && x % 11 == 0 -> 40
                    y in 36..124 && x in 26..96 && y % 9 == 0 -> 53
                    y in 36..124 && x in 26..96 &&
                        (x * 17 + y * 13) % 31 < 4 -> 71 // uneven table text
                    y in 129..137 && x in 63..100 -> 128 // signature
                    else -> 239
                }
                data[y * w + x] = value.toByte()
            }
        }
        return CaptureOrientationMatcher.Image(data, w, h)
    }

    /** Rotate a complete byte image clockwise without relying on Android Bitmap. */
    private fun rotate(src: CaptureOrientationMatcher.Image, turns: Int):
        CaptureOrientationMatcher.Image {
        val t = ((turns % 4) + 4) % 4
        val width = if (t % 2 == 0) src.width else src.height
        val height = if (t % 2 == 0) src.height else src.width
        val out = ByteArray(width * height)
        for (y in 0 until height) for (x in 0 until width) {
            val (sx, sy) = when (t) {
                1 -> y to (src.height - 1 - x)
                2 -> (src.width - 1 - x) to (src.height - 1 - y)
                3 -> (src.width - 1 - y) to x
                else -> x to y
            }
            out[y * width + x] = src.pixels[sy * src.width + sx]
        }
        return CaptureOrientationMatcher.Image(out, width, height)
    }

    @Test
    fun video381776PortraitPageShouldRemainUprightAfterCapture() {
        val upright = document()
        // Camera analysis YUV is stored sensor-landscape with rotation=90;
        // the camera still contains the sideways version of the same sheet.
        val sensorPreview = rotate(upright, 3)
        val sidewaysStill = rotate(upright, 1)
        val match = CaptureOrientationMatcher.find(sensorPreview, 90, sidewaysStill)
        assertEquals(3, match?.clockwiseTurns)
    }

    @Test
    fun alreadyUprightStillIsNotRotatedAgain() {
        val upright = document()
        val preview = rotate(upright, 3)
        assertEquals(0, CaptureOrientationMatcher.find(preview, 90, upright)?.clockwiseTurns)
    }

    @Test
    fun differentSensorRotationAndUpsideDownCaptureAreHandled() {
        val upright = document()
        val preview = rotate(upright, 1)
        val sidewaysStill = rotate(upright, 3)
        assertEquals(1, CaptureOrientationMatcher.find(preview, 270, sidewaysStill)
            ?.clockwiseTurns)
        assertEquals(2, CaptureOrientationMatcher.find(upright, 0,
            rotate(upright, 2))?.clockwiseTurns)
    }

    @Test
    fun uniformOrUnrelatedFramesDoNotGuessOrientation() {
        val blank = CaptureOrientationMatcher.Image(ByteArray(120 * 160) { 230.toByte() },
            120, 160)
        assertNull(CaptureOrientationMatcher.find(blank, 0, blank))
        val upright = document()
        val unrelated = CaptureOrientationMatcher.Image(ByteArray(120 * 160) { index ->
            ((index * 61 + index / 120 * 37) % 256).toByte()
        }, 120, 160)
        assertNull(CaptureOrientationMatcher.find(upright, 0, unrelated))
    }

    @Test
    fun matchedLiveCornersAreMappedThroughCaptureFramingDifference() {
        val match = CaptureOrientationMatcher.Match(
            clockwiseTurns = 1, score = .9, margin = .4,
            scale = .94, shiftX = .09, shiftY = -.09,
        )
        val quad = Quad(PointF(.2f, .2f), PointF(.8f, .2f),
            PointF(.8f, .8f), PointF(.2f, .8f))
        val mapped = match.mapPreviewQuad(quad)!!
        assertEquals(.308f, mapped.topLeft.x, .001f)
        assertEquals(.128f, mapped.topLeft.y, .001f)
        val offscreen = Quad(PointF(0f, 0f), PointF(1f, 0f),
            PointF(1f, 1f), PointF(0f, 1f))
        assertNull(match.mapPreviewQuad(offscreen))
    }
}
