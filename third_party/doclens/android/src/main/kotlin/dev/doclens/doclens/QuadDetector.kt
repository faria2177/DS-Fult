package dev.doclens.doclens

import android.graphics.Bitmap
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min


/**
 * Document quadrilateral detector that runs entirely on a downscaled
 * luma buffer. Strategy:
 *
 * 1. Compute mean luma; build a mask of the pixels on the document's side of
 *    that mean — brighter (paper, the default), darker (a dark ID card or a
 *    colored trading card on a light desk), or whichever of the two looks
 *    more document-like ([DetectionPolarity.AUTO]).
 * 2. Keep several substantial connected components. A brightly lit table,
 *    blanket or video-call overlay can be larger than the document.
 * 3. Score convex quadrilateral candidates for solidity, on-screen size,
 *    isolation from frame borders, and proximity to the preview centre.
 *
 * Returns normalized `[0,1]` coordinates in `topLeft → topRight → bottomRight
 * → bottomLeft` order on the input buffer's frame (orientation handled by
 * caller).
 *
 * Luma-only fallback when the OpenCV reference boundary detector does not
 * find a credible quadrilateral (or OpenCV cannot load on the device).
 */
object QuadDetector {
    /**
     * Luma bias applied on top of the frame mean when thresholding. Keeps the
     * mask off the noise floor around the mean, where a flat surface's own
     * gradient would otherwise carve out shapes.
     */
    const val DEFAULT_THRESHOLD_OFFSET = 20

    /**
     * Largest bias worth honouring. Past this the clamps in [buildMask] pin
     * the threshold to its extremes, so a larger offset changes nothing.
     */
    private const val MAX_THRESHOLD_OFFSET = 128

    fun detect(
        luma: ByteArray,
        width: Int,
        height: Int,
        polarity: DetectionPolarity = DetectionPolarity.BRIGHTER,
        thresholdOffset: Int = DEFAULT_THRESHOLD_OFFSET,
    ): Quad? {
        if (width < 16 || height < 16) return null
        val offset = thresholdOffset.coerceIn(0, MAX_THRESHOLD_OFFSET)
        return when (polarity) {
            DetectionPolarity.BRIGHTER ->
                analyze(luma, width, height, darker = false, offset = offset)?.quad
            DetectionPolarity.DARKER ->
                analyze(luma, width, height, darker = true, offset = offset)?.quad
            DetectionPolarity.AUTO -> {
                val bright = analyze(luma, width, height, darker = false, offset = offset)
                val dark = analyze(luma, width, height, darker = true, offset = offset)
                when {
                    bright == null -> dark?.quad
                    dark == null -> bright.quad
                    dark.score > bright.score -> dark.quad
                    else -> bright.quad
                }
            }
        }
    }

    /** The best non-border, document-shaped component at one polarity. */
    private class Candidate(val quad: Quad, val score: Float)

    /**
     * A connected component extending off the preview edge is often the desk
     * or a background object, not the document. Never let the biggest blob
     * prevent a smaller, central, closed quadrilateral from being considered.
     */
    private fun analyze(
        luma: ByteArray,
        width: Int,
        height: Int,
        darker: Boolean,
        offset: Int,
    ): Candidate? = analyzeMask(buildMask(luma, darker, offset), width, height)

    private fun analyzeMask(mask: BooleanArray, width: Int, height: Int): Candidate? {
        var best: Candidate? = null
        for (component in largestComponents(mask, width, height)) {
            val boundary = traceBoundary(component, width, height) ?: continue
            val hull = convexHull(boundary)
            if (hull.size < 4) continue
            val corners = approximateQuad(hull) ?: continue
            val score = documentScore(component, corners, width, height)
            if (score <= 0f) continue
            if (best == null || score > best.score) {
                best = Candidate(
                    normalizeAndOrder(corners, width.toFloat(), height.toFloat()),
                    score,
                )
            }
        }
        return best
    }

