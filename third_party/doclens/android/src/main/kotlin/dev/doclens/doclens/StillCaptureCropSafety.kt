package dev.doclens.doclens

import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

/** Geometric checks that keep an interior text/table band from replacing an A4 page.
 *
 * Coordinates are normalised to the upright still/preview image. No guessed
 * corners are ever warped automatically: uncertain stills go to manual review.
 */
internal object StillCaptureCropSafety {
    fun area(quad: Quad): Double {
        val points = listOf(quad.topLeft, quad.topRight, quad.bottomRight, quad.bottomLeft)
        var sum = 0.0
        for (i in points.indices) {
            val a = points[i]
            val b = points[(i + 1) % points.size]
            sum += a.x.toDouble() * b.y - b.x.toDouble() * a.y
        }
        return abs(sum) * .5
    }

    private fun edgeLength(a: PointF, b: PointF, width: Int, height: Int): Double =
        hypot((a.x - b.x) * width.toDouble(), (a.y - b.y) * height.toDouble())

    private fun sideLengths(quad: Quad, width: Int, height: Int): Pair<Double, Double> {
        val horizontal = (edgeLength(quad.topLeft, quad.topRight, width, height) +
            edgeLength(quad.bottomLeft, quad.bottomRight, width, height)) * .5
        val vertical = (edgeLength(quad.topLeft, quad.bottomLeft, width, height) +
            edgeLength(quad.topRight, quad.bottomRight, width, height)) * .5
        return horizontal to vertical
    }

    /** A live quad that can seed a review if the still chooses an inner table. */
    fun isCrediblePage(quad: Quad, width: Int, height: Int): Boolean {
        if (width <= 0 || height <= 0) return false
        val points = listOf(quad.topLeft, quad.topRight, quad.bottomRight, quad.bottomLeft)
        if (points.any { it.x !in 0.0f..1.0f || it.y !in 0.0f..1.0f }) return false
        val coverage = area(quad)
        val (w, h) = sideLengths(quad, width, height)
        val aspect = max(w, h) / min(w, h).coerceAtLeast(1.0)
        return coverage in .30..0.94 && aspect in 1.12..1.89
    }

    /** Strong *outer* ID-card proposal in a fully visible still photograph.
     *
     * Unlike the full-page policy, a card is landscape in physical pixels
     * regardless of photo rotation. Require enough foreground for a complete
     * card, an ID-like ratio and a reasonably centred contour. This is only
     * used to promote an independent colour-mask candidate, not to invalidate
     * the existing dedicated ID-card OpenCV selector.
     */
    fun isCredibleCard(quad: Quad, width: Int, height: Int): Boolean {
        if (width <= 0 || height <= 0) return false
        val points = listOf(quad.topLeft, quad.topRight,
            quad.bottomRight, quad.bottomLeft)
        if (points.any { !it.x.isFinite() || !it.y.isFinite() ||
                it.x !in 0.012f..0.988f || it.y !in 0.012f..0.988f }) return false
        val coverage = area(quad)
        if (coverage !in 0.25..0.86) return false
        val (w, h) = sideLengths(quad, width, height)
        val aspect = max(w, h) / min(w, h).coerceAtLeast(1.0)
        if (aspect !in 1.48..2.1) return false
        val cx = points.sumOf { it.x.toDouble() } / 4
        val cy = points.sumOf { it.y.toDouble() } / 4
        return abs(cx - .5) <= .22 && abs(cy - .5) <= .22
    }

    /**
     * The chroma mask has independent evidence that a *coloured* card is
     * surrounded by neutral paper, so it may accept a smaller complete card
     * than the generic contour detector. This must never relax the normal
     * A4-page or unverified text-box policy.
     */
    fun isCredibleColorCard(quad: Quad, width: Int, height: Int): Boolean {
        if (width <= 0 || height <= 0) return false
        val points = listOf(quad.topLeft, quad.topRight,
            quad.bottomRight, quad.bottomLeft)
        if (points.any { !it.x.isFinite() || !it.y.isFinite() ||
                it.x !in 0.025f..0.975f || it.y !in 0.025f..0.975f }) return false
        if (area(quad) !in 0.16..0.76) return false
        val (w, h) = sideLengths(quad, width, height)
        val ratio = max(w, h) / min(w, h).coerceAtLeast(1.0)
        if (ratio !in 1.44..2.12) return false
        val spanX = points.maxOf { it.x } - points.minOf { it.x }
        val spanY = points.maxOf { it.y } - points.minOf { it.y }
        if (spanX < .32f || spanY < .28f) return false
        val cx = points.sumOf { it.x.toDouble() } / 4
        val cy = points.sumOf { it.y.toDouble() } / 4
        return abs(cx - .5) <= .22 && abs(cy - .5) <= .22
    }

