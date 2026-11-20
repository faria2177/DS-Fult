package dev.doclens.doclens

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.io.ByteArrayOutputStream
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * libds_pdfcodec.so — DocScanner's own CCITT Group 4 encoder for
 * black-and-white PDF pages, plus fast JPEG compaction through Android's
 * built-in codec (libjpeg-turbo inside the platform). Every function returns
 * null on failure so the Dart export path stays the fallback.
 */
internal object NativePdfCodec {
    private val available: Boolean by lazy {
        try {
            System.loadLibrary("ds_pdfcodec")
            true
        } catch (_: Throwable) {
            false
        }
    }

    private external fun bilevelG4Native(
        pixels: IntArray, width: Int, height: Int, minShare: Double, maxColour: Double,
    ): ByteArray?

    /** Upright bitmap of [path], long side at most [maxSide]. */
    private fun decode(path: String, maxSide: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxSide) sample *= 2
        val decoded = BitmapFactory.decodeFile(path, BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }) ?: return null
        val matrix = ExifRotator.orientationMatrix(ExifRotator.orientationOf(path))
        val upright = if (matrix == null) decoded else Bitmap.createBitmap(
            decoded, 0, 0, decoded.width, decoded.height, matrix, true,
        ).also { if (it !== decoded) decoded.recycle() }
        val scale = maxSide.toDouble() / max(upright.width, upright.height)
        if (scale >= 1) return upright
        val scaled = Bitmap.createScaledBitmap(
            upright,
            max(1, (upright.width * scale).roundToInt()),
            max(1, (upright.height * scale).roundToInt()),
            true,
        )
        if (scaled !== upright) upright.recycle()
        return scaled
    }

    /** {width, height, data} of a 1-bit G4 page, or null when not B&W. */
    fun bilevelPage(path: String, minShare: Double, maxColour: Double): Map<String, Any>? {
        if (!available) return null
        return try {
            val bitmap = decode(path, 4000) ?: return null
            val width = bitmap.width
            val height = bitmap.height
            val pixels = IntArray(width * height)
            bitmap.getPixels(pixels, 0, width, 0, 0, width, height)
            bitmap.recycle()
            val data = bilevelG4Native(pixels, width, height, minShare, maxColour)
                ?: return null
            mapOf("width" to width, "height" to height, "data" to data)
        } catch (_: Throwable) {
            null
        }
    }

    /** JPEG of [path] with long side ≤ [maxSide] at [quality]. */
    fun compactJpeg(path: String, maxSide: Int, quality: Int): ByteArray? = try {
        val bitmap = decode(path, maxSide)
        if (bitmap == null) null else {
            val stream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.JPEG, quality.coerceIn(10, 100), stream)
            bitmap.recycle()
            stream.toByteArray()
        }
    } catch (_: Throwable) {
        null
    }
}
