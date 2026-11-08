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
        if (colourPanel == null || !isPlausiblePanel(colourPanel, width, height)) {
            // Several corners pinned to the camera edges are almost always
            // the frame or a clipped background surface, not a visible page.
            return contour?.takeUnless { isFrameSpanning(it) }
        }
        if (contour == null) return colourPanel
        if (isFrameSpanning(contour)) return colourPanel

        val centreDistance = hypot(
            (contour.topLeft.x + contour.topRight.x + contour.bottomRight.x +
                contour.bottomLeft.x - colourPanel.topLeft.x - colourPanel.topRight.x -
                colourPanel.bottomRight.x - colourPanel.bottomLeft.x).toDouble() / 4.0,
            (contour.topLeft.y + contour.topRight.y + contour.bottomRight.y +
                contour.bottomLeft.y - colourPanel.topLeft.y - colourPanel.topRight.y -
                colourPanel.bottomRight.y - colourPanel.bottomLeft.y).toDouble() / 4.0,
        )
        if (centreDistance > .22) return contour

        val contourArea = StillCaptureCropSafety.area(contour)
        val panelArea = StillCaptureCropSafety.area(colourPanel)
        val contourRatio = longSideRatio(contour, width, height)
        val panelRatio = longSideRatio(colourPanel, width, height)

        // The frame-wide green quad in 381536.mp4 has all four edges on the
        // camera limits while the blue cloth is fully visible inside it.
        // Prefer the independent cloth mask even if the chair accidentally
        // has a credible A4 aspect ratio.
        val borderBackground = edgeCornerCount(contour) >= 2 &&
            contourArea > panelArea * 1.20 && panelArea >= .28

        // A chair frame or desk edge can be bigger and considerably more
        // elongated than the actual document, as in 381530.mp4. Both must
        // be supported by the live pixels: area alone never decides.
        val elongatedBackground = contourArea > panelArea * 1.08 &&
            contourRatio > panelRatio * 1.32 && contourRatio > 1.70
        // Strong printed rectangles *inside* a coloured page are another
        // common false target. Do not turn this into a small-ID-card rule.
        val innerTitle = contourArea < panelArea * .42 &&
            StillCaptureCropSafety.isSuspiciousInteriorStrip(contour, width, height) &&
            StillCaptureCropSafety.encloses(colourPanel, contour)
        return if (borderBackground || elongatedBackground || innerTitle) colourPanel
            else contour
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
        return StillCaptureCropSafety.area(q) in 0.22..0.87 &&
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