    /**
     * Only an independently segmented *whole card* may challenge camera
     * preview geometry. A broad border from the notebook can be replaced;
     * a normal A4 page cannot be replaced by a coloured heading inside it.
     * A close match means the normal detector already found this same card.
     */
    fun verifiedColorCardOverBackground(
        detected: Quad?, colorCard: Quad?, width: Int, height: Int,
    ): Boolean {
        if (colorCard == null || !isCredibleColorCard(colorCard, width, height)) {
            return false
        }
        if (detected == null) return true
        val normalPoints = listOf(detected.topLeft, detected.topRight,
            detected.bottomRight, detected.bottomLeft)
        val cardPoints = listOf(colorCard.topLeft, colorCard.topRight,
            colorCard.bottomRight, colorCard.bottomLeft)
        val alreadySame = normalPoints.indices.all { i ->
            hypot((normalPoints[i].x - cardPoints[i].x).toDouble(),
                (normalPoints[i].y - cardPoints[i].y).toDouble()) <= .055
        }
        if (alreadySame) return true
        val left = normalPoints.minOf { it.x }
        val right = normalPoints.maxOf { it.x }
        val top = normalPoints.minOf { it.y }
        val bottom = normalPoints.maxOf { it.y }
        val nearFrameSides = listOf(left < .065f, right > .935f,
            top < .065f, bottom > .935f).count { it }
        return nearFrameSides >= 3 && area(detected) >= .70 &&
            area(detected) >= area(colorCard) * 1.40 &&
            encloses(detected, colorCard)
    }

    /** Recover an independently segmented outer card, never a loose panel.
     * If the card-mode contour is a smaller inner name box, the mask must
     * actually surround it and be at least 35% larger to replace it.
     */
    fun chooseCardStillBoundary(
        contour: Quad?, contrast: Quad?, neutral: Quad?,
        width: Int, height: Int, saturated: Quad? = null,
        colorCard: Quad? = null,
    ): Quad? {
        val normalCandidates = listOfNotNull(contrast, neutral, saturated)
            .filter { isCredibleCard(it, width, height) }
        val colorCandidates = listOfNotNull(colorCard)
            .filter { isCredibleColorCard(it, width, height) }
        val outer = (normalCandidates + colorCandidates)
            .maxByOrNull { area(it) } ?: return contour
        if (contour == null) return outer
        if (encloses(outer, contour) && area(outer) >= area(contour) * 1.35) {
            return outer // Recover the outside from a printed name box.
        }
        // A white ruled notebook can have a near-frame OpenCV contour, while
        // the smaller gold ID on it has a strong, coherent *colour* contour.
        // Only discard the broad frame if it is NOT itself a plausible card.
        if (!isCredibleCard(contour, width, height) &&
            encloses(contour, outer) && area(contour) >= area(outer) * 1.35) {
            return outer
        }
        return contour
    }

