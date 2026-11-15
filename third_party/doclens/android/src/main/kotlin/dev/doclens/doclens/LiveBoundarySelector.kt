package dev.doclens.doclens

import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

/**
 * Keeps a strong background rectangle from displacing a coloured document.
 * This only compares two independently observed boundaries in the *same*
 * analysis frame. It does not synthesize corners or reuse a stale camera quad.
 */
internal object LiveBoundarySelector {
    fun choose(contour: Quad?, colourPanel: Quad?, width: Int, height: Int): Quad? {
        // A notebook with a bright diagonal stripe and densely drawn lines
        // can yield a valid *convex* contour of one triangular coloured
        // section. It is not the four outer notebook corners. Require
        // moderately balanced opposite sides before showing the GREEN box.
        // This is a camera-preview selector only (never changes imports).
        val outside = contour?.takeIf { hasFourPageLikeSides(it, width, height) }
        if (colourPanel == null || !isPlausiblePanel(colourPanel, width, height)) {
            // Several corners pinned to the camera edges are almost always
            // the frame or a clipped background surface, not a visible page.
            return outside?.takeUnless { isFrameSpanning(it) }
        }
        if (outside == null || isFrameSpanning(outside)) return colourPanel

        val centreDistance = hypot(
            (outside.topLeft.x + outside.topRight.x + outside.bottomRight.x +
                outside.bottomLeft.x - colourPanel.topLeft.x - colourPanel.topRight.x -
                colourPanel.bottomRight.x - colourPanel.bottomLeft.x).toDouble() / 4.0,
            (outside.topLeft.y + outside.topRight.y + outside.bottomRight.y +
                outside.bottomLeft.y - colourPanel.topLeft.y - colourPanel.topRight.y -
                colourPanel.bottomRight.y - colourPanel.bottomLeft.y).toDouble() / 4.0,
        )
        if (centreDistance > .22) return outside

        val contourArea = StillCaptureCropSafety.area(outside)
        val panelArea = StillCaptureCropSafety.area(colourPanel)
        val contourRatio = longSideRatio(outside, width, height)
        val panelRatio = longSideRatio(colourPanel, width, height)

        // The frame-wide green quad in 381536.mp4 has all four edges on the
        // camera limits while the blue cloth is fully visible inside it.
        // Prefer the independent cloth mask even if the chair accidentally
        // has a credible A4 aspect ratio.
        val borderBackground = edgeCornerCount(outside) >= 2 &&
            contourArea > panelArea * 1.20 && panelArea >= .28

        // A chair frame or desk edge can be bigger and considerably more
        // elongated than the actual document, as in 381530.mp4. Both must
        // be supported by the live pixels: area alone never decides.
        val elongatedBackground = contourArea > panelArea * 1.08 &&
            contourRatio > panelRatio * 1.32 && contourRatio > 1.70
        // Strong printed rectangles *inside* a coloured page are another
        // common false target. Do not turn this into a small-ID-card rule.
        val innerTitle = contourArea < panelArea * .42 &&
            StillCaptureCropSafety.isSuspiciousInteriorStrip(outside, width, height) &&
            StillCaptureCropSafety.encloses(colourPanel, outside)
        return if (borderBackground || elongatedBackground || innerTitle) colourPanel
            else outside
    }

    /**
     * Opposite lengths of a genuine flat page should be reasonably similar,
     * even with ordinary handheld perspective. The diagonal interior colour
     * area in the user's notebook screenshots has a tiny top side compared
     * with its bottom (or a tiny left side compared with its right).
     * Filtering this partial region is safer than offering a green box that
     * would permanently clip writing. A strongly foreshortened page can
     * still be adjusted manually.
     */
    internal fun hasFourPageLikeSides(q: Quad, width: Int, height: Int): Boolean {
        if (width <= 0 || height <= 0) return false
        val points = listOf(q.topLeft, q.topRight, q.bottomRight, q.bottomLeft)
        if (points.any { !it.x.isFinite() || !it.y.isFinite() ||
                it.x !in 0f..1f || it.y !in 0f..1f }) return false
        fun length(a: PointF, b: PointF) = hypot(
            (a.x - b.x).toDouble() * width, (a.y - b.y).toDouble() * height)
        val top = length(q.topLeft, q.topRight)
        val right = length(q.topRight, q.bottomRight)
        val bottom = length(q.bottomLeft, q.bottomRight)
        val left = length(q.topLeft, q.bottomLeft)
        if (min(top, bottom) < max(top, bottom) * .50 ||
            min(left, right) < max(left, right) * .50) return false
        return StillCaptureCropSafety.area(q) >= .04
    }

    private fun edgeCornerCount(q: Quad): Int =
        listOf(q.topLeft, q.topRight, q.bottomRight, q.bottomLeft).count {
            it.x <= .020f || it.x >= .980f || it.y <= .020f || it.y >= .980f
        }

    private fun isFrameSpanning(q: Quad): Boolean =
        StillCaptureCropSafety.area(q) > .53 && edgeCornerCount(q) >= 3

    private fun isPlausiblePanel(q: Quad, width: Int, height: Int): Boolean {
        if (width <= 0 || height <= 0) return false
        val points = listOf(q.topLeft, q.topRight, q.bottomRight, q.bottomLeft)
        if (points.any { !it.x.isFinite() || !it.y.isFinite() ||
                it.x !in 0.015f..0.985f || it.y !in 0.015f..0.985f }) return false
        return hasFourPageLikeSides(q, width, height) &&
            StillCaptureCropSafety.area(q) in 0.22..0.87 &&
            longSideRatio(q, width, height) in 1.03..2.45
    }

    private fun longSideRatio(q: Quad, width: Int, height: Int): Double {
        fun distance(a: PointF, b: PointF) = hypot(
            (a.x - b.x).toDouble() * width, (a.y - b.y).toDouble() * height)
        val w = (distance(q.topLeft, q.topRight) +
            distance(q.bottomLeft, q.bottomRight)) / 2
        val h = (distance(q.topLeft, q.bottomLeft) +
            distance(q.topRight, q.bottomRight)) / 2
        return max(w, h) / min(w, h).coerceAtLeast(1.0)
    }
}
