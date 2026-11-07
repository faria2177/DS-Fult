package dev.doclens.doclens

import java.nio.ByteBuffer
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class YuvUtilsColorTest {
    @Test
    fun neutralChromaRemainsGrayAndOpaque() {
        val rgba = YuvUtils.convertToRgba(
            luma = YuvUtils.Luma(ByteArray(4) { 128.toByte() }, 2, 2),
            sourceWidth = 2,
            sourceHeight = 2,
            downscaleTo = 2,
            uPlane = ByteBuffer.wrap(byteArrayOf(128.toByte())),
            uRowStride = 1,
            uPixelStride = 1,
            vPlane = ByteBuffer.wrap(byteArrayOf(128.toByte())),
            vRowStride = 1,
            vPixelStride = 1,
        )
        for (offset in rgba.indices step 4) {
            assertEquals(rgba[offset], rgba[offset + 1])
            assertEquals(rgba[offset + 1], rgba[offset + 2])
            assertEquals(255, rgba[offset + 3].toInt() and 0xFF)
        }
    }

    @Test
    fun sameBrightnessDifferentChromaProducesDifferentColorEdges() {
        // Two 2x2 colour regions have identical luma. A Y-only preview
        // cannot distinguish them, whereas an RGB/saturation pass can.
        // Nonzero buffer positions, padding and pixelStride=2 mimic the
        // interleaved, padded chroma planes returned by real CameraX devices.
        val u = ByteBuffer.wrap(byteArrayOf(0, 90, 0, 240.toByte(), 0))
        val v = ByteBuffer.wrap(byteArrayOf(0, 240.toByte(), 0, 110, 0))
        u.position(1)
        v.position(1)
        val rgba = YuvUtils.convertToRgba(
            luma = YuvUtils.Luma(ByteArray(8) { 82.toByte() }, 4, 2),
            sourceWidth = 4,
            sourceHeight = 2,
            downscaleTo = 4,
            uPlane = u,
            uRowStride = 4,
            uPixelStride = 2,
            vPlane = v,
            vRowStride = 4,
            vPixelStride = 2,
        )
        val leftRed = rgba[0].toInt() and 0xFF
        val leftBlue = rgba[2].toInt() and 0xFF
        val rightRed = rgba[8].toInt() and 0xFF
        val rightBlue = rgba[10].toInt() and 0xFF
        assertTrue(leftRed > 230 && leftBlue < 40)
        assertTrue(rightBlue > 230 && rightRed < 130)
        assertTrue(leftRed > rightRed)
        assertTrue(rightBlue > leftBlue)
    }

    @Test
    fun downscaledColorUsesOriginalChromaCoordinates() {
        val rgba = YuvUtils.convertToRgba(
            luma = YuvUtils.Luma(ByteArray(4) { 82.toByte() }, 2, 2),
            sourceWidth = 4,
            sourceHeight = 4,
            downscaleTo = 2,
            uPlane = ByteBuffer.wrap(byteArrayOf(90, 240.toByte(), 90, 240.toByte())),
            uRowStride = 2,
            uPixelStride = 1,
            vPlane = ByteBuffer.wrap(byteArrayOf(240.toByte(), 110, 240.toByte(), 110)),
            vRowStride = 2,
            vPixelStride = 1,
        )
        assertTrue((rgba[0].toInt() and 0xFF) > (rgba[4].toInt() and 0xFF))
        assertTrue((rgba[6].toInt() and 0xFF) > (rgba[2].toInt() and 0xFF))
    }
}
