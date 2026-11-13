package dev.doclens.doclens

import android.graphics.Bitmap

/**
 * Independently authored, offline C++ enhancement in libds_pagescanner.so.
 *
 * This intentionally NEVER loads or invokes the optional CamScanner .so
 * binaries. All failures return false so ImageWarper can use its proven
 * low-memory Kotlin implementation. A limit on pixels bounds allocation.
 */
internal object NativeImageEnhancer {
    private const val MAX_PIXELS = 6_000_000L

    private val available: Boolean by lazy {
        try {
            System.loadLibrary("ds_pagescanner")
            true
        } catch (_: Throwable) {
            false
        }
    }

    private external fun enhanceArgbNative(
        pixels: IntArray,
        width: Int,
        height: Int,
        blackAndWhite: Boolean,
    ): Boolean

    fun enhanceInPlace(bitmap: Bitmap, mode: String): Boolean {
        if (mode != "enhanced" && mode != "blackAndWhite") return false
        val width = bitmap.width
        val height = bitmap.height
        if (width < 8 || height < 8 || width > 3200 || height > 3200 ||
            width.toLong() * height > MAX_PIXELS ||
            !available || !bitmap.isMutable) return false
        return try {
            val pixels = IntArray(width * height)
            bitmap.getPixels(pixels, 0, width, 0, 0, width, height)
            if (!enhanceArgbNative(pixels, width, height, mode == "blackAndWhite")) {
                false
            } else {
                bitmap.setPixels(pixels, 0, width, 0, 0, width, height)
                true
            }
        } catch (_: Throwable) {
            // Do not let unavailable ABI, memory pressure or JNI linkage
            // issues crash capture. The caller retains the Kotlin fallback.
            false
        }
    }
}
