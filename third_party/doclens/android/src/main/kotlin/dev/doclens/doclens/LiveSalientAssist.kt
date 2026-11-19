package dev.doclens.doclens

import org.opencv.core.CvType
import org.opencv.core.Mat
import org.opencv.core.MatOfPoint
import org.opencv.core.MatOfPoint2f
import org.opencv.core.Size
import org.opencv.imgproc.Imgproc
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.abs
import kotlin.math.hypot

/**
 * Whole-object outline for the live camera, from the bundled U²-Net
 * salient-object model (the same model the gallery import uses).
 *
 * The edge/contrast detector finds the bright, clean part of a card very
 * reliably but can stop at an inner boundary when the rest of the card is
 * dark: on 386217.jpg (bank ID card, dark blue top, white bottom, lying on a
 * patterned cloth) the green box covered only the white lower half. The
 * salient model sees the card as one object regardless of its colours.
 *
 * It is too slow for every frame, so it runs on its own thread at most a
 * few times per second on a copy of the frame; the newest result is only
 * used while it is fresh. It never replaces a good edge outline on its own:
 * see [combine].
 */
internal class LiveSalientAssist {
    @Volatile var modelPath: String? = null

    private val worker = Executors.newSingleThreadExecutor()
    private val busy = AtomicBoolean(false)
    @Volatile private var lastStart = 0L
    @Volatile private var latest: Pair<Quad, Long>? = null

    /** Offer the current RGBA analysis frame; returns immediately. */
    fun offer(rgba: ByteArray, width: Int, height: Int, now: Long) {
        val model = modelPath ?: return
        if (now - lastStart < INTERVAL_MS || !busy.compareAndSet(false, true)) return
        lastStart = now
        val copy = rgba.copyOf()
        try {
            worker.execute {
                try {
                    val quad = detect(model, copy, width, height)
                    latest = quad?.let { it to System.currentTimeMillis() }
                } catch (_: Throwable) {
                    latest = null
                } finally {
                    busy.set(false)
                }
            }
        } catch (_: Throwable) {
            busy.set(false)
        }
    }

    /** The newest outline if it is recent enough to describe this frame. */
    fun fresh(now: Long): Quad? = latest?.takeIf { now - it.second <= MAX_AGE_MS }?.first

    fun dispose() {
        modelPath = null
        latest = null
        worker.shutdownNow()
    }

    private fun detect(model: String, rgba: ByteArray, width: Int, height: Int): Quad? {
        val probability = SalientMaskEngine.probabilityForRgba(model, rgba, width, height)
            ?: return null
        return quadFromMask(probability, SalientMaskEngine.SIDE, width, height)
    }

