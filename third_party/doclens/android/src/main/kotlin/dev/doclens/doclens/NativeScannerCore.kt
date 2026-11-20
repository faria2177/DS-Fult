package dev.doclens.doclens

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.exifinterface.media.ExifInterface
import java.io.ByteArrayOutputStream
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * libds_scannercore.so — DocScanner's own C++ scanner core
 * (src/main/cpp/ds_scanner_core.cpp): paper-region crop and scanner-style
 * "magic" enhancement for black-and-white pages.
 *
 * Every function returns null on any failure so the Dart implementation
 * (the reference) takes over; a missing ABI or memory pressure never stops
 * a scan.
 */
internal object NativeScannerCore {
    private const val WORKING_SIDE = 420
    private const val MAX_ENHANCE_PIXELS = 24_000_000L

    val available: Boolean by lazy {
        try {
            System.loadLibrary("ds_scannercore")
            true
        } catch (_: Throwable) {
            false
        }
    }

    private external fun magicEnhanceNative(
        pixels: IntArray, width: Int, height: Int, onlyNeutral: Boolean,
    ): Int

    private external fun paperRegionNative(
        pixels: IntArray, width: Int, height: Int,
    ): FloatArray?

    /**
     * Enhances an upright, already-cropped page. Returns encoded JPEG/PNG,
     * or null when the page is not black-and-white (with [onlyNeutral]) or
     * the native core is unavailable.
     */
    fun magicEnhance(bytes: ByteArray, png: Boolean, onlyNeutral: Boolean): ByteArray? {
        if (!available) return null
        return try {
            val options = BitmapFactory.Options().apply {
                inPreferredConfig = Bitmap.Config.ARGB_8888
            }
            val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
                ?: return null
            val width = bitmap.width
            val height = bitmap.height
            if (width.toLong() * height > MAX_ENHANCE_PIXELS) {
                bitmap.recycle()
                return null
            }
            val pixels = IntArray(width * height)
            bitmap.getPixels(pixels, 0, width, 0, 0, width, height)
            bitmap.recycle()
            if (magicEnhanceNative(pixels, width, height, onlyNeutral) != 0) return null
            val out = Bitmap.createBitmap(pixels, width, height, Bitmap.Config.ARGB_8888)
            val stream = ByteArrayOutputStream()
            out.compress(
                if (png) Bitmap.CompressFormat.PNG else Bitmap.CompressFormat.JPEG,
                94, stream,
            )
            out.recycle()
            stream.toByteArray()
        } catch (_: Throwable) {
            null
        }
    }

    /**
     * Paper region of a photo file (EXIF applied). Returns
     * found, paperFraction, width, height (upright pixels) and 8 normalised
     * corners TL, TR, BR, BL; null when unavailable.
     */
    fun paperRegion(path: String): Map<String, Any>? {
        if (!available) return null
        return try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, bounds)
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
            var sample = 1
            while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= WORKING_SIDE) {
                sample *= 2
            }
            val decoded = BitmapFactory.decodeFile(path, BitmapFactory.Options().apply {
                inSampleSize = sample
                inPreferredConfig = Bitmap.Config.ARGB_8888
            }) ?: return null
            val orientation = ExifRotator.orientationOf(path)
            val matrix = ExifRotator.orientationMatrix(orientation)
            val upright = if (matrix == null) decoded else Bitmap.createBitmap(
                decoded, 0, 0, decoded.width, decoded.height, matrix, true,
            ).also { if (it !== decoded) decoded.recycle() }
            val turned = orientation == ExifInterface.ORIENTATION_ROTATE_90 ||
                orientation == ExifInterface.ORIENTATION_ROTATE_270 ||
                orientation == ExifInterface.ORIENTATION_TRANSPOSE ||
                orientation == ExifInterface.ORIENTATION_TRANSVERSE
            val fullWidth = if (turned) bounds.outHeight else bounds.outWidth
            val fullHeight = if (turned) bounds.outWidth else bounds.outHeight
            val scale = WORKING_SIDE.toDouble() / max(upright.width, upright.height)
            val small = if (scale < 1) Bitmap.createScaledBitmap(
                upright,
                max(1, (upright.width * scale).roundToInt()),
                max(1, (upright.height * scale).roundToInt()),
                true,
            ) else upright
            val width = small.width
            val height = small.height
            val pixels = IntArray(width * height)
            small.getPixels(pixels, 0, width, 0, 0, width, height)
            if (small !== upright) small.recycle()
            upright.recycle()
            val raw = paperRegionNative(pixels, width, height) ?: return null
            mapOf(
                "found" to (raw[0] > .5f),
                "paperFraction" to raw[1].toDouble(),
                "width" to fullWidth,
                "height" to fullHeight,
                "corners" to (2 until 10).map { raw[it].toDouble() },
            )
        } catch (_: Throwable) {
            null
        }
    }
}