    /**
     * Still-image safety net for a pale page on a saturated surface (for
     * example, the white sheet on blue cloth in the supplied Add Pages video).
     * Its paper/background contrast is largely chromatic rather than luma,
     * so an ordinary mean-luma threshold can miss the page entirely.
     *
     * Only enable this mask when a meaningful share of the scene is genuinely
     * colourful. On a white/grey desk its mask would include the whole image;
     * that scene must continue through the regular contour/luma detectors.
     * This is deliberately pixel-only and unit-testable without Android/JNI.
     */
    internal fun detectNeutralPaper(
        pixels: IntArray,
        width: Int,
        height: Int,
    ): Quad? {
        if (width < 32 || height < 32 || pixels.size != width * height) return null
        val mask = BooleanArray(pixels.size)
        var colouredBackgroundPixels = 0
        for (i in pixels.indices) {
            val pixel = pixels[i]
            val r = (pixel shr 16) and 0xFF
            val g = (pixel shr 8) and 0xFF
            val b = pixel and 0xFF
            val high = max(r, max(g, b))
            val low = min(r, min(g, b))
            val spread = high - low
            if (high >= 60 && spread * 100 >= high * 37) {
                colouredBackgroundPixels++
            }
            // Permit mild yellow/grey paper and photographed shadows; exclude
            // the saturated blue/green/red backdrop even if it is bright.
            mask[i] = high >= 106 && spread * 100 <= high * 27
        }
        if (colouredBackgroundPixels < pixels.size / 10) return null
        return analyzeMask(mask, width, height)?.quad
    }

    /**
     * Still-only page segmentation for neutral desks, wood and dark backgrounds.
     *
     * A dense printed letter has much stronger lines *inside* its page than at
     * the true sheet boundary. The regular edge detector can therefore return
     * a narrow text/table rectangle. This independent cue compares the image
     * with the background visible in the four corner patches, then finds a
     * large, closed and document-shaped component in that colour difference.
     *
     * Per-channel corner medians tolerate one finger or cluttered corner;
     * badly varying corner backgrounds raise the threshold or disable this
     * cue. Unlike a global brightness threshold, this can also find grey paper
     * on a grey desk when their relative lightness differs. It requires the
     * *entire* page to be framed and never fabricates an off-screen corner.
     */
    internal fun detectBackgroundContrastPage(
        pixels: IntArray,
        width: Int,
        height: Int,
    ): Quad? {
        if (width < 64 || height < 64 || pixels.size != width * height) return null

        // Keep the sample patches smaller than the minimum corner inset. A
        // centred document may take almost the whole preview; the first 3%
        // of each frame corner should still show its background.
        val patchW = (width * .028).toInt().coerceAtLeast(3)
        val patchH = (height * .028).toInt().coerceAtLeast(3)
        val cornerMeans = Array(4) { IntArray(3) }
        for (corner in 0..3) {
            val startX = if (corner % 2 == 0) 0 else width - patchW
            val startY = if (corner < 2) 0 else height - patchH
            var r = 0L
            var g = 0L
            var b = 0L
            for (y in startY until startY + patchH) {
                for (x in startX until startX + patchW) {
                    val pixel = pixels[y * width + x]
                    r += (pixel shr 16) and 0xFF
                    g += (pixel shr 8) and 0xFF
                    b += pixel and 0xFF
                }
            }
            val count = (patchW * patchH).toLong()
            cornerMeans[corner][0] = (r / count).toInt()
            cornerMeans[corner][1] = (g / count).toInt()
            cornerMeans[corner][2] = (b / count).toInt()
        }

        // Median from four corners is resilient to one mismatched patch.
        val background = IntArray(3) { channel ->
            val values = cornerMeans.map { it[channel] }.sorted()
            (values[1] + values[2]) / 2
        }
        val deviations = cornerMeans.map { corner ->
            (0..2).sumOf { channel ->
                kotlin.math.abs(corner[channel] - background[channel])
            } / 3.0
        }.sorted()
        val backgroundVariation = deviations[2] // three agreeing corners
        if (backgroundVariation > 38.0) return null

        val threshold = (14.0 + backgroundVariation * 2.25).coerceIn(14.0, 72.0)
        val mask = BooleanArray(pixels.size)
        var foregroundCount = 0
        for (i in pixels.indices) {
            val pixel = pixels[i]
            val difference = (
                kotlin.math.abs(((pixel shr 16) and 0xFF) - background[0]) +
                kotlin.math.abs(((pixel shr 8) and 0xFF) - background[1]) +
                kotlin.math.abs((pixel and 0xFF) - background[2])
            ) / 3.0
            if (difference >= threshold) {
                mask[i] = true
                foregroundCount++
            }
        }
        val foregroundFraction = foregroundCount.toDouble() / pixels.size
        if (foregroundFraction !in .11..0.90) return null
        val candidate = analyzeMask(mask, width, height)?.quad ?: return null
        val area = StillCaptureCropSafety.area(candidate)
        if (area !in .15..0.90) return null
        val horizontal = kotlin.math.hypot(
            (candidate.topRight.x - candidate.topLeft.x).toDouble() * width,
            (candidate.topRight.y - candidate.topLeft.y).toDouble() * height,
        )
        val vertical = kotlin.math.hypot(
            (candidate.bottomLeft.x - candidate.topLeft.x).toDouble() * width,
            (candidate.bottomLeft.y - candidate.topLeft.y).toDouble() * height,
        )
        val longRatio = kotlin.math.max(horizontal, vertical) /
            kotlin.math.min(horizontal, vertical).coerceAtLeast(1.0)
        return candidate.takeIf { longRatio in 1.08..2.80 }
    }

