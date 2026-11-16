package dev.doclens.doclens

import com.docscan.scanner.DocumentBoundaryDetector
import com.docscan.scanner.DetectionStage
import com.docscan.scanner.StillCapturePagePreference
import org.opencv.core.Point
import kotlin.test.Test
import kotlin.test.assertSame

class StillCapturePagePreferenceTest {
    private fun candidate(
        x0: Double, y0: Double, x1: Double, y1: Double,
        confidence: Double, contrast: Double = 24.0,
    ) = DocumentBoundaryDetector.CandidateScore(
        corners = arrayOf(Point(x0, y0), Point(x1, y0),
            Point(x1, y1), Point(x0, y1)),
        totalConfidence = confidence,
        areaScore = 1.0,
        edgeScore = .6,
        geometryScore = .92,
        cornerScore = .7,
        aspectRatioScore = .88,
        boundaryContrast = contrast,
        stage = DetectionStage.CONTOUR_QUAD,
    )

    @Test
    fun letterheadAndSignatureRemainWhenTableHasStrongerInnerLines() {
        // Representative still: the table occupies 14% of the image but the
        // 60%-area page enclosing it is detected with slightly less confidence.
        val table = candidate(220.0, 290.0, 780.0, 540.0, .72)
        val page = candidate(180.0, 70.0, 830.0, 930.0, .62)
        assertSame(page, StillCapturePagePreference.select(
            listOf(table, page), table, 1_000_000.0))
    }

    @Test
    fun smallCardNeverExpandsToWeakDesktopRectangle() {
        val card = candidate(360.0, 400.0, 660.0, 590.0, .72)
        val tableEdge = candidate(140.0, 170.0, 880.0, 830.0,
            .61, contrast = 4.0)
        assertSame(card, StillCapturePagePreference.select(
            listOf(card, tableEdge), card, 1_000_000.0))
    }

    @Test
    fun unrelatedLargerObjectDoesNotReplaceDetectedDocument() {
        val document = candidate(470.0, 350.0, 700.0, 600.0, .70)
        val elsewhere = candidate(110.0, 100.0, 510.0, 700.0, .65)
        assertSame(document, StillCapturePagePreference.select(
            listOf(document, elsewhere), document, 1_000_000.0))
    }

    @Test
    fun lowContrastOutsideLetterCanBeatStrongInnerTable() {
        val innerText = candidate(260.0, 325.0, 735.0, 590.0, .73)
        // The outer sheet is real but faded: its confidence trails the
        // sharply printed table by .23, outside the old .18 tie-breaker.
        val paper = candidate(180.0, 80.0, 840.0, 955.0,
            .50, contrast = 12.0)
        assertSame(paper, StillCapturePagePreference.select(
            listOf(innerText, paper), innerText, 1_000_000.0))
    }

    @Test
    fun largeSquareBackgroundDoesNotReplaceActualPage() {
        val document = candidate(330.0, 280.0, 655.0, 725.0, .74)
        val squareTable = candidate(60.0, 50.0, 950.0, 940.0,
            .58, contrast = 25.0)
        assertSame(document, StillCapturePagePreference.select(
            listOf(document, squareTable), document, 1_000_000.0))
    }
}
