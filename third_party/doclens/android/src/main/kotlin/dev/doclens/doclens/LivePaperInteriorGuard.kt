package dev.doclens.doclens

import kotlin.math.hypot
import kotlin.math.min

/**
 * Additional close-camera safety for white documents with dense black print.
 *
 * A page title/text region can itself be a perfect, high-contrast rectangle.
 * But the four areas OUTSIDE that rectangle remain pale document paper.
 * If at least three side margins are independently bright, the contour is
 * probably inside the page, not its physical perimeter. Hide it rather than
 * offer a green shutter crop that would cut away the heading/signature.
 *
 * Used only for live non-ID scans, after the outer-page candidate selector.
 * It never expands/invents corners and never edits the JPEG.
 */
internal object LivePaperInteriorGuard {
    /**
     * Only a fully enclosed, substantially larger frame-supported page may
     * supersede the printed rectangle. Never fabricate corner offsets from
     * a text block or select a desk/background covering most of the view.
     */
    fun recoveredOuterPage(
        printed: Quad, alternative: Quad?, width: Int, height: Int,
    ): Quad? {
        val candidate = alternative ?: return null
        val smallArea = StillCaptureCropSafety.area(printed)
        val largeArea = StillCaptureCropSafety.area(candidate)
        if (smallArea <= 0.0 ||
            largeArea < smallArea * 1.27 ||
            largeArea > smallArea * 2.65) return null
        if (!StillCaptureCropSafety.isCrediblePage(candidate, width, height) ||
            !LiveBoundarySelector.hasFourPageLikeSides(
                candidate, width, height)) return null
        if (!StillCaptureCropSafety.encloses(candidate, printed)) return null
        return candidate
    }

    fun isPrintedInterior(quad: Quad, rgba: ByteArray, width: Int, height: Int): Boolean {
        if (width < 64 || height < 64 || rgba.size != width * height * 4) return false
        val area = StillCaptureCropSafety.area(quad)
        if (area !in .16.. .76) return false
        val pts = listOf(
            quad.topLeft, quad.topRight, quad.bottomRight, quad.bottomLeft,
        )
        val centerX = pts.sumOf { it.x.toDouble() } * width / 4
        val centerY = pts.sumOf { it.y.toDouble() } * height / 4
        val step = min(width, height) * .035
        var paleMargins = 0
        var usableSides = 0
        for (side in 0 until 4) {
            val a = pts[side]
            val b = pts[(side + 1) % 4]
            val middleX = (a.x.toDouble() + b.x) * width / 2
            val middleY = (a.y.toDouble() + b.y) * height / 2
            val toOutsideX = middleX - centerX
            val toOutsideY = middleY - centerY
            val norm = hypot(toOutsideX, toOutsideY)
            if (norm < 1.0) continue
            val nx = toOutsideX / norm
            val ny = toOutsideY / norm
            var white = 0
            var valid = 0
            // Multiple positions away from printed ink prevent a black
            // heading/line on one margin from deciding the whole page.
            for (fraction in doubleArrayOf(.20, .35, .50, .65, .80)) {
                val sx = (a.x + (b.x - a.x) * fraction).toDouble() * width
                val sy = (a.y + (b.y - a.y) * fraction).toDouble() * height
                val x = (sx + nx * step).toInt()
                val y = (sy + ny * step).toInt()
                if (x !in 2 until width - 2 || y !in 2 until height - 2) continue
                val pos = (y * width + x) * 4
                val r = rgba[pos].toInt() and 255
                val g = rgba[pos + 1].toInt() and 255
                val blue = rgba[pos + 2].toInt() and 255
                val brightness = (r + g + blue) / 3
                val colourSpread = maxOf(r, g, blue) - minOf(r, g, blue)
                if (brightness >= 169 && colourSpread <= 55) white++
                valid++
            }
            if (valid >= 4) {
                usableSides++
                if (white >= 4) paleMargins++
            }
        }
        // Insufficient visible margin cannot invalidate a real page.
        return usableSides >= 3 && paleMargins >= 3
    }
}