    /**
     * A saturated *outer* document can contain a much stronger contrasting
     * inner label. In video 381526.mp4 the blue poster is on mixed stone and
     * patterned cloth, so sampling all four frame corners as one background
     * colour cannot recover its boundary. Search for a large connected panel
     * of locally consistent colour instead.
     *
     * This is a still-only proposal, never a standalone cropping decision.
     * [detectInBitmap] promotes it only when it is a credible, substantially
     * larger page than the contour winner. Four small inset samples avoid a
     * hard-coded colour (the page need not be blue); blank or full-frame
     * coloured backgrounds are rejected by the same geometric checks.
     */
    internal fun detectSaturatedPanel(
        pixels: IntArray,
        width: Int,
        height: Int,
        forLivePreview: Boolean = false,
    ): Quad? {
        if (width < 64 || height < 64 || pixels.size != width * height) return null
        val samples = if (forLivePreview) arrayOf(
            .32 to .32, .68 to .32, .32 to .68, .68 to .68, .50 to .50,
        ) else arrayOf(
            .28 to .20, .72 to .20,
            .28 to .32, .72 to .32,
        )
        var best: Quad? = null
        var bestArea = 0.0
        for ((sx, sy) in samples) {
            val sample = pixels[(sy * height).toInt() * width + (sx * width).toInt()]
            val sr = (sample shr 16) and 0xFF
            val sg = (sample shr 8) and 0xFF
            val sb = sample and 0xFF
            val high = max(sr, max(sg, sb))
            val low = min(sr, min(sg, sb))
            if (high < 85 || (high - low) * 100 < high * 32) continue

            val mask = BooleanArray(pixels.size)
            for (i in pixels.indices) {
                val p = pixels[i]
                val r = (p shr 16) and 0xFF
                val g = (p shr 8) and 0xFF
                val b = p and 0xFF
                val peak = max(r, max(g, b))
                val trough = min(r, min(g, b))
                if (peak < 70 || (peak - trough) * 100 < peak * 25) continue
                val difference = (abs(r - sr) + abs(g - sg) + abs(b - sb)) / 3
                mask[i] = difference <= 48
            }
            val quad = analyzeMask(mask, width, height)?.quad ?: continue
            val area = StillCaptureCropSafety.area(quad)
            if (forLivePreview) {
                // Fabric, posters and book covers can be close to square.
                // Keep this a candidate, subject to LiveBoundarySelector.
                if (area !in 0.22..0.87) continue
            } else if (!StillCaptureCropSafety.isCrediblePage(quad, width, height)) {
                continue
            }
            if (area > bestArea) {
                best = quad
                bestArea = area
            }
        }
        return best
    }

    /**
     * A small gold/coloured ID card laid over an almost neutral notebook is
     * neither an A4 page nor a large saturated poster. The normal still
     * colour-panel cue deliberately rejects it (page area >= 30%). Use a
     * separate, still-only foreground mask instead of relaxing the A4 rules.
     *
     * Thin blue notebook rules, monochrome printed text and pale shadows do
     * not pass the chroma threshold. Three of the four *outer* corner patches
     * must also be neutral, so a coloured tabletop/cloth is not silently
     * mistaken for a smaller card. This is a proposal only: the independent
     * four-corner and aspect-ratio checks still decide whether it is safe.
     */
    internal fun detectColoredCardOnNeutralPage(
        pixels: IntArray,
        width: Int,
        height: Int,
    ): Quad? {
        if (width < 64 || height < 64 || pixels.size != width * height) return null
        val patchW = (width * .085).toInt().coerceAtLeast(4)
        val patchH = (height * .085).toInt().coerceAtLeast(4)
        var neutralCorners = 0
        for (corner in 0..3) {
            val startX = if (corner % 2 == 0) 0 else width - patchW
            val startY = if (corner < 2) 0 else height - patchH
            var coloured = 0
            for (y in startY until startY + patchH) {
                for (x in startX until startX + patchW) {
                    if (isCardForegroundColor(pixels[y * width + x])) coloured++
                }
            }
            if (coloured * 4 < patchW * patchH) neutralCorners++
        }
        if (neutralCorners < 3) return null

        val colourMask = BooleanArray(pixels.size)
        var colouredPixels = 0
        for (i in pixels.indices) {
            if (isCardForegroundColor(pixels[i])) {
                colourMask[i] = true
                colouredPixels++
            }
        }
        if (colouredPixels.toDouble() / pixels.size !in .105..0.78) return null
        val card = analyzeMask(colourMask, width, height)?.quad ?: return null
        return card.takeIf {
            StillCaptureCropSafety.isCredibleColorCard(it, width, height)
        }
    }

