package dev.doclens.doclens

import android.media.Image
import android.graphics.Rect
import java.nio.ByteBuffer

/** Helpers for pulling the luma (Y) plane out of a YUV image and downscaling. */
object YuvUtils {
    data class Luma(val data: ByteArray, val width: Int, val height: Int)

    /** CameraX ViewPort crops ImageAnalysis through ImageProxy.cropRect.
     * The detector must operate on this SAME sensor field as the on-disk JPEG.
     * Cropping both luma and chroma *before* detection prevents a border
     * outside the visible ViewPort from being reported as a green quad.
     */
    // Pure integer geometry can run in local JVM tests without Android's
    // unmocked Rect constructor. Android Rect stays at the CameraX boundary.
    data class CropBounds(
        val left: Int, val top: Int, val width: Int, val height: Int,
    )

    internal fun checkedCropBounds(
        w: Int, h: Int, left: Int, top: Int, right: Int, bottom: Int,
    ): CropBounds {
        require(left >= 0 && top >= 0 && right <= w && bottom <= h &&
            right > left && bottom > top)
        return CropBounds(left, top, right - left, bottom - top)
    }

    internal fun checkedCrop(w: Int, h: Int, cropRect: Rect?): CropBounds {
        return if (cropRect == null) {
            checkedCropBounds(w, h, 0, 0, w, h)
        } else checkedCropBounds(
            w, h, cropRect.left, cropRect.top, cropRect.right, cropRect.bottom)
    }

    /** Downsample the cropRect only. Coordinates returned by the detector
     * are now already normalized inside the shared CameraX ViewPort. */
    fun extractLuma(
        image: Image, downscaleTo: Int, cropBounds: CropBounds? = null,
    ): Luma {
        val plane = image.planes[0]
        val rowStride = plane.rowStride
        val pixelStride = plane.pixelStride
        val crop = cropBounds ?: checkedCropBounds(
            image.width, image.height, 0, 0, image.width, image.height)
        val buffer = plane.buffer.duplicate()
        val origin = buffer.position()
        val scale = (downscaleTo.toFloat() /
            maxOf(crop.width, crop.height)).coerceAtMost(1f)
        val outW = (crop.width * scale).toInt().coerceAtLeast(1)
        val outH = (crop.height * scale).toInt().coerceAtLeast(1)
        val out = ByteArray(outW * outH)
        for (y in 0 until outH) {
            val srcY = crop.top +
                (y / scale).toInt().coerceIn(0, crop.height - 1)
            for (x in 0 until outW) {
                val srcX = crop.left +
                    (x / scale).toInt().coerceIn(0, crop.width - 1)
                out[y * outW + x] = buffer.get(
                    origin + srcY * rowStride + srcX * pixelStride)
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
    fun extractRgba(image: Image, luma: Luma, downscaleTo: Int,
                    cropBounds: CropBounds? = null): ByteArray? {
        if (image.planes.size < 3) return null
        val u = image.planes[1]
        val v = image.planes[2]
        return try {
            convertToRgba(
                luma = luma,
                sourceWidth = image.width,
                sourceHeight = image.height,
                downscaleTo = downscaleTo,
                cropBounds = cropBounds ?: checkedCropBounds(
                    image.width, image.height, 0, 0,
                    image.width, image.height),
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
        cropBounds: CropBounds = CropBounds(0, 0, sourceWidth, sourceHeight),
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

        val crop = checkedCropBounds(sourceWidth, sourceHeight,
            cropBounds.left, cropBounds.top,
            cropBounds.left + cropBounds.width,
            cropBounds.top + cropBounds.height)
        val scale = (downscaleTo.toFloat() /
            maxOf(crop.width, crop.height)).coerceAtMost(1f)
        require(luma.width == (crop.width * scale).toInt().coerceAtLeast(1))
        require(luma.height == (crop.height * scale).toInt().coerceAtLeast(1))

        val uBase = uPlane.position()
        val vBase = vPlane.position()
        val rgba = ByteArray(luma.width * luma.height * 4)
        for (y in 0 until luma.height) {
            val srcY = crop.top +
                (y / scale).toInt().coerceIn(0, crop.height - 1)
            val chromaY = srcY / 2
            for (x in 0 until luma.width) {
                val srcX = crop.left +
                    (x / scale).toInt().coerceIn(0, crop.width - 1)
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
