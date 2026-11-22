package dev.doclens.doclens

/**
 * Live green box for a page photographed from close up (386769.mp4).
 *
 * The sheet fills most of the preview and runs off the bottom of the frame,
 * so the rectangle detectors never see four paper corners. They locked onto
 * the printed table, or onto a skewed quad whose left and bottom sides ran
 * through the text, and the box kept jumping. The visible paper itself
 * (libds_scannercore.so, the same detector the gallery import uses) is the
 * page: its corners may lie on the frame edge, like CamScanner's box.
 *
 * Pure geometry so it is unit-tested on the JVM.
 */
internal object LivePaperRegion {
    /** How long a paper outline may bridge a frame where it was not found. */
    const val HOLD_MS = 600L

    /**
     * True when [paper] is a usable live outline: a big, page-shaped region
     * that runs off the frame (otherwise the rectangle detectors, which have
     * sharper corners, already handle the page).
     */
    fun isLivePaper(paper: Quad, width: Int, height: Int): Boolean {
        val area = StillCaptureCropSafety.area(paper)
        if (area !in .30..0.96) return false
        if (!LiveBoundarySelector.hasFourPageLikeSides(paper, width, height)) return false
        return cornersOnFrame(paper) >= 2
    }

    /**
     * Decide between the rectangle detector's outline [edge] and the visible
     * [paper] region of the same frame. The paper wins only when the edge
     * outline is missing, or lies inside a clearly bigger sheet (a table,
     * a text block, or a quad drawn through the writing). A small card or
     * receipt lying on a sheet keeps its own outline.
     */
    fun choose(edge: Quad?, paper: Quad?, width: Int, height: Int): Quad? {
        if (paper == null || !isLivePaper(paper, width, height)) return edge
        if (edge == null) return paper
        val edgeArea = StillCaptureCropSafety.area(edge)
        val paperArea = StillCaptureCropSafety.area(paper)
        if (edgeArea < .30) return edge
        if (paperArea < edgeArea * 1.20) return edge
        return if (LiveSalientAssist.insideFraction(edge, paper) >= .85) paper else edge
    }

    private fun cornersOnFrame(q: Quad): Int =
        listOf(q.topLeft, q.topRight, q.bottomRight, q.bottomLeft).count {
            it.x <= .02f || it.x >= .98f || it.y <= .02f || it.y >= .98f
        }
}
