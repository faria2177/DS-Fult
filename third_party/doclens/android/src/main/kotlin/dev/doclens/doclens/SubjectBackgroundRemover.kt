package dev.doclens.doclens

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.segmentation.subject.SubjectSegmentation
import com.google.mlkit.vision.segmentation.subject.SubjectSegmenterOptions
import java.io.ByteArrayOutputStream
import java.util.concurrent.TimeUnit
import kotlin.math.roundToInt

/**
 * Offline image inference using the Google Play services ML Kit Subject
 * Segmentation model. First use can download model assets from Google; the
 * user's photo bytes are never uploaded by this code. Invoke on a worker.
 */
internal object SubjectBackgroundRemover {
    fun process(imageBytes: ByteArray, backgroundArgb: Int?): ByteArray {
        require(imageBytes.isNotEmpty() && imageBytes.size <= 32 * 1024 * 1024) {
            "Image is too large for AI segmentation"
        }
        val decoded = BitmapFactory.decodeByteArray(
            imageBytes, 0, imageBytes.size,
        ) ?: throw IllegalArgumentException("Cannot decode source photo")
        val bitmap = decoded.copy(Bitmap.Config.ARGB_8888, false)
        if (bitmap !== decoded) decoded.recycle()
        val width = bitmap.width
        val height = bitmap.height
        if (width < 256 || height < 256 ||
            width.toLong() * height.toLong() > 4000000) {
            bitmap.recycle()
            throw IllegalArgumentException(
                "Choose an image at least 256 px wide and no more than 4 MP",
            )
        }
        val options = SubjectSegmenterOptions.Builder()
            .enableForegroundConfidenceMask()
            .build()
        val segmenter = SubjectSegmentation.getClient(options)
        try {
            // ML Kit's subject model runs on device after optional first-use
            // model download. Never block Flutter's main/platform thread.
            val result = Tasks.await(
                segmenter.process(InputImage.fromBitmap(bitmap, 0)),
                60, TimeUnit.SECONDS,
            )
            val mask = result.foregroundConfidenceMask
                ?: throw IllegalStateException("AI model returned no subject mask")
            val count = width * height
            if (mask.remaining() < count) {
                throw IllegalStateException("Unexpected AI mask dimensions")
            }
            val source = IntArray(count)
            bitmap.getPixels(source, 0, width, 0, 0, width, height)
            val confidence = FloatArray(count)
            mask.get(confidence)
            val pixels = SubjectAlphaMatte.composite(
                source, confidence, backgroundArgb,
            )
            val output = Bitmap.createBitmap(
                pixels, width, height, Bitmap.Config.ARGB_8888,
            )
            return try {
                val stream = ByteArrayOutputStream()
                if (!output.compress(Bitmap.CompressFormat.PNG, 100, stream)) {
                    throw IllegalStateException("Could not export transparent PNG")
                }
                stream.toByteArray()
            } finally {
                output.recycle()
            }
        } finally {
            segmenter.close()
            bitmap.recycle()
        }
    }
}

/** Pure Kotlin alpha-mask blending; exercised by local JVM unit tests. */
internal object SubjectAlphaMatte {
    fun composite(
        original: IntArray, confidence: FloatArray, backgroundArgb: Int?,
    ): IntArray {
        require(original.size == confidence.size && original.isNotEmpty())
        val output = IntArray(original.size)
        var foregroundPixels = 0
        for (i in original.indices) {
            val value = confidence[i]
            require(value.isFinite()) { "Invalid AI confidence mask" }
            // Smooth cutout edges preserve hair/shoulder antialiasing instead
            // of discarding every pixel beneath a hard 0.5 threshold.
            val t = ((value - .10f) / .80f).coerceIn(0f, 1f)
            val weight = t * t * (3f - 2f * t)
            val pixel = original[i]
            val alpha = ((pixel ushr 24) * weight).roundToInt().coerceIn(0, 255)
            if (alpha > 0) foregroundPixels++
            if (backgroundArgb == null) {
                output[i] = if (alpha == 0) 0 else
                    (alpha shl 24) or (pixel and 0xFFFFFF)
            } else {
                val bg = backgroundArgb
                val blend = alpha / 255f
                fun channel(shift: Int): Int {
                    val foreground = (pixel ushr shift) and 0xFF
                    val background = (bg ushr shift) and 0xFF
                    return (foreground * blend + background * (1f - blend))
                        .roundToInt().coerceIn(0, 255)
                }
                output[i] = (0xFF shl 24) or
                    (channel(16) shl 16) or
                    (channel(8) shl 8) or channel(0)
            }
        }
        // Never silently save a completely empty AI cutout.
        if (foregroundPixels < original.size / 250) {
            throw IllegalStateException(
                "No reliable foreground subject was found by the AI model",
            )
        }
        return output
    }
}
