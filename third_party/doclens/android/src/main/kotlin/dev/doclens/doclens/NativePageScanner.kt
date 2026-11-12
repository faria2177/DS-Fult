package dev.doclens.doclens

import kotlin.math.abs

/**
 * Own native C++ document contour proposal for captured stills.
 *
 * libds_pagescanner.so is built from src/main/cpp, not from CamScanner
 * binaries. No cloud, API token, or proprietary OpenCV dependency.
 * Failure/unavailable ABI returns null; the existing Kotlin/OpenCV and
 * Dart detectors remain the default safe path.
 */
internal object NativePageScanner {
    internal data class Candidate(
        val quad: Quad,
        val confidence: Float,
        val mode: Int,
    )

    private val nativeAvailable: Boolean by lazy {
        try {
            System.loadLibrary("ds_pagescanner")
            true
        } catch (_: Throwable) {
            false
        }
    }

    private external fun detectArgbNative(
        pixels: IntArray,
        width: Int,
        height: Int,
        preferCard: Boolean,
    ): FloatArray?

    fun detectArgb(
        pixels: IntArray,
        width: Int,
        height: Int,
        preferCard: Boolean = false,
    ): Candidate? {
        if (width < 64 || height < 64 || width > 2048 || height > 2048 ||
            width.toLong() * height > 1200000L ||
            pixels.size.toLong() != width.toLong() * height) return null
        if (!nativeAvailable) return null
        val result = try {
            detectArgbNative(pixels, width, height, preferCard)
        } catch (_: Throwable) {
            // Never allow a missing ABI / native linkage error to interrupt a scan.
            null
        }
        return validateResult(result, width, height, preferCard)
    }

    /**
     * Android-independent validation seam; JVM tests exercise JNI response
     * safety without requiring NDK .so loading on the Gradle test host.
     */
    internal fun validateResult(
        raw: FloatArray?, width: Int, height: Int, preferCard: Boolean,
    ): Candidate? {
        if (raw == null || raw.size != 10 || width < 64 || height < 64 ||
            !raw.all { it.isFinite() }) return null
        val confidence = raw[8]
        val mode = raw[9].toInt()
        if (confidence < .66f || confidence > 1.1f ||
            raw[9] != mode.toFloat() || mode !in 0..5) return null
        val points = (0..3).map { index ->
            PointF(raw[2 * index], raw[2 * index + 1])
        }
        if (points.any { it.x !in .003f..0.997f || it.y !in .003f..0.997f }) {
            return null
        }
        // Order must be TL->TR->BR->BL and strictly convex, not a text
        // line, self-intersecting polygon, or repeated corner.
        val cross = (0..3).map { i ->
            val a = points[i]
            val b = points[(i + 1) % 4]
            val c = points[(i + 2) % 4]
            (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
        }
        if (cross.any { it < .001f }) return null
        val quad = Quad(points[0], points[1], points[2], points[3])
        val area = StillCaptureCropSafety.area(quad)
        if (area !in .13..0.90) return null
        if (preferCard &&
            !StillCaptureCropSafety.isCredibleCard(quad, width, height) &&
            !(mode == 0 &&
              StillCaptureCropSafety.isCredibleColorCard(quad, width, height))) {
            return null
        }
        if (abs(points.map { it.x.toDouble() }.average() - .5) > .31 ||
            abs(points.map { it.y.toDouble() }.average() - .5) > .31) {
            return null
        }
        return Candidate(quad, confidence, mode)
    }
}
