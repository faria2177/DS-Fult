package dev.doclens.doclens

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class LivePaperInteriorGuardTest {
    private fun rectangle(l: Float, t: Float, r: Float, b: Float) = Quad(
        PointF(l, t), PointF(r, t),
        PointF(r, b), PointF(l, b),
    )

    private fun frame(width: Int, height: Int, paperColor: Int = 221): ByteArray {
        val pixels = ByteArray(width * height * 4)
        for (i in 0 until width * height) {
            pixels[i * 4] = paperColor.toByte()
            pixels[i * 4 + 1] = paperColor.toByte()
            pixels[i * 4 + 2] = paperColor.toByte()
            pixels[i * 4 + 3] = 255.toByte()
        }
        return pixels
    }

    private fun paintRect(
        rgba: ByteArray, width: Int, height: Int,
        left: Int, top: Int, right: Int, bottom: Int, gray: Int,
    ) {
        for (y in top until bottom) for (x in left until right) {
            val pos = (y * width + x) * 4
            for (channel in 0..2) rgba[pos + channel] = gray.toByte()
        }
    }

    @Test
    fun higherResolutionRetryOnlyPromotesActualEnclosingPage() {
        val innerText = rectangle(.24f, .18f, .76f, .84f)
        val outerPage = rectangle(.12f, .08f, .88f, .93f)
        assertTrue(LivePaperInteriorGuard.recoveredOuterPage(
            innerText, outerPage, 384, 512) == outerPage)
        // The scanner must not invent more paper or follow an unrelated
        // near-frame desk/shadow contour when moving the camera closer.
        assertTrue(LivePaperInteriorGuard.recoveredOuterPage(
            innerText, rectangle(.01f, .01f, .99f, .99f),
            384, 512) == null)
        assertTrue(LivePaperInteriorGuard.recoveredOuterPage(
            innerText, rectangle(.01f, .01f, .70f, .70f),
            384, 512) == null)
    }

    @Test
    fun writtenTextRectangleWithinWhiteA4HasPaleOutsideOnAllSides() {
        val width = 384
        val height = 512
        val pixels = frame(width, height)
        val text = rectangle(.23f, .18f, .77f, .84f)
        // Strong black lines may surround the written text block; margins
        // *outside* remain white page. Treat this as a dangerous inner crop.
        paintRect(pixels, width, height, 89, 92, 91, 431, 20)
        paintRect(pixels, width, height, 294, 92, 296, 431, 20)
        paintRect(pixels, width, height, 89, 92, 296, 94, 20)
        paintRect(pixels, width, height, 89, 429, 296, 431, 20)
        assertTrue(LivePaperInteriorGuard.isPrintedInterior(
            text, pixels, width, height))
    }

    @Test
    fun actualWhitePageAgainstDarkAndBusyBackgroundIsNotHidden() {
        val width = 384
        val height = 512
        val pixels = frame(width, height, paperColor = 40)
        paintRect(pixels, width, height, 45, 45, 345, 462, 218)
        assertFalse(LivePaperInteriorGuard.isPrintedInterior(
            rectangle(.12f, .09f, .90f, .90f),
            pixels, width, height))
    }

    @Test
    fun clippedFrameWithoutThreeVisibleWhiteMarginsCannotBeRejected() {
        val pixels = frame(384, 512)
        assertFalse(LivePaperInteriorGuard.isPrintedInterior(
            rectangle(.01f, .01f, .99f, .99f), pixels, 384, 512))
    }
}
