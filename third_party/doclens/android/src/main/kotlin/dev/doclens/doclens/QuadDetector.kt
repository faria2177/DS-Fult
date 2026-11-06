package dev.doclens.doclens

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min


/**
 * Document quadrilateral detector that runs entirely on a downscaled
 * luma buffer. Strategy:
 *
 * 1. Compute mean luma; build a mask of the pixels on the document's side of
 *    that mean — brighter (paper, the default), darker (a dark ID card or a
 *    colored trading card on a light desk), or whichever of the two looks
 *    more document-like ([DetectionPolarity.AUTO]).
 * 2. Keep several substantial connected components. A brightly lit table,
 *    blanket or video-call overlay can be larger than the document.
 * 3. Score convex quadrilateral candidates for solidity, on-screen size,
 *    isolation from frame borders, and proximity to the preview centre.
 *
 * Returns normalized `[0,1]` coordinates in `topLeft → topRight → bottomRight
 * → bottomLeft` order on the input buffer's frame (orientation handled by
 * caller).
 *
 * v0.1 deliberately avoids OpenCV and ML Kit (see docs/decisions.md).
 */
object QuadDetector {
    /**
     * Luma bias applied on top of the frame mean when thresholding. Keeps the
     * mask off the noise floor around the mean, where a flat surface's own
     * gradient would otherwise carve out shapes.
     */
    const val DEFAULT_THRESHOLD_OFFSET = 20

    /**
     * Largest bias worth honouring. Past this the clamps in [buildMask] pin
     * the threshold to its extremes, so a larger offset changes nothing.
     */
    private const val MAX_THRESHOLD_OFFSET = 128

    fun detect(
        luma: ByteArray,
        width: Int,
        height: Int,
        polarity: DetectionPolarity = DetectionPolarity.BRIGHTER,
        thresholdOffset: Int = DEFAULT_THRESHOLD_OFFSET,
    ): Quad? {
        if (width < 16 || height < 16) return null
        val offset = thresholdOffset.coerceIn(0, MAX_THRESHOLD_OFFSET)
        return when (polarity) {
            DetectionPolarity.BRIGHTER ->
                analyze(luma, width, height, darker = false, offset = offset)?.quad
            DetectionPolarity.DARKER ->
                analyze(luma, width, height, darker = true, offset = offset)?.quad
            DetectionPolarity.AUTO -> {
                val bright = analyze(luma, width, height, darker = false, offset = offset)
                val dark = analyze(luma, width, height, darker = true, offset = offset)
                when {
                    bright == null -> dark?.quad
                    dark == null -> bright.quad
                    dark.score > bright.score -> dark.quad
                    else -> bright.quad
                }
            }
        }
    }

    /** The best non-border, document-shaped component at one polarity. */
    private class Candidate(val quad: Quad, val score: Float)

    /**
     * A connected component extending off the preview edge is often the desk
     * or a background object, not the document. Never let the biggest blob
     * prevent a smaller, central, closed quadrilateral from being considered.
     */
    private fun analyze(
        luma: ByteArray,
        width: Int,
        height: Int,
        darker: Boolean,
        offset: Int,
    ): Candidate? {
        val mask = buildMask(luma, darker, offset)
        var best: Candidate? = null
        for (component in largestComponents(mask, width, height)) {
            val boundary = traceBoundary(component, width, height) ?: continue
            val hull = convexHull(boundary)
            if (hull.size < 4) continue
            val corners = approximateQuad(hull) ?: continue
            val score = documentScore(component, corners, width, height)
            if (score <= 0f) continue
            if (best == null || score > best.score) {
                best = Candidate(
                    normalizeAndOrder(corners, width.toFloat(), height.toFloat()),
                    score,
                )
            }
        }
        return best
    }

