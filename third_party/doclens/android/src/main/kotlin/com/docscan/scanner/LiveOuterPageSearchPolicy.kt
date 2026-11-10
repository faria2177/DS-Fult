package com.docscan.scanner

/**
 * Decides whether a preview candidate might be printed content rather than
 * the actual outside of a sheet. Expensive colour/line passes are reserved
 * for an inset, smaller rectangle; normal full-page live detection stays fast.
 *
 * This policy only asks for more observations. It never fabricates corners or
 * makes a crop valid, and it is disabled for the dedicated ID-card mode.
 */
internal object LiveOuterPageSearchPolicy {
    fun shouldInspect(
        candidate: DocumentBoundaryDetector.CandidateScore?,
        width: Int,
        height: Int,
    ): Boolean {
        if (candidate == null || width <= 0 || height <= 0) return false
        val quad = candidate.corners
        if (quad.size != 4) return false

        val coverage = ContourDetector.calculatePolygonArea(quad) /
            (width.toDouble() * height)
        // The bank application in 381803.mp4 occupies the middle of a much
        // larger white sheet. A near-frame-wide candidate is more likely to
        // already be the true page (or a background we must not expand).
        if (coverage !in 0.12..0.53) return false

        val left = quad.minOf { it.x } / width
        val right = quad.maxOf { it.x } / width
        val top = quad.minOf { it.y } / height
        val bottom = quad.maxOf { it.y } / height
        if (left <= .045 || right >= .955 || top <= .045 || bottom >= .955) {
            return false
        }

        val ratio = ScannerTuning.normalizedLongRatio(quad)
        return ratio in 1.08..2.40 &&
            candidate.geometryScore >= .44 && candidate.edgeScore >= .18
    }
}
