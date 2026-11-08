package dev.doclens.doclens

import android.graphics.Bitmap
import com.docscan.scanner.DocumentBoundaryDetector
import com.docscan.scanner.ScannerTuning
import org.opencv.android.OpenCVLoader
import org.opencv.android.Utils
import org.opencv.core.CvType
import org.opencv.core.Mat
import org.opencv.imgproc.Imgproc
import kotlin.math.max
import kotlin.math.min

/**
 * Reuses the multi-stage Kotlin/OpenCV detector supplied with the working
 * DocScan Android project. The Flutter plugin continues to own CameraX,
 * preview coordinates, image capture and perspective warping.
 *
 * An adapter lives on one executor thread only. The global loader is shared;
 * the Mats inside DocumentBoundaryDetector are deliberately not shared.
 */
internal class OpenCvBoundaryAdapter {
    private var detector: DocumentBoundaryDetector? = null

    private fun engine(): DocumentBoundaryDetector? {
        if (!Loader.ready()) return null
        if (detector == null) detector = DocumentBoundaryDetector()
        return detector
    }

    /** Live CameraX Y-plane frame. Returns corners in frame coordinates. */
    fun detectLuma(luma: ByteArray, width: Int, height: Int,
                   preferIdCardBounds: Boolean = false): Quad? {
        if (width < 32 || height < 32 || luma.size < width * height) return null
        val boundaryDetector = try { engine() } catch (_: Throwable) { null } ?: return null
        val gray = Mat(height, width, CvType.CV_8UC1)
        val rgba = Mat()
        return try {
            gray.put(0, 0, luma)
            Imgproc.cvtColor(gray, rgba, Imgproc.COLOR_GRAY2RGBA)
            toNormalizedQuad(boundaryDetector.detectBoundary(rgba,
                preferIdCardBounds = preferIdCardBounds), width, height)
        } catch (_: Exception) {
            null // The original luma-only detector remains the safe fallback.
        } finally {
            gray.release()
            rgba.release()
        }
    }

    /**
     * Live YUV preview converted to a small RGBA frame. Unlike grayscale
     * replication, this lets the detector use its HSV/saturation edge pass
     * when paper and background have similar brightness but different hues.
     */
    fun detectRgba(pixels: ByteArray, width: Int, height: Int,
                   preferIdCardBounds: Boolean = false): Quad? {
        if (width < 32 || height < 32 || pixels.size != width * height * 4) {
            return null
        }
        val boundaryDetector = try { engine() } catch (_: Throwable) { null } ?: return null
        val rgba = Mat(height, width, CvType.CV_8UC4)
        return try {
            rgba.put(0, 0, pixels)
            toNormalizedQuad(boundaryDetector.detectBoundary(rgba,
                preferIdCardBounds = preferIdCardBounds), width, height)
        } catch (_: Exception) {
            null
        } finally {
            rgba.release()
        }
    }

    /** Captured still bitmap; preserves colour-dependent edge detection. */
    fun detectBitmap(bitmap: Bitmap, preferIdCardBounds: Boolean = false): Quad? {
        val boundaryDetector = try { engine() } catch (_: Throwable) { null } ?: return null
        val longest = max(bitmap.width, bitmap.height)
        if (longest < 32) return null
        val scale = min(1.0, 900.0 / longest)
        val w = max(32, (bitmap.width * scale).toInt())
        val h = max(32, (bitmap.height * scale).toInt())
        val small = if (scale == 1.0) bitmap
            else Bitmap.createScaledBitmap(bitmap, w, h, true)
        val rgba = Mat()
        return try {
            Utils.bitmapToMat(small, rgba)
            toNormalizedQuad(boundaryDetector.detectBoundary(rgba,
                preferOuterPageInStill = !preferIdCardBounds,
                preferIdCardBounds = preferIdCardBounds), w, h)
        } catch (_: Exception) {
            null
        } finally {
            rgba.release()
            if (small !== bitmap) small.recycle()
        }
    }

    fun release() {
        detector?.release()
        detector = null
    }

    companion object {
        /** Stateless wrapper for gallery and capture paths on arbitrary threads. */
        fun detectStill(bitmap: Bitmap, preferIdCardBounds: Boolean = false): Quad? {
            val adapter = OpenCvBoundaryAdapter()
            return try { adapter.detectBitmap(bitmap, preferIdCardBounds) }
                finally { adapter.release() }
        }

        private fun toNormalizedQuad(
            result: com.docscan.scanner.DocumentDetectionResult,
            width: Int,
            height: Int,
        ): Quad? {
            if (!result.isValid || result.corners.size != 4 ||
                !result.confidence.isFinite()) return null
            if (!ScannerTuning.hasFourVisibleCorners(result.corners.toTypedArray(), width, height)) {
                return null
            }
            val points = result.corners.map { point ->
                PointF(
                    (point.x / width).toFloat().coerceIn(0f, 1f),
                    (point.y / height).toFloat().coerceIn(0f, 1f),
                )
            }
            return QuadOrdering.reorderClockwise(points)
        }
    }

    private object Loader {
        @Volatile private var initialized = false
        @Volatile private var failed = false

        fun ready(): Boolean {
            if (initialized) return true
            if (failed) return false
            synchronized(this) {
                if (!initialized && !failed) {
                    try {
                        initialized = OpenCVLoader.initLocal()
                        failed = !initialized
                    } catch (_: Throwable) {
                        failed = true
                    }
                }
            }
            return initialized
        }
    }
}
