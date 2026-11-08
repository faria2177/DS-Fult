package com.docscan.scanner

import kotlin.math.abs
import kotlin.math.hypot

/** ID/business-card selection for a card lying on another sheet of paper.
 *
 * The ordinary page-scanner favours a large, complete sheet. A card is often
 * smaller and surrounded by form boxes, so the still-image page preference
 * can accidentally crop the form instead of the card. Require a believable
 * central landscape card with four supported edges. If no such boundary is
 * present, leave the original available for manual corner adjustment.
 */
object CardBoundaryPreference {
    fun select(
        candidates: List<DocumentBoundaryDetector.CandidateScore>,
        width: Int,
        height: Int,
    ): DocumentBoundaryDetector.CandidateScore? {
        if (width <= 0 || height <= 0) return null
        val imageArea = width.toDouble() * height
        return candidates.mapNotNull { candidate ->
            val quad = candidate.corners
            val aspect = ScannerTuning.normalizedLongRatio(quad)
            val area = ContourDetector.calculatePolygonArea(quad) / imageArea
            val centreX = quad.map { it.x }.average() / width
            val centreY = quad.map { it.y }.average() / height
            val centreDistance = hypot(centreX - .5, centreY - .5)
            if (aspect !in 1.46..2.45 || area !in .032..0.74 ||
                centreDistance > .36 || candidate.geometryScore < .43 ||
                candidate.edgeScore < .22 || candidate.totalConfidence < .38) {
                return@mapNotNull null
            }
            val aspectFit = (1.0 - abs(aspect - 1.72) / .80).coerceIn(0.0, 1.0)
            val centreFit = (1.0 - centreDistance / .36).coerceIn(0.0, 1.0)
            val areaFit = (1.0 - abs(area - .28) / .55).coerceIn(0.0, 1.0)
            val rank = candidate.totalConfidence * .38 +
                candidate.edgeScore * .24 +
                candidate.geometryScore * .12 +
                aspectFit * .16 + centreFit * .07 + areaFit * .03
            candidate to rank
        }.maxByOrNull { it.second }?.first
    }
}