    /**
     * Give a central, closed card a chance against a larger bright background.
     *
     * - **solidity** — component pixels over its own quad's area. A document
     *   fills its quad; the surface *around* a document does not, because the
     *   document is a hole punched in it.
     * - **borderFraction** — the share of the frame's outer ring the component
     *   owns. The surface a document lies on runs off every edge of the frame;
     *   the document itself usually does not.
     * - **coverage** — saturates once a candidate is comfortably readable;
     *   a large foreground region must not always beat a smaller ID card.
     * - **centrality** — prefers the document being framed over a bright
     *   distraction in a corner, without requiring a perfectly centred page.
     */
    private fun documentScore(
        component: IntArray,
        corners: List<PointF>,
        width: Int,
        height: Int,
    ): Float {
        val area = polygonArea(corners)
        if (area <= 0f) return 0f
        val solidity = (component.size / area).coerceIn(0f, 1f)
        val coverage = (area / (width * height).toFloat()).coerceIn(0f, 1f)
        if (coverage < 0.02f || coverage > 0.96f || solidity < 0.45f) return 0f
        val quadWidth = (corners.maxOf { it.x } - corners.minOf { it.x })
        val quadHeight = (corners.maxOf { it.y } - corners.minOf { it.y })
        if (quadHeight <= 0f || quadWidth / quadHeight !in 0.22f..5f) return 0f
        var onBorder = 0
        for (idx in component) {
            val x = idx % width
            val y = idx / width
            if (x == 0 || y == 0 || x == width - 1 || y == height - 1) onBorder++
        }
        val borderTotal = (2 * width + 2 * height - 4).coerceAtLeast(1)
        val borderFraction = (onBorder.toFloat() / borderTotal).coerceIn(0f, 1f)
        val cx = corners.sumOf { it.x.toDouble() }.toFloat() / (corners.size * width)
        val cy = corners.sumOf { it.y.toDouble() }.toFloat() / (corners.size * height)
        val centrality = (1f - (abs(cx - .5f) + abs(cy - .5f))).coerceIn(0f, 1f)
        val sizeScore = (coverage / .15f).coerceIn(0f, 1f)
        return solidity * (1f - .9f * borderFraction) *
            (.40f + .35f * centrality + .25f * sizeScore)
    }

