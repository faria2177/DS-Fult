package dev.doclens.doclens

import com.docscan.scanner.CardBoundaryPreference
import com.docscan.scanner.DetectionStage
import com.docscan.scanner.DocumentBoundaryDetector
import org.opencv.core.Point
import kotlin.test.Test
import kotlin.test.assertNull
import kotlin.test.assertSame

class CardBoundaryPreferenceTest {
    private fun candidate(
        x0: Double, y0: Double, x1: Double, y1: Double,
        confidence: Double = .65,
        edgeSupport: Double = .65,
    ) = DocumentBoundaryDetector.CandidateScore(
        corners = arrayOf(Point(x0, y0), Point(x1, y0),
            Point(x1, y1), Point(x0, y1)),
        totalConfidence = confidence,
        areaScore = .9,
        edgeScore = edgeSupport,
        geometryScore = .92,
        cornerScore = .8,
        aspectRatioScore = .9,
        boundaryContrast = 22.0,
        stage = DetectionStage.CONTOUR_QUAD,
    )

    @Test
    fun cardWinsOverLargeBankForm() {
        val card = candidate(230.0, 395.0, 770.0, 700.0, .66)
        val form = candidate(80.0, 80.0, 920.0, 940.0, .88)
        assertSame(card, CardBoundaryPreference.select(
            listOf(form, card), 1000, 1000))
    }

    @Test
    fun doesNotAutomaticallyCropOnlyTheBackgroundForm() {
        val form = candidate(100.0, 90.0, 910.0, 920.0, .90)
        assertNull(CardBoundaryPreference.select(listOf(form), 1000, 1000))
    }

    @Test
    fun weakCardEdgeMustBeReviewedManually() {
        val weakCard = candidate(230.0, 395.0, 770.0, 700.0,
            edgeSupport = .12)
        assertNull(CardBoundaryPreference.select(listOf(weakCard), 1000, 1000))
    }
}