    private fun isStronglyColoured(pixel: Int): Boolean {
        val r = (pixel shr 16) and 0xFF
        val g = (pixel shr 8) and 0xFF
        val b = pixel and 0xFF
        val high = max(r, max(g, b))
        val low = min(r, min(g, b))
        return high >= 95 && (high - low) * 100 >= high * 32
    }

    /**
     * Light gold cards can be almost as bright as the paper underneath them.
     * They have a consistent warm red/green excess over blue even when their
     * HSV saturation falls below the generic coloured-panel threshold.
     * White notebook pages and thin blue ruling fail this additional cue.
     */
    private fun isCardForegroundColor(pixel: Int): Boolean {
        if (isStronglyColoured(pixel)) return true
        val r = (pixel shr 16) and 0xFF
        val g = (pixel shr 8) and 0xFF
        val b = pixel and 0xFF
        return r >= 130 && g >= 105 && r - b >= 34 && g - b >= 14
    }

    /**
     * An independent, colour-backed still-capture hint. Used only after the
     * user presses the shutter, never in the live-frame hot path. This can
     * verify a card when the normal camera detector has chosen the entire
     * ruled notebook behind it. The original high-resolution photo stays
     * intact, and the normalized corners warp the full-resolution bitmap.
     */
    internal fun detectColoredCardInBitmap(bitmap: Bitmap): Quad? {
        if (bitmap.width < 64 || bitmap.height < 64) return null
        val scale = min(1.0, 512.0 / max(bitmap.width, bitmap.height))
        val width = max(64, (bitmap.width * scale).toInt())
        val height = max(64, (bitmap.height * scale).toInt())
        val small = if (width == bitmap.width && height == bitmap.height) bitmap
            else Bitmap.createScaledBitmap(bitmap, width, height, true)
        val pixels = IntArray(width * height)
        try {
            small.getPixels(pixels, 0, width, 0, 0, width, height)
        } finally {
            if (small !== bitmap) small.recycle()
        }
        return detectColoredCardOnNeutralPage(pixels, width, height)
    }

    /** RGB-backed live candidate at a bounded 256px edge, independent of OpenCV. */
    internal fun detectSaturatedPanelInRgba(
        rgba: ByteArray, width: Int, height: Int,
    ): Quad? {
        if (width < 64 || height < 64 || rgba.size != width * height * 4) return null
        val scale = min(1.0, 256.0 / max(width, height))
        val dw = (width * scale).toInt().coerceAtLeast(64)
        val dh = (height * scale).toInt().coerceAtLeast(64)
        val pixels = IntArray(dw * dh)
        for (y in 0 until dh) {
            val sourceY = (y / scale).toInt().coerceIn(0, height - 1)
            for (x in 0 until dw) {
                val sourceX = (x / scale).toInt().coerceIn(0, width - 1)
                val offset = (sourceY * width + sourceX) * 4
                pixels[y * dw + x] = (0xFF shl 24) or
                    ((rgba[offset].toInt() and 0xFF) shl 16) or
                    ((rgba[offset + 1].toInt() and 0xFF) shl 8) or
                    (rgba[offset + 2].toInt() and 0xFF)
            }
        }
        return detectSaturatedPanel(pixels, dw, dh, forLivePreview = true)
    }