    /** Shoelace area of a polygon in pixel space. */
    private fun polygonArea(pts: List<PointF>): Float {
        var sum = 0f
        for (i in pts.indices) {
            val a = pts[i]
            val b = pts[(i + 1) % pts.size]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2f
    }

    /**
     * Run [detect] on a still image already on disk (e.g. one imported from
     * the gallery). Decodes the file, bakes in any EXIF orientation, then
     * detects on a downscaled luma copy — the normalized quad is
     * resolution-independent, so the downscale only affects speed.
     *
     * [polarity] and [thresholdOffset] carry the same meaning as on [detect];
     * callers pass the session's `ScannerConfig` values so an imported photo
     * segments exactly the way the live preview does.
     *
     * Returns a map of `{ "quad": <normalized quad map> | null, "imageSize":
     * [width, height] }` in the EXIF-upright pixel space (the same space the
     * warp operates in). Throws [ScannerException.CaptureFailed] when the file
     * cannot be decoded.
     */
    fun detectInFile(
        path: String,
        polarity: DetectionPolarity = DetectionPolarity.BRIGHTER,
        thresholdOffset: Int = DEFAULT_THRESHOLD_OFFSET,
    ): Map<String, Any?> {
        val raw = BitmapFactory.decodeFile(path)
            ?: throw ScannerException.CaptureFailed("Decode failed: $path")
        val upright = ExifRotator.rotated(raw, path)
        try {
            val w = upright.width
            val h = upright.height
            // Downscale for detection; the largest side caps at ~480 px. The
            // detector emits normalized [0,1] coords, so this is purely a
            // speed/memory optimisation and doesn't affect the result space.
            val target = 480
            val scale = min(1.0, target.toDouble() / max(w, h))
            val dw = max(16, (w * scale).toInt())
            val dh = max(16, (h * scale).toInt())
            val small = if (dw == w && dh == h) upright
                        else Bitmap.createScaledBitmap(upright, dw, dh, true)
            val pixels = IntArray(dw * dh)
            small.getPixels(pixels, 0, dw, 0, 0, dw, dh)
            if (small !== upright) small.recycle()

            val luma = ByteArray(dw * dh)
            for (i in pixels.indices) {
                val p = pixels[i]
                val r = (p shr 16) and 0xFF
                val g = (p shr 8) and 0xFF
                val b = p and 0xFF
                // Rec.601 luma, integer weights (77/150/29 ≈ /256).
                luma[i] = (((r * 77 + g * 150 + b * 29) shr 8) and 0xFF).toByte()
            }

            val quad = detect(luma, dw, dh, polarity, thresholdOffset)
            return mapOf(
                "quad" to quad?.toMap(),
                "imageSize" to listOf(w.toDouble(), h.toDouble()),
            )
        } finally {
            if (upright !== raw) upright.recycle()
            raw.recycle()
        }
    }

    /**
     * Threshold the frame around its own mean luma, biased by [offset] onto
     * the side the document is expected to be on.
     *
     * With [darker] false this is the original paper-bright rule: keep pixels
     * above `mean + offset`. With [darker] true it is its mirror image: keep
     * pixels below `mean - offset`, so a dark ID card or a saturated trading
     * card on a light desk becomes the component instead of the desk. The
     * clamps mirror too (`60..220` becomes `35..195`), keeping the mask off
     * the extremes where a blown-out or crushed frame yields nothing usable.
     */
    private fun buildMask(luma: ByteArray, darker: Boolean, offset: Int): BooleanArray {
        var sum = 0L
        for (b in luma) sum += b.toInt() and 0xFF
        val mean = (sum / luma.size).toInt()
        val mask = BooleanArray(luma.size)
        if (darker) {
            val threshold = (mean - offset).coerceIn(35, 195)
            for (i in luma.indices) {
                mask[i] = (luma[i].toInt() and 0xFF) < threshold
            }
        } else {
            val threshold = (mean + offset).coerceIn(60, 220)
            for (i in luma.indices) {
                mask[i] = (luma[i].toInt() and 0xFF) > threshold
            }
        }
        return mask
    }

    /** Keep the largest viable blobs rather than only the single biggest. */
    private fun largestComponents(
        mask: BooleanArray, w: Int, h: Int, maxCandidates: Int = 12,
    ): List<IntArray> {
        val labels = IntArray(mask.size) { -1 }
        val candidates = ArrayList<IntArray>(maxCandidates)
        val minimumSize = (w * h / 50).coerceAtLeast(4)
        val stack = IntArray(mask.size)
        // One scratch buffer for every component, copied out only when a
        // component turns out to be the largest so far. A darker-polarity
        // mask over a page of text yields hundreds of small components, and
        // a full-size allocation per component is real GC pressure at 15 Hz.
        val collected = IntArray(mask.size)
        for (start in mask.indices) {
            if (!mask[start] || labels[start] != -1) continue
            // BFS / flood fill iterative.
            var top = 0
            stack[top++] = start
            labels[start] = start
            var collectedSize = 0
            while (top > 0) {
                val idx = stack[--top]
                collected[collectedSize++] = idx
                val x = idx % w
                val y = idx / w
                val neighbors = intArrayOf(
                    if (x > 0) idx - 1 else -1,
                    if (x < w - 1) idx + 1 else -1,
                    if (y > 0) idx - w else -1,
                    if (y < h - 1) idx + w else -1,
                )
                for (n in neighbors) {
                    if (n >= 0 && mask[n] && labels[n] == -1) {
                        labels[n] = start
                        stack[top++] = n
                    }
                }
            }
            if (collectedSize >= minimumSize &&
                (candidates.size < maxCandidates ||
                    collectedSize > candidates.last().size)) {
                val component = collected.copyOf(collectedSize)
                val pos = candidates.indexOfFirst { it.size < collectedSize }
                if (pos == -1) candidates.add(component)
                else candidates.add(pos, component)
                if (candidates.size > maxCandidates) candidates.removeAt(candidates.lastIndex)
            }
        }
        return candidates
    }

    private fun traceBoundary(component: IntArray, w: Int, h: Int): List<PointF>? {
        // A pixel is a boundary if any of its 4-neighbors is NOT in the component.
        val inComp = BooleanArray(w * h)
        for (idx in component) inComp[idx] = true
        val result = ArrayList<PointF>(component.size / 4 + 8)
        for (idx in component) {
            val x = idx % w
            val y = idx / w
            val isBoundary =
                x == 0 || y == 0 || x == w - 1 || y == h - 1 ||
                !inComp[idx - 1] || !inComp[idx + 1] ||
                !inComp[idx - w] || !inComp[idx + w]
            if (isBoundary) result.add(PointF(x.toFloat(), y.toFloat()))
        }
        return if (result.size < 4) null else result
    }

    private fun convexHull(points: List<PointF>): List<PointF> {
        if (points.size < 3) return points
        val sorted = points.sortedWith(compareBy({ it.x }, { it.y }))
        val lower = ArrayList<PointF>()
        for (p in sorted) {
            while (lower.size >= 2 && cross(lower[lower.size - 2], lower[lower.size - 1], p) <= 0)
                lower.removeAt(lower.size - 1)
            lower.add(p)
        }
        val upper = ArrayList<PointF>()
        for (p in sorted.reversed()) {
            while (upper.size >= 2 && cross(upper[upper.size - 2], upper[upper.size - 1], p) <= 0)
                upper.removeAt(upper.size - 1)
            upper.add(p)
        }
        if (lower.isNotEmpty()) lower.removeAt(lower.size - 1)
        if (upper.isNotEmpty()) upper.removeAt(upper.size - 1)
        return lower + upper
    }

    private fun cross(O: PointF, A: PointF, B: PointF): Float =
        (A.x - O.x) * (B.y - O.y) - (A.y - O.y) * (B.x - O.x)

    /**
     * Reduce a convex hull to its 4 dominant corners by picking the hull
     * points that extremize (x+y), (x-y), -(x+y), -(x-y) — these are the
     * TL, TR, BR, BL extents for any near-rectangular hull, robust to
     * orientation jitter.
     */
    private fun approximateQuad(hull: List<PointF>): List<PointF>? {
        if (hull.size < 4) return null
        var tl = hull[0]; var tr = hull[0]; var br = hull[0]; var bl = hull[0]
        var tlScore = Float.POSITIVE_INFINITY
        var brScore = Float.NEGATIVE_INFINITY
        var trScore = Float.NEGATIVE_INFINITY
        var blScore = Float.POSITIVE_INFINITY
        for (p in hull) {
            val sum = p.x + p.y
            val diff = p.x - p.y
            if (sum < tlScore) { tlScore = sum; tl = p }
            if (sum > brScore) { brScore = sum; br = p }
            if (diff > trScore) { trScore = diff; tr = p }
            if (diff < blScore) { blScore = diff; bl = p }
        }
        // Ensure non-degenerate (no two corners coincide).
        val set = setOf(tl, tr, br, bl)
        if (set.size < 4) return null
        return listOf(tl, tr, br, bl)
    }

    private fun normalizeAndOrder(pts: List<PointF>, w: Float, h: Float): Quad {
        val normalized = pts.map { PointF(it.x / w, it.y / h) }
        return QuadOrdering.reorderClockwise(normalized)
    }
}

object QuadOrdering {
    /** Orders 4 points into TL/TR/BR/BL based on sum and difference heuristics. */
    fun reorderClockwise(pts: List<PointF>): Quad {
        require(pts.size == 4)
        val sumSorted = pts.sortedBy { it.x + it.y }
        val tl = sumSorted.first()
        val br = sumSorted.last()
        val remaining = pts - tl - br
        val (tr, bl) = if (remaining[0].x > remaining[1].x) remaining[0] to remaining[1]
                       else remaining[1] to remaining[0]
        return Quad(tl, tr, br, bl)
    }
}
