package dev.doclens.doclens

import com.docscan.scanner.DetectionStage
import com.docscan.scanner.DocumentBoundaryDetector
import com.docscan.scanner.LiveOuterPageSearchPolicy
import com.docscan.scanner.StillCapturePagePreference
import org.opencv.core.Point
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertSame
import kotlin.test.assertTrue

class LiveOuterPageSearchPolicyTest {
    private fun candidate(
        left: Double, top: Double, right: Double, bottom: Double,
        confidence: Double = .72,
    ) = DocumentBoundaryDetector.CandidateScore(
        corners = arrayOf(
            Point(left, top), Point(right, top),
            Point(right, bottom), Point(left, bottom),
        ),
        totalConfidence = confidence,
        areaScore = 1.0,
        edgeScore = .66,
        geometryScore = .90,
        cornerScore = .8,
        aspectRatioScore = .85,
        boundaryContrast = 16.0,
        stage = DetectionStage.CONTOUR_QUAD,
    )

    @Test
    fun densePrintedFormTriggersOuterPageSearchAndPrefersRealEnclosingSheet() {
        val width = 320
        val height = 400
        val printedTable = candidate(75.0, 95.0, 245.0, 270.0, .79)
        val actualPaper = candidate(25.0, 26.0, 295.0, 374.0, .62)

        assertTrue(LiveOuterPageSearchPolicy.shouldInspect(
            printedTable, width, height))
        assertSame(actualPaper, StillCapturePagePreference.select(
            listOf(printedTable, actualPaper), printedTable,
            (width * height).toDouble()))
    }

    @Test
    fun actualLargePaperKeepsFastLivePath() {
        assertFalse(LiveOuterPageSearchPolicy.shouldInspect(
            candidate(18.0, 24.0, 302.0, 377.0), 320, 400))
    }

    @Test
    fun clippedRectangleDoesNotTriggerBlindPageExpansion() {
        assertFalse(LiveOuterPageSearchPolicy.shouldInspect(
            candidate(4.0, 85.0, 210.0, 305.0), 320, 400))
    }

    @Test
    fun printedHeadingStripDoesNotCountAsInsetSheet() {
        assertFalse(LiveOuterPageSearchPolicy.shouldInspect(
            candidate(65.0, 100.0, 270.0, 142.0), 320, 400))
    }
}
