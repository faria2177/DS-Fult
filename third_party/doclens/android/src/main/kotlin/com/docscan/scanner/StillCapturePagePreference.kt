package com.docscan.scanner

import org.opencv.core.Point

/**
 * Page-aware tie-breaker for shutter stills only. An A4 document often has
 * heavy table borders inside a weaker outer page edge. Those internal lines
 * can outscore the actual paper and irreversibly crop away the letterhead and
 * signature. Prefer a complete outer page when BOTH borders were detected.
 *
 * This never invents four corners or uses a stale live-preview rectangle.
 */
internal object StillCapturePagePreference {
    fun select(
        candidates: List<DocumentBoundaryDetector.CandidateScore>,
        best: DocumentBoundaryDetector.CandidateScore,
        imageArea: Double,
        closePagePreview: Boolean = false,
    ): DocumentBoundaryDetector.CandidateScore {
        if (imageArea <= 0.0) return best
        val bestArea = ContourDetector.calculatePolygonArea(best.corners)
        if (bestArea <= 0.0) return best

        return candidates.asSequence()
            .filter { it !== best }
            .filter { outer ->
                val area = ContourDetector.calculatePolygonArea(outer.corners)
                val coverage = area / imageArea
                val ratio = area / bestArea
                val paperShape = ScannerTuning.paperRatioScore(
                    ScannerTuning.normalizedLongRatio(outer.corners))
                // When the camera is close, dense writing forms a strong
                // *inner* four-sided quadrilateral, often 65%-75% of the
                // real page area. The old 1.60x rule excluded genuine outer
                // sheets and kept the text region green. Permit 1.30x in
                // PREVIEW only, but demand stronger paper geometry and edge
                // evidence and exclude a huge desk/background rectangle.
                val closeEnough = closePagePreview &&
                    coverage in .35.. .88 &&
                    ratio in 1.30..2.40 &&
                    bestArea / imageArea >= .15 &&
                    outer.totalConfidence >= .46 &&
                    outer.totalConfidence >= best.totalConfidence - .32 &&
                    outer.geometryScore >= .68 &&
                    outer.edgeScore >= .28 &&
                    outer.boundaryContrast >= 9.0 &&
                    paperShape >= .63
                val stillSafe = coverage in .20.. .92 &&
                    ratio >= 1.60 &&
                    outer.totalConfidence >= .46 &&
                    outer.totalConfidence >= best.totalConfidence - .26 &&
                    outer.geometryScore >= .55 &&
                    outer.edgeScore >= .25 &&
                    outer.boundaryContrast >= 8.0 &&
                    paperShape >= .58
                (closeEnough || stillSafe) &&
                    isInside(outer.corners, best.corners)
            }
            .maxByOrNull { ContourDetector.calculatePolygonArea(it.corners) }
            ?: best
    }

    private fun isInside(outer: Array<Point>, inner: Array<Point>): Boolean {
        if (outer.size != 4 || inner.size != 4) return false
        // ContourDetector emits clockwise convex quads in image coordinates.
        // Each inner vertex must stay inside every half-plane of the outer.
        return inner.all { p ->
            (0..3).all { i ->
                val a = outer[i]
                val b = outer[(i + 1) % 4]
                val cross = (b.x - a.x) * (p.y - a.y) -
                    (b.y - a.y) * (p.x - a.x)
                cross >= -1.0
            }
        }
    }
}