    /**
     * Give a central, closed card a chance against a larger bright background.
     *
     * - **solidity** — component pixels over its own quad's area. A document
     *   fills its quad; the surface *around* a document does not, because the
     *   document is a hole punched in it.
     * - **borderFraction** — the share of the frame's outer ring the component
     *   owns. The surface a document lies on runs off every edge of the frame;
     *   the document itself usually does not.
     * - **coverage** — saturates once a candidate is comfortably readable;
     *   a large foreground region must not always beat a smaller ID card.
     * - **centrality** — prefers the document being framed over a bright
     *   distraction in a corner, without requiring a perfectly centred page.
     */
    private fun documentScore(
        component: IntArray,
        corners: List<PointF>,
        width: Int,
        height: Int,
    ): Float {
        val area = polygonArea(corners)
        if (area <= 0f) return 0f
        // Even the low-cost fallback must not interpret an off-screen patch
        // of fabric or desk as a fully capturable four-corner document.
        val insetX = width * 0.015f
        val insetY = height * 0.015f
        if (corners.any { it.x < insetX || it.y < insetY ||
                it.x > width - insetX || it.y > height - insetY }) return 0f
        val solidity = (component.size / area).coerceIn(0f, 1f)
        val coverage = (area / (width * height).toFloat()).coerceIn(0f, 1f)
        if (coverage < 0.02f || coverage > 0.96f || solidity < 0.45f) return 0f
        val quadWidth = (corners.maxOf { it.x } - corners.minOf { it.x })
        val quadHeight = (corners.maxOf { it.y } - corners.minOf { it.y })
        if (quadHeight <= 0f || quadWidth / quadHeight !in 0.22f..5f) return 0f
        // The previous four-extrema approximation would accept a polygon
        // around a chair, shadow, or textured background as a document. Real
        // cards/pages have four usable sides and a reasonably filled bounding
        // rectangle, including when viewed at a moderate perspective angle.
        if (area / (quadWidth * quadHeight).coerceAtLeast(1f) < 0.58f) return 0f
        for (i in corners.indices) {
            val before = corners[(i + 3) % 4]
            val at = corners[i]
            val after = corners[(i + 1) % 4]
            val ux = before.x - at.x
            val uy = before.y - at.y
            val vx = after.x - at.x
            val vy = after.y - at.y
            val ul = kotlin.math.sqrt(ux * ux + uy * uy)
            val vl = kotlin.math.sqrt(vx * vx + vy * vy)
            if (ul < min(width, height) * .09f || vl < min(width, height) * .09f) return 0f
            val cos = abs((ux * vx + uy * vy) / (ul * vl))
            if (cos > .91f) return 0f // almost straight or pinched corner
        }
        var onBorder = 0
        for (idx in component) {
            val x = idx % width
            val y = idx / width
            if (x == 0 || y == 0 || x == width - 1 || y == height - 1) onBorder++
        }
        val borderTotal = (2 * width + 2 * height - 4).coerceAtLeast(1)
        val borderFraction = (onBorder.toFloat() / borderTotal).coerceIn(0f, 1f)
        // A valid fully visible document must have a closed boundary; a
        // region touching a large portion of the image edge is background.
        if (borderFraction > .16f) return 0f
        val cx = corners.sumOf { it.x.toDouble() }.toFloat() / (corners.size * width)
        val cy = corners.sumOf { it.y.toDouble() }.toFloat() / (corners.size * height)
        val centrality = (1f - (abs(cx - .5f) + abs(cy - .5f))).coerceIn(0f, 1f)
        val sizeScore = (coverage / .15f).coerceIn(0f, 1f)
        return solidity * (1f - .9f * borderFraction) *
            (.40f + .35f * centrality + .25f * sizeScore)
    }

