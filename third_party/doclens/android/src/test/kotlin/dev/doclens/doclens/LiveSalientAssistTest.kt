package dev.doclens.doclens

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class LiveSalientAssistTest {
    private fun rect(left: Float, top: Float, right: Float, bottom: Float) = Quad(
        PointF(left, top), PointF(right, top),
        PointF(right, bottom), PointF(left, bottom),
    )

    // 386217.jpg: the bank ID card spans roughly x .36–.73, y .33–.61 of the
    // preview; the edge detector boxed only its white lower half.
    private val wholeCard = rect(.36f, .33f, .73f, .61f)
    private val whiteHalf = Quad(
        PointF(.31f, .47f), PointF(.69f, .52f),
        PointF(.69f, .60f), PointF(.31f, .59f),
    )

    @Test
    fun wholeCardReplacesTheBrightHalfOnly() {
        assertEquals(wholeCard, LiveSalientAssist.combine(whiteHalf, wholeCard))
    }

    @Test
    fun goodEdgeOutlineIsKept() {
        val edge = rect(.355f, .325f, .735f, .615f)
        assertEquals(edge, LiveSalientAssist.combine(edge, wholeCard))
    }

    @Test
    fun separateObjectDoesNotStealTheBox() {
        // The model picked a different object elsewhere in the frame.
        val other = rect(.05f, .05f, .30f, .25f)
        val page = rect(.40f, .40f, .90f, .90f)
        assertEquals(page, LiveSalientAssist.combine(page, other))
    }

    @Test
    fun modelOutlineIsUsedWhenEdgesFindNothing() {
        assertEquals(wholeCard, LiveSalientAssist.combine(null, wholeCard))
        assertNull(LiveSalientAssist.combine(null, null))
    }
}
