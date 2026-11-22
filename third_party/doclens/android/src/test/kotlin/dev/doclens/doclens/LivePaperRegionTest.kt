package dev.doclens.doclens

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class LivePaperRegionTest {
    private fun rect(left: Float, top: Float, right: Float, bottom: Float) = Quad(
        PointF(left, top), PointF(right, top),
        PointF(right, bottom), PointF(left, bottom),
    )

    // 386769.mp4, frame 40: visible paper measured by libds_scannercore on
    // the preview (the sheet runs off the left and bottom of the frame).
    private val paper = Quad(
        PointF(0f, .033f), PointF(.943f, .036f),
        PointF(1f, .869f), PointF(0f, 1f),
    )

    @Test
    fun skewedQuadThroughTheTextGivesWayToTheVisiblePaper() {
        // The green box of the same frame: top and right on the paper,
        // left and bottom sides drawn through the writing.
        val skewed = Quad(
            PointF(.216f, .016f), PointF(.951f, .034f),
            PointF(.863f, .672f), PointF(.149f, .679f),
        )
        assertEquals(paper, LivePaperRegion.choose(skewed, paper, 288, 384))
    }

    @Test
    fun textBlockInsideThePageGivesWayToThePaper() {
        val table = rect(.10f, .25f, .86f, .66f)
        assertEquals(paper, LivePaperRegion.choose(table, paper, 288, 384))
    }

    @Test
    fun noRectangleStillShowsThePaper() {
        assertEquals(paper, LivePaperRegion.choose(null, paper, 288, 384))
    }

    @Test
    fun smallCardOnASheetKeepsItsOwnOutline() {
        val card = rect(.30f, .40f, .70f, .62f)
        assertEquals(card, LivePaperRegion.choose(card, paper, 288, 384))
    }

    @Test
    fun completePageInsideTheFrameIsNotReplaced() {
        // A fully visible page: the paper region is about the same size.
        val page = rect(.05f, .06f, .95f, .93f)
        val visible = rect(.04f, .05f, .96f, .94f)
        assertFalse(LivePaperRegion.isLivePaper(visible, 288, 384))
        assertEquals(page, LivePaperRegion.choose(page, visible, 288, 384))
    }

    @Test
    fun onlyBigPageShapedRegionsThatRunOffTheFrameQualify() {
        assertTrue(LivePaperRegion.isLivePaper(paper, 288, 384))
        // Whole frame: nothing to show.
        assertFalse(LivePaperRegion.isLivePaper(rect(0f, 0f, 1f, 1f), 288, 384))
        // Thin strip along the bottom edge.
        assertFalse(LivePaperRegion.isLivePaper(rect(0f, .70f, 1f, 1f), 288, 384))
    }

    @Test
    fun aDifferentObjectBesideThePaperIsKept() {
        // Mostly outside the sheet: not an inner box of it.
        val other = rect(.55f, .05f, .99f, .70f)
        val leftSheet = Quad(
            PointF(0f, .10f), PointF(.50f, .12f),
            PointF(.52f, 1f), PointF(0f, 1f),
        )
        assertEquals(other, LivePaperRegion.choose(other, leftSheet, 288, 384))
    }
}
