package dev.doclens.doclens

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import java.io.ByteArrayOutputStream
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Long image with smart stitching. libds_stitch.so (ds_stitch.cpp) finds
 * where the bottom of a page and the top of the next one show the same
 * content; that repeated band is joined at its middle instead of being
 * shown twice. Pages without a clear overlap are simply placed one below
 * the other, as before.
 */
internal object LongImageStitcher {
    private const val WIDTH = 1100
    private const val MAX_HEIGHT = 15_500
    private const val FOOTER = 56

    private val available: Boolean by lazy {
        try {
            System.loadLibrary("ds_stitch")
            true
        } catch (_: Throwable) {
            false
        }
    }

    private external fun findOverlapNative(
        grayA: ByteArray, heightA: Int, grayB: ByteArray, heightB: Int, width: Int,
    ): IntArray?

    private fun decodeAtWidth(path: String): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (bounds.outWidth / (sample * 2) >= WIDTH) sample *= 2
        val decoded = BitmapFactory.decodeFile(path, BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }) ?: return null
        val matrix = ExifRotator.orientationMatrix(ExifRotator.orientationOf(path))
        val upright = if (matrix == null) decoded else Bitmap.createBitmap(
            decoded, 0, 0, decoded.width, decoded.height, matrix, true,
        ).also { if (it !== decoded) decoded.recycle() }
        val height = max(1, (upright.height * WIDTH.toDouble() / upright.width).roundToInt())
        val scaled = Bitmap.createScaledBitmap(upright, WIDTH, height, true)
        if (scaled !== upright) upright.recycle()
        return scaled
    }

    private fun gray(bitmap: Bitmap): ByteArray {
        val w = bitmap.width
        val h = bitmap.height
        val pixels = IntArray(w * h)
        bitmap.getPixels(pixels, 0, w, 0, 0, w, h)
        return ByteArray(w * h) { i ->
            val p = pixels[i]
            ((77 * ((p shr 16) and 255) + 150 * ((p shr 8) and 255) + 29 * (p and 255)) shr 8)
                .toByte()
        }
    }

    /** {jpeg, merged}: merged = number of page joins that removed an overlap. */
    fun stitch(paths: List<String>, watermark: Boolean, smart: Boolean): Map<String, Any>? {
        if (paths.isEmpty()) return null
        val pages = mutableListOf<Bitmap>()
        try {
            for (path in paths) pages.add(decodeAtWidth(path) ?: return null)
            // Overlap (rows, shift) between page i and i + 1.
            val overlaps = MutableList(pages.size) { intArrayOf(0, 0) }
            var merged = 0
            if (smart && available) {
                var previous = gray(pages[0])
                for (i in 1 until pages.size) {
                    val current = gray(pages[i])
                    val found = try {
                        findOverlapNative(previous, pages[i - 1].height, current,
                            pages[i].height, WIDTH)
                    } catch (_: Throwable) {
                        null
                    }
                    if (found != null && found[0] > 0) {
                        overlaps[i] = intArrayOf(found[0], found[1])
                        merged++
                    }
                    previous = current
                }
            }
            var total = 0
            for (i in pages.indices) total += pages[i].height - overlaps[i][0]
            val footer = if (watermark) FOOTER else 0
            if (total + footer > MAX_HEIGHT) {
                throw IllegalStateException("Long image exceeds 15,500 pixels in height. " +
                    "Please split the document into smaller groups.")
            }
            val out = Bitmap.createBitmap(WIDTH, total + footer, Bitmap.Config.ARGB_8888)
            out.eraseColor(Color.WHITE)
            val canvas = Canvas(out)
            val paint = Paint(Paint.FILTER_BITMAP_FLAG)
            var bottom = 0
            for (i in pages.indices) {
                val page = pages[i]
                val (rows, shift) = overlaps[i].let { it[0] to it[1] }
                // Join in the middle of the repeated band; earlier rows of
                // this page are already shown at the end of the previous one.
                val skip = rows / 2
                val top = bottom - rows
                canvas.drawBitmap(page, Rect(0, skip, page.width, page.height),
                    Rect(-shift, top + skip, page.width - shift, top + page.height), paint)
                bottom = top + page.height
            }
            if (watermark) {
                val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = Color.rgb(120, 120, 120)
                    textSize = 24f
                    textAlign = Paint.Align.CENTER
                }
                canvas.drawText("DocScanner", WIDTH / 2f, total + 36f, text)
            }
            val stream = ByteArrayOutputStream()
            out.compress(Bitmap.CompressFormat.JPEG, 86, stream)
            out.recycle()
            return mapOf("jpeg" to stream.toByteArray(), "merged" to merged)
        } finally {
            pages.forEach { it.recycle() }
        }
    }
}