    /** Shoelace area of a polygon in pixel space. */
    private fun polygonArea(pts: List<PointF>): Float {
        var sum = 0f
        for (i in pts.indices) {
            val a = pts[i]
            val b = pts[(i + 1) % pts.size]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2f
    }

    /**
     * Run [detect] on a still image already on disk (e.g. one imported from
     * the gallery). Decodes the file, bakes in any EXIF orientation, then
     * detects on a downscaled luma copy — the normalized quad is
     * resolution-independent, so the downscale only affects speed.
     *
     * [polarity] and [thresholdOffset] carry the same meaning as on [detect];
     * callers pass the session's `ScannerConfig` values so an imported photo
     * segments exactly the way the live preview does.
     *
     * Returns a map of `{ "quad": <normalized quad map> | null, "imageSize":
     * [width, height] }` in the EXIF-upright pixel space (the same space the
     * warp operates in). Throws [ScannerException.CaptureFailed] when the file
     * cannot be decoded.
     */
    fun detectInFile(
        path: String,
        polarity: DetectionPolarity = DetectionPolarity.BRIGHTER,
        thresholdOffset: Int = DEFAULT_THRESHOLD_OFFSET,
        preferIdCardBounds: Boolean = false,
    ): Map<String, Any?> {
        // Keep the detector and perspective warper in the same EXIF-upright,
        // memory-bounded pixel space. Decoding a 6000px gallery image at full
        // resolution could otherwise OOM before returning any corners.
        val upright = ExifRotator.decodeUpright(path)
            ?: throw ScannerException.CaptureFailed("Decode failed: $path")
        try {
            val quad = detectInBitmap(upright, polarity, thresholdOffset,
                preferIdCardBounds)
            return mapOf(
                "quad" to quad?.toMap(),
                "imageSize" to listOf(upright.width.toDouble(), upright.height.toDouble()),
            )
        } finally {
            upright.recycle()
        }
    }

    /** Detect from the actual upright shutter bitmap, not the lower-resolution
     *  analysis preview. This avoids applying stale preview-frame coordinates
     *  to a still frame with a different sensor crop/rotation.
     */
    fun detectInBitmap(
        bitmap: Bitmap,
        polarity: DetectionPolarity = DetectionPolarity.BRIGHTER,
        thresholdOffset: Int = DEFAULT_THRESHOLD_OFFSET,
        preferIdCardBounds: Boolean = false,
    ): Quad? {
        // The reference OpenCV pipeline is primary, including gallery imports.
        // Keep a chroma-aware fallback for pale documents on coloured fabric;
        // without it a missed still quad silently saves the entire camera
        // frame (the incorrect third page in the supplied video).
        val cvQuad = OpenCvBoundaryAdapter.detectStill(bitmap, preferIdCardBounds)
        // ID mode keeps its strict OpenCV card selector. On imported photos
        // with a dark table background, independently segment the *outer*
        // card before giving up. This fallback is card-shaped/centred and
        // cannot promote a large A4 form behind a small card.
        val w = bitmap.width
        val h = bitmap.height
        val scale = min(1.0, 512.0 / max(w, h))
        val dw = max(16, (w * scale).toInt())
        val dh = max(16, (h * scale).toInt())
        val small = if (dw == w && dh == h) bitmap
                    else Bitmap.createScaledBitmap(bitmap, dw, dh, true)
        val pixels = IntArray(dw * dh)
        try {
            small.getPixels(pixels, 0, dw, 0, 0, dw, dh)
        } finally {
            if (small !== bitmap) small.recycle()
        }
        // Extra native evidence is computed on the existing 512px upright
        // working image, never on CameraX live frames or the large raw JPEG.
        // If the .so is absent or a proposal is ambiguous, all old paths work.
        val native = NativePageScanner.detectArgb(
            pixels, dw, dh, preferCard = preferIdCardBounds)
        if (preferIdCardBounds) {
            val contrast = detectBackgroundContrastPage(pixels, dw, dh)
            val neutral = detectNeutralPaper(pixels, dw, dh)
            // Gold/coloured cards over ruled white paper are often close in
            // luma to the desk. Background-difference masks then merge the
            // long notebook lines with the card; a coherent colour-panel
            // proposal can recover its actual outside without tracing text.
            val colouredCard = detectSaturatedPanel(pixels, dw, dh)
            val smallColouredCard = detectColoredCardOnNeutralPage(pixels, dw, dh)
            val nativeCard = native?.quad?.takeIf {
                native.confidence >= .72f &&
                    StillCaptureCropSafety.isCredibleCard(it, dw, dh)
            }
            val nativeColor = native?.quad?.takeIf {
                native.mode == 0 && native.confidence >= .74f &&
                    StillCaptureCropSafety.isCredibleColorCard(it, dw, dh)
            }
            val bestColor = listOfNotNull(smallColouredCard, nativeColor)
                .maxByOrNull { StillCaptureCropSafety.area(it) }
            return StillCaptureCropSafety.chooseCardStillBoundary(
                cvQuad, contrast, neutral, dw, dh,
                nativeCard ?: colouredCard, bestColor)
        }
        // The independently segmented outside sheet must outweigh any inner
        // text rectangle, but cannot displace an equally sized strong CV page.
        val neutralQuad = detectNeutralPaper(pixels, dw, dh)
        val contrastQuad = if (cvQuad == null ||
            StillCaptureCropSafety.area(cvQuad) < .48 ||
            StillCaptureCropSafety.isSuspiciousInteriorStrip(cvQuad, dw, dh)) {
            detectBackgroundContrastPage(pixels, dw, dh)
        } else null
        val saturatedPanelQuad = if (cvQuad == null ||
            StillCaptureCropSafety.area(cvQuad) < .28) {
            detectSaturatedPanel(pixels, dw, dh)
                ?.takeIf { cvQuad == null ||
                    StillCaptureCropSafety.encloses(it, cvQuad) }
        } else null
        // A confident, independently segmented gold ID may be a better
        // document than a broad near-frame notebook contour.
        val nativeColorCard = native?.quad?.takeIf {
            native.mode == 0 && native.confidence >= .78f &&
                StillCaptureCropSafety.isCredibleColorCard(it, dw, dh)
        }
        if (StillCaptureCropSafety.verifiedColorCardOverBackground(
                cvQuad, nativeColorCard, dw, dh)) {
            return nativeColorCard
        }
        val nativePage = native?.quad?.takeIf {
            native.confidence >= .75f &&
                StillCaptureCropSafety.isCrediblePage(it, dw, dh)
        }
        val wholePage = listOfNotNull(
                neutralQuad, contrastQuad, saturatedPanelQuad, nativePage)
            .filter { StillCaptureCropSafety.isCrediblePage(it, dw, dh) }
            .maxByOrNull { StillCaptureCropSafety.area(it) }
        if (cvQuad != null) {
            // Mask segmentations are boundary *proposals*, not a replacement
            // for good contour corners. Promote only a credible outer page
            // substantially larger than the existing CV quad.
            if (wholePage != null &&
                StillCaptureCropSafety.shouldPreferPaperMask(
                    cvQuad, wholePage, dw, dh)) return wholePage
            return cvQuad
        }
        if (wholePage != null) return wholePage
        // Retain the older small-card/receipt fallback when there is no CV
        // result; the page-only preference above must not remove that option.
        if (neutralQuad != null) return neutralQuad
        if (contrastQuad != null) return contrastQuad
        val luma = ByteArray(dw * dh)
        for (i in pixels.indices) {
            val p = pixels[i]
            val r = (p shr 16) and 0xFF
            val g = (p shr 8) and 0xFF
            val b = p and 0xFF
            // Rec.601 luma, integer weights (77/150/29 ~= /256).
            luma[i] = (((r * 77 + g * 150 + b * 29) shr 8) and 0xFF).toByte()
        }
        return detect(luma, dw, dh, polarity, thresholdOffset)
    }

    /**
     * Threshold the frame around its own mean luma, biased by [offset] onto
     * the side the document is expected to be on.
     *
     * With [darker] false this is the original paper-bright rule: keep pixels
     * above `mean + offset`. With [darker] true it is its mirror image: keep
     * pixels below `mean - offset`, so a dark ID card or a saturated trading
     * card on a light desk becomes the component instead of the desk. The
     * clamps mirror too (`60..220` becomes `35..195`), keeping the mask off
     * the extremes where a blown-out or crushed frame yields nothing usable.
     */
    private fun buildMask(luma: ByteArray, darker: Boolean, offset: Int): BooleanArray {
        var sum = 0L
        for (b in luma) sum += b.toInt() and 0xFF
        val mean = (sum / luma.size).toInt()
        val mask = BooleanArray(luma.size)
        if (darker) {
            val threshold = (mean - offset).coerceIn(35, 195)
            for (i in luma.indices) {
                mask[i] = (luma[i].toInt() and 0xFF) < threshold
            }
        } else {
            val threshold = (mean + offset).coerceIn(60, 220)
            for (i in luma.indices) {
                mask[i] = (luma[i].toInt() and 0xFF) > threshold
            }
        }
        return mask
    }

    /** Keep the largest viable blobs rather than only the single biggest. */
    private fun largestComponents(
        mask: BooleanArray, w: Int, h: Int, maxCandidates: Int = 12,
    ): List<IntArray> {
        val labels = IntArray(mask.size) { -1 }
        val candidates = ArrayList<IntArray>(maxCandidates)
        val minimumSize = (w * h / 50).coerceAtLeast(4)
        val stack = IntArray(mask.size)
        // One scratch buffer for every component, copied out only when a
        // component turns out to be the largest so far. A darker-polarity
        // mask over a page of text yields hundreds of small components, and
        // a full-size allocation per component is real GC pressure at 15 Hz.
        val collected = IntArray(mask.size)
        for (start in mask.indices) {
            if (!mask[start] || labels[start] != -1) continue
            // BFS / flood fill iterative.
            var top = 0
            stack[top++] = start
            labels[start] = start
            var collectedSize = 0
            while (top > 0) {
                val idx = stack[--top]
                collected[collectedSize++] = idx
                val x = idx % w
                val y = idx / w
                val neighbors = intArrayOf(
                    if (x > 0) idx - 1 else -1,
                    if (x < w - 1) idx + 1 else -1,
                    if (y > 0) idx - w else -1,
                    if (y < h - 1) idx + w else -1,
                )
                for (n in neighbors) {
                    if (n >= 0 && mask[n] && labels[n] == -1) {
                        labels[n] = start
                        stack[top++] = n
                    }
                }
            }
            if (collectedSize >= minimumSize &&
                (candidates.size < maxCandidates ||
                    collectedSize > candidates.last().size)) {
                val component = collected.copyOf(collectedSize)
                val pos = candidates.indexOfFirst { it.size < collectedSize }
                if (pos == -1) candidates.add(component)
                else candidates.add(pos, component)
                if (candidates.size > maxCandidates) candidates.removeAt(candidates.lastIndex)
            }
        }
        return candidates
    }

    private fun traceBoundary(component: IntArray, w: Int, h: Int): List<PointF>? {
        // A pixel is a boundary if any of its 4-neighbors is NOT in the component.
        val inComp = BooleanArray(w * h)
        for (idx in component) inComp[idx] = true
        val result = ArrayList<PointF>(component.size / 4 + 8)
        for (idx in component) {
            val x = idx % w
            val y = idx / w
            val isBoundary =
                x == 0 || y == 0 || x == w - 1 || y == h - 1 ||
                !inComp[idx - 1] || !inComp[idx + 1] ||
                !inComp[idx - w] || !inComp[idx + w]
            if (isBoundary) result.add(PointF(x.toFloat(), y.toFloat()))
        }
        return if (result.size < 4) null else result
    }

    private fun convexHull(points: List<PointF>): List<PointF> {
        if (points.size < 3) return points
        val sorted = points.sortedWith(compareBy({ it.x }, { it.y }))
        val lower = ArrayList<PointF>()
        for (p in sorted) {
            while (lower.size >= 2 && cross(lower[lower.size - 2], lower[lower.size - 1], p) <= 0)
                lower.removeAt(lower.size - 1)
            lower.add(p)
        }
        val upper = ArrayList<PointF>()
        for (p in sorted.reversed()) {
            while (upper.size >= 2 && cross(upper[upper.size - 2], upper[upper.size - 1], p) <= 0)
                upper.removeAt(upper.size - 1)
            upper.add(p)
        }
        if (lower.isNotEmpty()) lower.removeAt(lower.size - 1)
        if (upper.isNotEmpty()) upper.removeAt(upper.size - 1)
        return lower + upper
    }

    private fun cross(O: PointF, A: PointF, B: PointF): Float =
        (A.x - O.x) * (B.y - O.y) - (A.y - O.y) * (B.x - O.x)

    /**
     * Reduce a convex hull to its 4 dominant corners by picking the hull
     * points that extremize (x+y), (x-y), -(x+y), -(x-y) — these are the
     * TL, TR, BR, BL extents for any near-rectangular hull, robust to
     * orientation jitter.
     */
    private fun approximateQuad(hull: List<PointF>): List<PointF>? {
        if (hull.size < 4) return null
        var tl = hull[0]; var tr = hull[0]; var br = hull[0]; var bl = hull[0]
        var tlScore = Float.POSITIVE_INFINITY
        var brScore = Float.NEGATIVE_INFINITY
        var trScore = Float.NEGATIVE_INFINITY
        var blScore = Float.POSITIVE_INFINITY
        for (p in hull) {
            val sum = p.x + p.y
            val diff = p.x - p.y
            if (sum < tlScore) { tlScore = sum; tl = p }
            if (sum > brScore) { brScore = sum; br = p }
            if (diff > trScore) { trScore = diff; tr = p }
            if (diff < blScore) { blScore = diff; bl = p }
        }
        // Ensure non-degenerate (no two corners coincide).
        val set = setOf(tl, tr, br, bl)
        if (set.size < 4) return null
        return listOf(tl, tr, br, bl)
    }

    private fun normalizeAndOrder(pts: List<PointF>, w: Float, h: Float): Quad {
        val normalized = pts.map { PointF(it.x / w, it.y / h) }
        return QuadOrdering.reorderClockwise(normalized)
    }
}

object QuadOrdering {
    /** Orders 4 points into TL/TR/BR/BL based on sum and difference heuristics. */
    fun reorderClockwise(pts: List<PointF>): Quad {
        require(pts.size == 4)
        val sumSorted = pts.sortedBy { it.x + it.y }
        val tl = sumSorted.first()
        val br = sumSorted.last()
        val remaining = pts - tl - br
        val (tr, bl) = if (remaining[0].x > remaining[1].x) remaining[0] to remaining[1]
                       else remaining[1] to remaining[0]
        return Quad(tl, tr, br, bl)
    }
}