    /**
     * A high-contrast inner title, label or table can win still detection even
     * though the live preview framed the entire document. The still JPEG's
     * sensor orientation is not guaranteed to match the displayed preview, so
     * do not rely solely on `height > width` to recognise a narrow inner crop.
     *
     * Prefer a full, editable original over an irreversible crop when a small,
     * centred strip is proposed. The separate ID-card flow deliberately does
     * not use this guard (see ScannerSession.capture).
     */
    fun isSuspiciousInteriorStrip(quad: Quad, width: Int, height: Int): Boolean {
        if (width <= 0 || height <= 0) return false
        val points = listOf(quad.topLeft, quad.topRight, quad.bottomRight, quad.bottomLeft)
        if (points.any { !it.x.isFinite() || !it.y.isFinite() ||
                it.x !in 0f..1f || it.y !in 0f..1f }) return false

        val left = points.minOf { it.x }
        val right = points.maxOf { it.x }
        val top = points.minOf { it.y }
        val bottom = points.maxOf { it.y }
        // A border touching the picture edge may be a real, closely framed
        // document. This guard is specifically for an *interior* rectangle.
        if (left < .045f || right > .955f || top < .065f || bottom > .935f) {
            return false
        }

        val (w, h) = sideLengths(quad, width, height)
        val coverage = area(quad)
        // Cover both orientations: a landscape text band in an upright JPEG,
        // or the same band rotated by CameraX/EXIF on a device-specific path.
        val narrowStrip = max(w, h) > min(w, h) * 1.55
        val smallCentralPanel = coverage < .19 && narrowStrip
        // Preserve the earlier portrait-page protection for somewhat wider
        // text bands, without disallowing a well-framed landscape document.
        val portraitTextBand = height > width * 1.10 && w > h * 1.58 &&
            coverage < .36 && (bottom - top) < .43f
        return smallCentralPanel || portraitTextBand
    }

    fun compatibleView(previewWidth: Int, previewHeight: Int,
                       stillWidth: Int, stillHeight: Int): Boolean {
        if (previewWidth <= 0 || previewHeight <= 0 ||
            stillWidth <= 0 || stillHeight <= 0) return false
        val previewAspect = previewWidth.toDouble() / previewHeight
        val stillAspect = stillWidth.toDouble() / stillHeight
        return abs(previewAspect - stillAspect) / previewAspect <= .085
    }

    /**
     * A few Android CameraX devices write landscape JPEG pixels without the
     * 90/270-degree EXIF flag while the live analysis surface is portrait.
     * Only correct a proven transposed aspect ratio, using CameraX's recent
     * frame rotation; never guess from the content of a landscape document.
     */
    fun missingExifQuarterTurns(previewWidth: Int, previewHeight: Int,
                                stillWidth: Int, stillHeight: Int,
                                frameRotationDegrees: Int): Int {
        if (compatibleView(previewWidth, previewHeight, stillWidth, stillHeight)) return 0
        if (!compatibleView(previewWidth, previewHeight, stillHeight, stillWidth)) return 0
        return when (((frameRotationDegrees % 360) + 360) % 360) {
            90 -> 1
            270 -> 3
            else -> 0
        }
    }

    fun significantlySmallerThan(still: Quad, preview: Quad): Boolean =
        area(still) < area(preview) * .78

    /** A proposed coloured outer panel must actually contain the inner crop. */
    fun encloses(outer: Quad, inner: Quad): Boolean {
        val boundary = listOf(outer.topLeft, outer.topRight,
            outer.bottomRight, outer.bottomLeft)
        val subject = listOf(inner.topLeft, inner.topRight,
            inner.bottomRight, inner.bottomLeft)
        return subject.all { point ->
            boundary.indices.all { index ->
                val a = boundary[index]
                val b = boundary[(index + 1) % boundary.size]
                (b.x - a.x) * (point.y - a.y) -
                    (b.y - a.y) * (point.x - a.x) >= -.008f
            }
        }
    }

    /** Called before any irreversible perspective warp of a normal scan. */
    fun requiresManualReview(
        still: Quad?, width: Int, height: Int, credibleLiveHint: Quad?,
    ): Boolean = still == null ||
        !isCrediblePage(still, width, height) ||
        isSuspiciousInteriorStrip(still, width, height) ||
        (credibleLiveHint != null && significantlySmallerThan(still, credibleLiveHint))

    /** Keep accurate CV corners unless the independent mask clearly recovers a page. */
    fun shouldPreferPaperMask(
        still: Quad, mask: Quad, width: Int, height: Int,
    ): Boolean {
        if (!isCrediblePage(mask, width, height)) return false
        val stillArea = area(still)
        val needsRecovery = stillArea < .28 ||
            isSuspiciousInteriorStrip(still, width, height) ||
            !isCrediblePage(still, width, height)
        val minimumGrowth = if (needsRecovery) 1.35 else 1.85
        return area(mask) > stillArea * minimumGrowth
    }
}
