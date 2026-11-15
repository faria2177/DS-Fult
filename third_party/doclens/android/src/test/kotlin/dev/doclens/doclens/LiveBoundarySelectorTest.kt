package dev.doclens.doclens

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class LiveBoundarySelectorTest {
    private fun rect(left: Float, top: Float, right: Float, bottom: Float) = Quad(
        PointF(left, top), PointF(right, top),
        PointF(right, bottom), PointF(left, bottom),
    )

    @Test
    fun chairOutlineLosesToRealBlueClothInReferenceVideo() {
        // Normalised portrait coordinates, before rotating to CameraX's
        // sensor buffer. The top of the chair is outside the cloth's border.
        val chair = Quad(
            PointF(.20f, .03f), PointF(.75f, .14f),
            PointF(.84f, .97f), PointF(.19f, .95f),
        )
        val cloth = rect(.10f, .22f, .80f, .82f)
        assertEquals(cloth, LiveBoundarySelector.choose(chair, cloth, 592, 792))
    }

    @Test
    fun notebookDiagonalInteriorIsNotTheFourOuterCorners() {
        // November 15 screenshots: one half of a multicolour cover became
        // a wedge with a tiny top and a full-width bottom. The real document
        // is visible around that interior stripe and must not be cropped.
        val diagonalSection = Quad(
            PointF(.74f, .36f), PointF(.90f, .36f),
            PointF(.92f, .96f), PointF(.22f, .97f),
        )
        assertEquals(null, LiveBoundarySelector.choose(
            diagonalSection, null, 384, 288))
        val trueNotebook = Quad(
            PointF(.22f, .24f), PointF(.88f, .25f),
            PointF(.91f, .95f), PointF(.18f, .94f),
        )
        assertEquals(trueNotebook, LiveBoundarySelector.choose(
            trueNotebook, diagonalSection, 384, 288))
    }

    @Test
    fun writingAndNotebookLinesMustNotCreateAFalseTopStrip() {
        // A dense ruled notebook with scribbles can generate a short-sided
        // trapezoid covering just its top few lines (not the whole page).
        val ruledStrip = Quad(
            PointF(.22f, .27f), PointF(.89f, .29f),
            PointF(.85f, .46f), PointF(.20f, .34f),
        )
        assertNull(LiveBoundarySelector.choose(
            ruledStrip, null, 384, 288))
        val actualPage = rect(.17f, .27f, .88f, .94f)
        assertEquals(actualPage, LiveBoundarySelector.choose(
            actualPage, ruledStrip, 384, 288))
    }

    @Test
    fun legitimatePerspectivePageStillHasFourVisibleBalancedSides() {
        val page = Quad(
            PointF(.18f, .24f), PointF(.84f, .27f),
            PointF(.88f, .92f), PointF(.15f, .94f),
        )
        assertEquals(page, LiveBoundarySelector.choose(page, null, 384, 288))
        assertEquals(null, LiveBoundarySelector.choose(
            rect(0f, 0f, 1f, 1f), null, 384, 288))
    }

    @Test
    fun normalWhitePageBeatsItsInnerColouredPanel() {
        val page = rect(.13f, .12f, .87f, .86f)
        val colouredSection = rect(.20f, .22f, .80f, .79f)
        assertEquals(page, LiveBoundarySelector.choose(page, colouredSection, 592, 792))
    }

    @Test
    fun smallPrintedLabelInsideClothDoesNotWin() {
        val label = rect(.29f, .40f, .71f, .58f)
        val cloth = rect(.10f, .19f, .80f, .83f)
        assertEquals(cloth, LiveBoundarySelector.choose(label, cloth, 592, 792))
    }

    @Test
    fun distantColouredObjectCannotReplaceDocument() {
        val page = rect(.05f, .12f, .45f, .77f)
        val distantPanel = rect(.54f, .19f, .98f, .84f)
        assertEquals(page, LiveBoundarySelector.choose(page, distantPanel, 592, 792))
    }

    @Test
    fun colourPanelCannotBeInventedWithoutVisiblePixels() {
        val page = rect(.10f, .15f, .85f, .90f)
        assertEquals(page, LiveBoundarySelector.choose(page, null, 592, 792))
    }

    @Test
    fun frameWideChairCannotStealDetectionFromBlueCloth() {
        // Matches 381536.mp4, 00:02: the chair/frame starts at the preview
        // limits while the real cloth remains completely in the camera view.
        val chair = rect(0f, 0f, 1f, .83f)
        val cloth = rect(.28f, .23f, .86f, .81f)
        assertEquals(cloth, LiveBoundarySelector.choose(chair, cloth, 592, 792))
    }

    @Test
    fun frameWideFalsePositiveWithNoDocumentIsHidden() {
        val chair = rect(0f, .001f, 1f, .78f)
        assertNull(LiveBoundarySelector.choose(chair, null, 592, 792))
    }

    @Test
    fun normalPageWithClearMarginIsStillDetected() {
        val page = rect(.065f, .07f, .935f, .91f)
        assertEquals(page, LiveBoundarySelector.choose(page, null, 592, 792))
    }
}
