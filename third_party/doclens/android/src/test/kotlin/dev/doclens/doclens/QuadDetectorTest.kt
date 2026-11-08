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

    @Test
    fun whiteSheetOnBlueClothKeepsCornersWhenLumaEdgesAreWeak() {
        val width = 320
        val height = 400
        val pixels = IntArray(width * height) { 0xFF2E62B7.toInt() }
        for (y in 62 until 348) for (x in 69 until 263) {
            // Include lightly shaded paper and some dirty marks, as with a
            // real white document on a blue tablecloth.
            val paper = if ((x + y) % 19 == 0) 0xFFCBC9C3.toInt()
                else 0xFFECECE8.toInt()
            pixels[y * width + x] = paper
        }
        val quad = assertNotNull(QuadDetector.detectNeutralPaper(pixels, width, height))
        assertTrue(abs(quad.topLeft.x - 69f / width) < .035f)
        assertTrue(abs(quad.topLeft.y - 62f / height) < .035f)
        assertTrue(abs(quad.bottomRight.x - 262f / width) < .035f)
        assertTrue(abs(quad.bottomRight.y - 347f / height) < .035f)
    }

    @Test
    fun whiteDeskWithoutColourContrastDoesNotInventPage() {
        val pixels = IntArray(320 * 240) { 0xFFE7E5E2.toInt() }
        assertNull(QuadDetector.detectNeutralPaper(pixels, 320, 240))
    }

    @Test
    fun contrastMaskFindsCompletePageOnNeutralDeskDespitePrintedTable() {
        val width = 320
        val height = 400
        val pixels = IntArray(width * height) { 0xFF777571.toInt() }
        fillRgb(pixels, width, 60, 48, 267, 351, 0xFFEDEAE6.toInt())
        // Dense letters/table lines can overpower the true outside edge in
        // Canny. The page mask must still cover the header and signature.
        for (y in 92 until 316 step 15) {
            fillRgb(pixels, width, 94, y, 230, y + 3, 0xFF343433.toInt())
        }
        val quad = assertNotNull(
            QuadDetector.detectBackgroundContrastPage(pixels, width, height),
        )
        assertTrue(abs(quad.topLeft.x - 60f / width) < .045f)
        assertTrue(abs(quad.topLeft.y - 48f / height) < .045f)
        assertTrue(abs(quad.bottomRight.x - 266f / width) < .045f)
        assertTrue(abs(quad.bottomRight.y - 350f / height) < .045f)
    }

    @Test
    fun contrastMaskDetectsSubtleGreyPaperOnGreyDesk() {
        val width = 320
        val height = 400
        val pixels = IntArray(width * height) { 0xFFBBB9B7.toInt() }
        fillRgb(pixels, width, 65, 62, 258, 345, 0xFFD8D7D4.toInt())
        val quad = assertNotNull(
            QuadDetector.detectBackgroundContrastPage(pixels, width, height),
        )
        assertTrue(abs(quad.topLeft.x - 65f / width) < .045f)
        assertTrue(abs(quad.bottomRight.y - 344f / height) < .045f)
    }

    @Test
    fun contrastMaskDoesNotInventPageOnUniformSurface() {
        val pixels = IntArray(320 * 400) { 0xFFD0CFCC.toInt() }
        assertNull(QuadDetector.detectBackgroundContrastPage(pixels, 320, 400))
    }

    @Test
    fun contrastMaskRejectsBrightObjectCutOffAtFrameEdge() {
        val width = 320
        val height = 400
        val pixels = IntArray(width * height) { 0xFF555555.toInt() }
        fillRgb(pixels, width, 0, 60, 123, 340, 0xFFE9E9E9.toInt())
        assertNull(QuadDetector.detectBackgroundContrastPage(pixels, width, height))
    }

    @Test
    fun saturatedPanelFindsEntireBluePosterAroundYellowInnerLabel() {
        val width = 320
        val height = 400
        val pixels = IntArray(width * height) { 0xFF746F68.toInt() }
        // Mixed stone and a patterned bottom surface defeat single-colour
        // background-corner sampling, as in the 381526.mp4 scene.
        for (y in 305 until height step 20) {
            for (x in 0 until width step 40) {
                val tile = if ((x / 40 + y / 20) % 2 == 0) 0xFF1768BE.toInt()
                    else 0xFF993A62.toInt()
                fillRgb(pixels, width, x, y, x + 40, (y + 20).coerceAtMost(height), tile)
            }
        }
        fillRgb(pixels, width, 65, 58, 255, 285, 0xFF1766C9.toInt())
        fillRgb(pixels, width, 102, 152, 215, 203, 0xFFEACA46.toInt())
        fillRgb(pixels, width, 112, 89, 190, 100, 0xFFF3F4F4.toInt())

        val quad = assertNotNull(QuadDetector.detectSaturatedPanel(pixels, width, height))
        assertTrue(abs(quad.topLeft.x - 65f / width) < .045f)
        assertTrue(abs(quad.topLeft.y - 58f / height) < .045f)
        assertTrue(abs(quad.bottomRight.x - 254f / width) < .045f)
        assertTrue(abs(quad.bottomRight.y - 284f / height) < .045f)
    }

    @Test
    fun saturatedPanelDoesNotTreatUniformBackgroundAsDocument() {
        val pixels = IntArray(320 * 400) { 0xFF1766C9.toInt() }
        assertNull(QuadDetector.detectSaturatedPanel(pixels, 320, 400))
    }

    @Test
    fun saturatedPanelRejectsSmallInternalColourBox() {
        val width = 320
        val height = 400
        val pixels = IntArray(width * height) { 0xFFDBD9D5.toInt() }
        fillRgb(pixels, width, 85, 55, 225, 179, 0xFF1766C9.toInt())
        assertNull(QuadDetector.detectSaturatedPanel(pixels, width, height))
    }

    @Test
    fun liveRgbaPanelTracksBlueClothInsteadOfBrownChair() {
        val width = 320
        val height = 400
        val pixels = IntArray(width * height) { 0xFF92745F.toInt() }
        fillRgb(pixels, width, 34, 48, 292, 100, 0xFF171C20.toInt())
        fillRgb(pixels, width, 50, 111, 268, 358, 0xFF176BC3.toInt())
        // A white, densely decorated centre must not replace the blue cloth.
        fillRgb(pixels, width, 92, 162, 228, 297, 0xFFE5E4D9.toInt())
        val rgba = ByteArray(width * height * 4)
        for (index in pixels.indices) {
            val colour = pixels[index]
            val offset = index * 4
            rgba[offset] = (colour shr 16).toByte()
            rgba[offset + 1] = (colour shr 8).toByte()
            rgba[offset + 2] = colour.toByte()
            rgba[offset + 3] = 0xFF.toByte()
        }
        val detected = assertNotNull(
            QuadDetector.detectSaturatedPanelInRgba(rgba, width, height),
        )
        assertTrue(abs(detected.topLeft.x - 50f / width) < .055f)
        assertTrue(abs(detected.topLeft.y - 111f / height) < .055f)
        assertTrue(abs(detected.bottomRight.x - 267f / width) < .055f)
        assertTrue(abs(detected.bottomRight.y - 357f / height) < .055f)
    }

    private fun fillRgb(
        image: IntArray, width: Int, left: Int, top: Int,
        right: Int, bottom: Int, color: Int,
    ) {
        for (y in top until bottom) for (x in left until right) {
            image[y * width + x] = color
        }
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
