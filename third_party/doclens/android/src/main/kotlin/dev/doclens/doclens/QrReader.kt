package dev.doclens.doclens

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * libds_qr.so — QR and barcode reading on the device with the open-source
 * zxing-cpp decoder (Apache-2.0) behind DocScanner's own JNI wrapper.
 * Used live while scanning (throttled, own thread) and for still photos.
 */
internal object QrReader {
    private val available: Boolean by lazy {
        try {
            System.loadLibrary("ds_qr")
            true
        } catch (_: Throwable) {
            false
        }
    }

    private external fun readNative(
        luma: ByteArray, width: Int, height: Int, tryHarder: Boolean,
    ): Array<String>?

    fun read(luma: ByteArray, width: Int, height: Int, tryHarder: Boolean):
        List<Map<String, Any>> {
        if (!available) return emptyList()
        val raw = try {
            readNative(luma, width, height, tryHarder)
        } catch (_: Throwable) {
            null
        } ?: return emptyList()
        val out = mutableListOf<Map<String, Any>>()
        var i = 0
        while (i + 2 < raw.size) {
            val corners = raw[i + 2].split(',').mapNotNull { it.toIntOrNull() }
            out.add(mapOf(
                "format" to raw[i],
                "text" to raw[i + 1],
                "corners" to corners.mapIndexed { k, v ->
                    v.toDouble() / (if (k % 2 == 0) width else height)
                },
            ))
            i += 3
        }
        return out
    }

    /** Codes in a photo file (EXIF applied), searched thoroughly. */
    fun readFile(path: String): List<Map<String, Any>> {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return emptyList()
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= 2400) sample *= 2
        val decoded = BitmapFactory.decodeFile(path, BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }) ?: return emptyList()
        val matrix = ExifRotator.orientationMatrix(ExifRotator.orientationOf(path))
        val upright = if (matrix == null) decoded else Bitmap.createBitmap(
            decoded, 0, 0, decoded.width, decoded.height, matrix, true,
        ).also { if (it !== decoded) decoded.recycle() }
        val w = upright.width
        val h = upright.height
        val pixels = IntArray(w * h)
        upright.getPixels(pixels, 0, w, 0, 0, w, h)
        upright.recycle()
        val luma = ByteArray(w * h) { k ->
            val p = pixels[k]
            ((77 * ((p shr 16) and 255) + 150 * ((p shr 8) and 255) + 29 * (p and 255)) shr 8)
                .toByte()
        }
        return read(luma, w, h, tryHarder = true)
    }

    /**
     * Live helper: decodes at most one frame at a time on its own thread and
     * reports codes through [emit] (frame-normalised corners, rotated to the
     * displayed orientation by the caller's [rotate]).
     */
    class Live(private val emit: (List<Map<String, Any>>) -> Unit) {
        private val executor = Executors.newSingleThreadExecutor()
        private val busy = AtomicBoolean(false)
        private var lastOffer = 0L
        private var lastSignature = ""
        private var lastEmit = 0L

        fun wants(now: Long): Boolean =
            available && !busy.get() && now - lastOffer >= INTERVAL_MS

        fun offer(luma: ByteArray, width: Int, height: Int, rotation: Int, now: Long) {
            if (!busy.compareAndSet(false, true)) return
            lastOffer = now
            executor.execute {
                try {
                    val codes = read(luma, width, height, tryHarder = false)
                        .map { code -> rotateCorners(code, rotation) }
                    if (codes.isNotEmpty()) {
                        val signature = codes.joinToString("\n") { "${it["format"]}:${it["text"]}" }
                        val time = System.currentTimeMillis()
                        if (signature != lastSignature || time - lastEmit > 1500) {
                            lastSignature = signature
                            lastEmit = time
                            emit(codes)
                        }
                    }
                } finally {
                    busy.set(false)
                }
            }
        }

        fun dispose() = executor.shutdown()

        private fun rotateCorners(code: Map<String, Any>, rotation: Int): Map<String, Any> {
            @Suppress("UNCHECKED_CAST")
            val c = code["corners"] as List<Double>
            val rotated = c.chunked(2).flatMap { (x, y) ->
                when (((rotation % 360) + 360) % 360) {
                    90 -> listOf(1 - y, x)
                    180 -> listOf(1 - x, 1 - y)
                    270 -> listOf(y, 1 - x)
                    else -> listOf(x, y)
                }
            }
            return code + ("corners" to rotated)
        }

        companion object {
            const val INTERVAL_MS = 500L
            const val SIDE = 1280
        }
    }

    /** Scales a luma buffer down to fit [side] (nearest), if larger. */
    fun fit(luma: ByteArray, width: Int, height: Int, side: Int): Triple<ByteArray, Int, Int> {
        val scale = side.toDouble() / max(width, height)
        if (scale >= 1) return Triple(luma, width, height)
        val w = max(1, (width * scale).roundToInt())
        val h = max(1, (height * scale).roundToInt())
        val out = ByteArray(w * h)
        for (y in 0 until h) {
            val sy = (y / scale).toInt().coerceAtMost(height - 1)
            for (x in 0 until w) {
                out[y * w + x] = luma[sy * width + (x / scale).toInt().coerceAtMost(width - 1)]
            }
        }
        return Triple(out, w, h)
    }
}
