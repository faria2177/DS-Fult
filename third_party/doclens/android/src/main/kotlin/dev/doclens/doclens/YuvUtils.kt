package dev.doclens.doclens

import android.media.Image
import java.nio.ByteBuffer

/** Helpers for pulling the luma (Y) plane out of a YUV image and downscaling. */
object YuvUtils {
    data class Luma(val data: ByteArray, val width: Int, val height: Int)

    /** Extracts the Y plane, downscales by nearest neighbor so the max dimension
     *  is ~downscaleTo. Returns the bytes + new size. */
    fun extractLuma(image: Image, downscaleTo: Int): Luma {
        val plane = image.planes[0]
        val rowStride = plane.rowStride
        val pixelStride = plane.pixelStride
        val w = image.width
        val h = image.height
        val buffer = plane.buffer
        val src = ByteArray(buffer.remaining())
        buffer.get(src)

        val scale = (downscaleTo.toFloat() / maxOf(w, h)).coerceAtMost(1f)
        val outW = (w * scale).toInt().coerceAtLeast(1)
        val outH = (h * scale).toInt().coerceAtLeast(1)
        val out = ByteArray(outW * outH)
        for (y in 0 until outH) {
            val srcY = (y / scale).toInt().coerceIn(0, h - 1)
            val rowStart = srcY * rowStride
            for (x in 0 until outW) {
                val srcX = (x / scale).toInt().coerceIn(0, w - 1)
                out[y * outW + x] = src[rowStart + srcX * pixelStride]
            }
        }
        return Luma(out, outW, outH)
    }

    /**
     * Reconstructs colour at the SAME sampled coordinates as [extractLuma].
     * CameraX YUV_420_888 chroma planes may have independent row strides and
     * a pixel stride of two (interleaved NV12/NV21 backing memory). Reading
     * plane 1 as U and plane 2 as V handles both layouts without guessing the
     * underlying byte order. The output is RGBA for OpenCV's colour edges.
     *
     * An unsupported/truncated plane falls back to the original luma path.
     */
    fun extractRgba(image: Image, luma: Luma, downscaleTo: Int): ByteArray? {
        if (image.planes.size < 3) return null
        val u = image.planes[1]
        val v = image.planes[2]
        return try {
            convertToRgba(
                luma = luma,
                sourceWidth = image.width,
                sourceHeight = image.height,
                downscaleTo = downscaleTo,
                uPlane = u.buffer.duplicate(),
                uRowStride = u.rowStride,
                uPixelStride = u.pixelStride,
                vPlane = v.buffer.duplicate(),
                vRowStride = v.rowStride,
                vPixelStride = v.pixelStride,
            )
        } catch (_: RuntimeException) {
            null
        }
    }

    /** Separately testable stride-aware YUV420 to RGBA conversion. */
    internal fun convertToRgba(
        luma: Luma,
        sourceWidth: Int,
        sourceHeight: Int,
        downscaleTo: Int,
        uPlane: ByteBuffer,
        uRowStride: Int,
        uPixelStride: Int,
        vPlane: ByteBuffer,
        vRowStride: Int,
        vPixelStride: Int,
    ): ByteArray {
        require(sourceWidth > 0 && sourceHeight > 0 && downscaleTo > 0)
        require(uRowStride > 0 && vRowStride > 0 &&
                uPixelStride > 0 && vPixelStride > 0)
        require(luma.data.size == luma.width * luma.height)

        val scale = (downscaleTo.toFloat() / maxOf(sourceWidth, sourceHeight))
            .coerceAtMost(1f)
        require(luma.width == (sourceWidth * scale).toInt().coerceAtLeast(1))
        require(luma.height == (sourceHeight * scale).toInt().coerceAtLeast(1))

        val uBase = uPlane.position()
        val vBase = vPlane.position()
        val rgba = ByteArray(luma.width * luma.height * 4)
        for (y in 0 until luma.height) {
            val srcY = (y / scale).toInt().coerceIn(0, sourceHeight - 1)
            val chromaY = srcY / 2
            for (x in 0 until luma.width) {
                val srcX = (x / scale).toInt().coerceIn(0, sourceWidth - 1)
                val chromaX = srcX / 2
                val u = uPlane.get(uBase + chromaY * uRowStride +
                    chromaX * uPixelStride).toInt() and 0xFF
                val v = vPlane.get(vBase + chromaY * vRowStride +
                    chromaX * vPixelStride).toInt() and 0xFF
                val yy = luma.data[y * luma.width + x].toInt() and 0xFF
                val c = (yy - 16).coerceAtLeast(0)
                val d = u - 128
                val e = v - 128
                val output = (y * luma.width + x) * 4
                rgba[output] = ((298 * c + 409 * e + 128) shr 8)
                    .coerceIn(0, 255).toByte()
                rgba[output + 1] = ((298 * c - 100 * d - 208 * e + 128) shr 8)
                    .coerceIn(0, 255).toByte()
                rgba[output + 2] = ((298 * c + 516 * d + 128) shr 8)
                    .coerceIn(0, 255).toByte()
                rgba[output + 3] = 0xFF.toByte()
            }
        }
        return rgba
    }
}

object LumaEstimator {
    fun isLowLight(luma: ByteArray): Boolean {
        if (luma.isEmpty()) return false
        var sum = 0L
        var count = 0L
        val step = (luma.size / 1024).coerceAtLeast(1)
        var i = 0
        while (i < luma.size) {
            sum += luma[i].toInt() and 0xFF
            count++
            i += step
        }
        val avg = sum / count
        return avg < 50
    }
}
