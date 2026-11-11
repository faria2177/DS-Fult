package dev.doclens.doclens

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import androidx.exifinterface.media.ExifInterface

object ExifRotator {
    /**
     * Longest side used when reading a gallery/exported photo. Scanner exports
     * and modern phone cameras routinely exceed this (6000-12000 px). Decoding
     * those at full size used to throw OutOfMemoryError, which the caller
     * swallowed and reported as "auto-crop skipped" — the photo then arrived
     * uncropped, which reads as "auto crop does not work". Detection and warp
     * share this cap so both work in the same pixel space.
     */
    const val DECODE_MAX_DIMENSION = 4096

    /** EXIF orientation of [path], or ORIENTATION_NORMAL when unreadable. */
    fun orientationOf(path: String): Int = try {
        ExifInterface(path).getAttributeInt(
            ExifInterface.TAG_ORIENTATION,
            ExifInterface.ORIENTATION_NORMAL,
        )
    } catch (_: Exception) {
        ExifInterface.ORIENTATION_NORMAL
    }

    /**
     * Full transform for all eight EXIF orientations, including the mirrored
     * ones. Previously only ROTATE_90/180/270 were handled, so a photo tagged
     * FLIP_HORIZONTAL / TRANSPOSE / TRANSVERSE (common for images exported by
     * other scanner apps and for front-camera or edited documents) was
     * analysed upright but dewarped mirrored — the cropped page came out
     * horizontally flipped or with the wrong corner order.
     *
     * Returns null when the image needs no change.
     */
    fun orientationMatrix(orientation: Int): Matrix? {
        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                // Mirror across the main diagonal: rotate 90° CW, then flip X.
                matrix.postRotate(90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                // Mirror across the anti-diagonal: rotate 270° CW, then flip X.
                matrix.postRotate(270f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            else -> return null
        }
        return matrix
    }

    /**
     * Returns either the original bitmap unchanged, or a new upright copy.
     * Caller is responsible for recycling whichever it doesn't keep — use
     * referential identity (`!==`) to tell them apart.
     */
    fun rotated(bitmap: Bitmap, path: String): Bitmap =
        rotated(bitmap, orientationOf(path))

    fun rotated(bitmap: Bitmap, orientation: Int): Bitmap {
        val matrix = orientationMatrix(orientation) ?: return bitmap
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
    }

    /**
     * Decode [path] with a bounded sample size and bake in the EXIF
     * orientation (rotation *and* mirroring), returning an upright bitmap.
     *
     * Every still-image entry point — detection, warp, rotate, OCR — must use
     * this so the normalized quad the detector reports is expressed in exactly
     * the pixel space the warp reads back. Two different decode paths (one
     * honouring a flip, one not) is what produced crops that were mirrored or
     * offset by the excluded border.
     *
     * Returns null when the file cannot be decoded. The caller owns the result
     * and must recycle it.
     */
    fun decodeUpright(
        path: String,
        maxDimension: Int = DECODE_MAX_DIMENSION,
    ): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

        val options = BitmapFactory.Options().apply {
            inPreferredConfig = Bitmap.Config.ARGB_8888
            inSampleSize = sampleSizeFor(bounds.outWidth, bounds.outHeight, maxDimension)
        }
        val decoded = BitmapFactory.decodeFile(path, options) ?: return null
        val upright = rotated(decoded, orientationOf(path))
        if (upright !== decoded) decoded.recycle()
        return upright
    }

    /** Smallest power-of-two subsample whose long side lands at or below the cap. */
    private fun sampleSizeFor(width: Int, height: Int, maxDimension: Int): Int {
        if (maxDimension <= 0) return 1
        val longest = maxOf(width, height)
        var sample = 1
        while (longest / sample > maxDimension) sample *= 2
        return sample
    }
}
