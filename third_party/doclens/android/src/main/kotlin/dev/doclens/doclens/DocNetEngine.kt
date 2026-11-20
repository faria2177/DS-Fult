package dev.doclens.doclens

import android.content.res.AssetManager

/**
 * DocNet — DocScanner's own document-mask network (tool/docnet), run by
 * libds_docnet.so on the open-source ncnn engine. 160×160 RGB in, 80×80
 * document probabilities out. Returns null whenever the library or model
 * is unavailable; callers then use the U²-Net salient model.
 */
internal object DocNetEngine {
    const val INPUT = 160
    const val OUTPUT = 80

    private var loaded: Boolean? = null

    private external fun loadNative(assets: AssetManager): Boolean
    private external fun runNative(rgb: ByteArray): FloatArray?

    @Synchronized
    fun ensureLoaded(assets: AssetManager): Boolean {
        loaded?.let { return it }
        val ok = try {
            System.loadLibrary("ds_docnet")
            loadNative(assets)
        } catch (_: Throwable) {
            false
        }
        loaded = ok
        return ok
    }

    val isLoaded: Boolean get() = loaded == true

    /** [rgb] is INPUT×INPUT×3 bytes. */
    fun run(rgb: ByteArray): FloatArray? {
        if (loaded != true || rgb.size != INPUT * INPUT * 3) return null
        return try {
            runNative(rgb)?.takeIf { it.size == OUTPUT * OUTPUT }
        } catch (_: Throwable) {
            null
        }
    }
}
