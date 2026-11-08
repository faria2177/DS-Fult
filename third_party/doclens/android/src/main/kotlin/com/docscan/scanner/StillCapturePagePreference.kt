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
    ): DocumentBoundaryDetector.CandidateScore {
        if (imageArea <= 0.0) return best
        val bestArea = ContourDetector.calculatePolygonArea(best.corners)
        if (bestArea <= 0.0) return best

        return candidates.asSequence()
            .filter { it !== best }
            .filter { outer ->
                val area = ContourDetector.calculatePolygonArea(outer.corners)
                val coverage = area / imageArea
                // A small ID card is not a 20%-of-frame A4 page. Constrain
                // this preference to large, fully visible paper candidates.
                coverage in 0.20..0.86 && area >= bestArea * 1.85 &&
                    outer.totalConfidence >= .46 &&
                    outer.totalConfidence >= best.totalConfidence - .18 &&
                    outer.geometryScore >= .50 &&
                    outer.edgeScore >= .28 &&
                    outer.boundaryContrast >= 11.0 &&
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
