package dev.doclens.doclens

import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

/** Geometric checks that keep an interior text/table band from replacing an A4 page.
 *
 * Coordinates are normalised to the upright still/preview image. No guessed
 * corners are ever warped automatically: uncertain stills go to manual review.
 */
internal object StillCaptureCropSafety {
    fun area(quad: Quad): Double {
        val points = listOf(quad.topLeft, quad.topRight, quad.bottomRight, quad.bottomLeft)
        var sum = 0.0
        for (i in points.indices) {
            val a = points[i]
            val b = points[(i + 1) % points.size]
            sum += a.x.toDouble() * b.y - b.x.toDouble() * a.y
        }
        return abs(sum) * .5
    }

    private fun edgeLength(a: PointF, b: PointF, width: Int, height: Int): Double =
        hypot((a.x - b.x) * width.toDouble(), (a.y - b.y) * height.toDouble())

    private fun sideLengths(quad: Quad, width: Int, height: Int): Pair<Double, Double> {
        val horizontal = (edgeLength(quad.topLeft, quad.topRight, width, height) +
            edgeLength(quad.bottomLeft, quad.bottomRight, width, height)) * .5
        val vertical = (edgeLength(quad.topLeft, quad.bottomLeft, width, height) +
            edgeLength(quad.topRight, quad.bottomRight, width, height)) * .5
        return horizontal to vertical
    }

    /** A live quad that can seed a review if the still chooses an inner table. */
    fun isCrediblePage(quad: Quad, width: Int, height: Int): Boolean {
        if (width <= 0 || height <= 0) return false
        val points = listOf(quad.topLeft, quad.topRight, quad.bottomRight, quad.bottomLeft)
        if (points.any { it.x !in 0.0f..1.0f || it.y !in 0.0f..1.0f }) return false
        val coverage = area(quad)
        val (w, h) = sideLengths(quad, width, height)
        val aspect = max(w, h) / min(w, h).coerceAtLeast(1.0)
        return coverage in .30..0.94 && aspect in 1.12..1.89
    }

    /** Horizontal letter body on a portrait still: never make it the saved page. */
    fun isSuspiciousInteriorStrip(quad: Quad, width: Int, height: Int): Boolean {
        if (width <= 0 || height <= width * 1.10) return false
        val (w, h) = sideLengths(quad, width, height)
        val isLandscapeStrip = w > h * 1.58
        return isLandscapeStrip && area(quad) < .73
    }

    fun compatibleView(previewWidth: Int, previewHeight: Int,
                       stillWidth: Int, stillHeight: Int): Boolean {
        if (previewWidth <= 0 || previewHeight <= 0 ||
            stillWidth <= 0 || stillHeight <= 0) return false
        val previewAspect = previewWidth.toDouble() / previewHeight
        val stillAspect = stillWidth.toDouble() / stillHeight
        return abs(previewAspect - stillAspect) / previewAspect <= .085
    }

    fun significantlySmallerThan(still: Quad, preview: Quad): Boolean =
        area(still) < area(preview) * .64

    /** Keep accurate CV corners unless the independent mask clearly recovers a page. */
    fun shouldPreferPaperMask(
        still: Quad, mask: Quad, width: Int, height: Int,
    ): Boolean {
        if (!isCrediblePage(mask, width, height)) return false
        val stillArea = area(still)
        val needsRecovery = stillArea < .28 ||
            isSuspiciousInteriorStrip(still, width, height) ||
            !isCrediblePage(still, width, height)
        val minimumGrowth = if (needsRecovery) 1.35 else 1.85
        return area(mask) > stillArea * minimumGrowth
    }
}
