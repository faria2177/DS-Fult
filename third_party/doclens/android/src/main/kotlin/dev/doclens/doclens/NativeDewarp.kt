package dev.doclens.doclens

import android.graphics.Bitmap

/**
 * libds_dewarp.so — DocScanner's own page flattening (ds_dewarp.cpp).
 * Traces the four sides of the page; when a side is clearly bowed it
 * resamples the page through a Coons patch so the sides and the text lines
 * become straight. Returns null for straight pages and on any failure, so
 * [ImageWarper] keeps its perspective warp.
 */
internal object NativeDewarp {
    private const val MAX_SOURCE_PIXELS = 20_000_000L

    private val available: Boolean by lazy {
        try {
            System.loadLibrary("ds_dewarp")
            true
        } catch (_: Throwable) {
            false
        }
    }

    private external fun dewarpNative(
        pixels: IntArray, width: Int, height: Int, quad: DoubleArray,
        outWidth: Int, outHeight: Int,
    ): IntArray?

    fun dewarp(source: Bitmap, quad: Quad, outWidth: Int, outHeight: Int): Bitmap? {
        if (!available) return null
        val width = source.width
        val height = source.height
        if (width.toLong() * height > MAX_SOURCE_PIXELS) return null
        return try {
            val pixels = IntArray(width * height)
            source.getPixels(pixels, 0, width, 0, 0, width, height)
            val corners = doubleArrayOf(
                quad.topLeft.x.toDouble(), quad.topLeft.y.toDouble(),
                quad.topRight.x.toDouble(), quad.topRight.y.toDouble(),
                quad.bottomRight.x.toDouble(), quad.bottomRight.y.toDouble(),
                quad.bottomLeft.x.toDouble(), quad.bottomLeft.y.toDouble(),
            )
            val out = dewarpNative(pixels, width, height, corners, outWidth, outHeight)
                ?: return null
            Bitmap.createBitmap(outWidth, outHeight, Bitmap.Config.ARGB_8888).apply {
                setPixels(out, 0, outWidth, 0, 0, outWidth, outHeight)
            }
        } catch (_: Throwable) {
            null
        }
    }
}