    companion object {
        private const val INTERVAL_MS = 450L
        private const val MAX_AGE_MS = 1100L

        /**
         * Largest confident object in the 320×320 probability map as a
         * four-cornered outline in normalized frame coordinates, or null when
         * the object is not a flat rectangle (a person, a bag, a crumpled
         * cloth) or touches the frame edge on several sides.
         */
        fun quadFromMask(probability: ByteArray, side: Int, width: Int, height: Int): Quad? {
            val mask = Mat(side, side, CvType.CV_8UC1)
            val big = Mat()
            val hierarchy = Mat()
            val contours = ArrayList<MatOfPoint>()
            try {
                mask.put(0, 0, probability)
                Imgproc.threshold(mask, mask, 127.0, 255.0, Imgproc.THRESH_BINARY)
                // Back to the frame's aspect so angles and areas are true.
                Imgproc.resize(mask, big, Size(width.toDouble(), height.toDouble()),
                    0.0, 0.0, Imgproc.INTER_LINEAR)
                Imgproc.threshold(big, big, 127.0, 255.0, Imgproc.THRESH_BINARY)
                Imgproc.findContours(big, contours, hierarchy,
                    Imgproc.RETR_EXTERNAL, Imgproc.CHAIN_APPROX_SIMPLE)
                val largest = contours.maxByOrNull { Imgproc.contourArea(it) } ?: return null
                val objectArea = Imgproc.contourArea(largest)
                val frameArea = width.toDouble() * height
                if (objectArea < frameArea * .03 || objectArea > frameArea * .88) return null

                val curve = MatOfPoint2f(*largest.toArray())
                val perimeter = Imgproc.arcLength(curve, true)
                var corners: Array<org.opencv.core.Point>? = null
                for (epsilon in doubleArrayOf(.02, .03, .045, .06)) {
                    val approx = MatOfPoint2f()
                    Imgproc.approxPolyDP(curve, approx, perimeter * epsilon, true)
                    val points = approx.toArray()
                    approx.release()
                    if (points.size == 4) {
                        corners = points
                        break
                    }
                }
                curve.release()
                val found = corners ?: return null
                val quad = QuadOrdering.reorderClockwise(found.map {
                    PointF((it.x / width).toFloat().coerceIn(0f, 1f),
                        (it.y / height).toFloat().coerceIn(0f, 1f))
                })
                // The object must fill its outline: a rectangle, not a blob.
                val quadArea = StillCaptureCropSafety.area(quad) * frameArea
                if (quadArea <= 0 || objectArea / quadArea < .88) return null
                if (!LiveBoundarySelector.hasFourPageLikeSides(quad, width, height)) return null
                if (!hasRightishAngles(quad, width, height)) return null
                val onEdge = listOf(quad.topLeft, quad.topRight, quad.bottomRight,
                    quad.bottomLeft).count {
                    it.x <= .01f || it.x >= .99f || it.y <= .01f || it.y >= .99f
                }
                if (onEdge >= 2) return null
                return quad
            } finally {
                mask.release()
                big.release()
                hierarchy.release()
                contours.forEach { it.release() }
            }
        }

        private fun hasRightishAngles(q: Quad, width: Int, height: Int): Boolean {
            val p = listOf(q.topLeft, q.topRight, q.bottomRight, q.bottomLeft)
            for (i in 0 until 4) {
                val a = p[(i + 3) % 4]
                val b = p[i]
                val c = p[(i + 1) % 4]
                val ux = (a.x - b.x).toDouble() * width
                val uy = (a.y - b.y).toDouble() * height
                val vx = (c.x - b.x).toDouble() * width
                val vy = (c.y - b.y).toDouble() * height
                val cos = (ux * vx + uy * vy) / (hypot(ux, uy) * hypot(vx, vy))
                if (abs(cos) > .45) return false // outside ~63°..117°
            }
            return true
        }

        /**
         * Decide what the live green box shows.
         *
         * * no edge outline → the model's outline;
         * * edge outline lies inside a clearly bigger model outline → the
         *   edge detector stopped at an inner boundary (dark half of a card,
         *   a photo or a printed panel): use the model's whole object;
         * * otherwise keep the edge outline, which has sharper corners.
         */
        fun combine(edge: Quad?, salient: Quad?): Quad? {
            if (salient == null) return edge
            if (edge == null) return salient
            val edgeArea = StillCaptureCropSafety.area(edge)
            val salientArea = StillCaptureCropSafety.area(salient)
            if (salientArea < edgeArea * 1.22) return edge
            // The partial edge box may poke a little past the object (it
            // follows a skewed inner line), so ask how much of it lies
            // inside rather than requiring strict containment.
            return if (insideFraction(edge, salient) >= .80) salient else edge
        }

        /** Share of [inner]'s surface that lies inside [outer] (sampled). */
        internal fun insideFraction(inner: Quad, outer: Quad): Double {
            val n = 14
            var inside = 0
            for (i in 0 until n) {
                for (j in 0 until n) {
                    val u = (i + .5f) / n
                    val v = (j + .5f) / n
                    val top = lerp(inner.topLeft, inner.topRight, u)
                    val bottom = lerp(inner.bottomLeft, inner.bottomRight, u)
                    if (contains(outer, lerp(top, bottom, v))) inside++
                }
            }
            return inside.toDouble() / (n * n)
        }

        private fun lerp(a: PointF, b: PointF, t: Float) =
            PointF(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)

        private fun contains(q: Quad, p: PointF): Boolean {
            val pts = listOf(q.topLeft, q.topRight, q.bottomRight, q.bottomLeft)
            var sign = 0
            for (i in 0 until 4) {
                val a = pts[i]
                val b = pts[(i + 1) % 4]
                val cross = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
                val s = if (cross > 0) 1 else if (cross < 0) -1 else 0
                if (s != 0) {
                    if (sign == 0) sign = s else if (s != sign) return false
                }
            }
            return true
        }
    }
}
