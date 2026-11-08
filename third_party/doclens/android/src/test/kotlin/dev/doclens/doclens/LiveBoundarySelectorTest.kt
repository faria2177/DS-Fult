package dev.doclens.doclens

import kotlin.test.Test
import kotlin.test.assertEquals

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
}
