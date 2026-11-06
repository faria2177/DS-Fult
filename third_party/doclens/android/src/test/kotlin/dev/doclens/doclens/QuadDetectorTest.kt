package dev.doclens.doclens

import kotlin.test.Test
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.math.abs

class QuadDetectorTest {
    @Test
    fun centralLightCardWinsOverLargerBorderClutter() {
        val width = 128
        val height = 96
        val luma = ByteArray(width * height) { 22 }
        fill(luma, width, 28, 17, 100, 60, 195)
        // Brighter cloth across the bottom is the largest connected region.
        fill(luma, width, 0, 71, width, height, 195)

        val quad = assertNotNull(
            QuadDetector.detect(luma, width, height, DetectionPolarity.AUTO, 12),
        )
        assertTrue(quad.topLeft.x in 0.18f..0.3f)
        assertTrue(quad.topLeft.y in 0.12f..0.25f)
        assertTrue(quad.bottomRight.x in 0.7f..0.85f)
        assertTrue(quad.bottomRight.y in 0.55f..0.7f)
    }

    @Test
    fun centralDarkCardWinsOverLargerDarkBorder() {
        val width = 128
        val height = 96
        val luma = ByteArray(width * height) { 218.toByte() }
        fill(luma, width, 28, 17, 100, 60, 35)
        fill(luma, width, 0, 71, width, height, 35)

        val quad = assertNotNull(
            QuadDetector.detect(luma, width, height, DetectionPolarity.AUTO, 12),
        )
        assertTrue(quad.topLeft.x in 0.18f..0.3f)
        assertTrue(quad.bottomRight.y in 0.55f..0.7f)
    }

    @Test
    fun uniformFrameNeverProducesFakeDocument() {
        val luma = ByteArray(128 * 96) { 120.toByte() }
        assertNull(QuadDetector.detect(luma, 128, 96, DetectionPolarity.AUTO, 12))
    }

    @Test
    fun separateBrightCardKeepsItsExactFourCorners() {
        val width = 320
        val height = 240
        val luma = ByteArray(width * height) { 35 }
        // A brighter background region occupies more pixels than the card.
        fill(luma, width, 0, 0, 110, 240, 230)
        fill(luma, width, 139, 49, 293, 199, 190)

        val quad = assertNotNull(
            QuadDetector.detect(luma, width, height, DetectionPolarity.AUTO, 12),
        )
        assertTrue(abs(quad.topLeft.x - 139f / width) < .035f)
        assertTrue(abs(quad.topLeft.y - 49f / height) < .035f)
        assertTrue(abs(quad.bottomRight.x - 292f / width) < .035f)
        assertTrue(abs(quad.bottomRight.y - 198f / height) < .035f)
    }

    @Test
    fun darkWalletIsDetectedAgainstLightSurface() {
        val width = 320
        val height = 240
        val luma = ByteArray(width * height) { 200.toByte() }
        fill(luma, width, 65, 52, 264, 193, 45)

        val quad = assertNotNull(
            QuadDetector.detect(luma, width, height, DetectionPolarity.AUTO, 12),
        )
        assertTrue(abs(quad.topLeft.x - 65f / width) < .035f)
        assertTrue(abs(quad.topLeft.y - 52f / height) < .035f)
        assertTrue(abs(quad.bottomRight.x - 263f / width) < .035f)
        assertTrue(abs(quad.bottomRight.y - 192f / height) < .035f)
    }

    private fun fill(
        image: ByteArray,
        width: Int,
        left: Int,
        top: Int,
        right: Int,
        bottom: Int,
        brightness: Int,
    ) {
        for (y in top until bottom) for (x in left until right) {
            image[y * width + x] = brightness.toByte()
        }
    }
}
