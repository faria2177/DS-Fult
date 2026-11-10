package dev.doclens.doclens

import kotlin.math.floor
import kotlin.math.sqrt

/**
 * Compares the *pixels* of a recent camera-analysis frame with a captured still.
 *
 * EXIF flags and aspect ratios alone do not establish that the document is
 * upright: some CameraX devices report a portrait JPEG containing sideways
 * sensor pixels. A confident content match lets us correct that image without
 * assuming the orientation of the printed text or of the paper itself.
 *
 * All inputs are low-resolution luminance planes. No Bitmap/Android APIs are
 * used here, so rotation choice can be regression-tested on the JVM.
 */
internal object CaptureOrientationMatcher {
    data class Image(val pixels: ByteArray, val width: Int, val height: Int) {
        fun valid(): Boolean = width >= 24 && height >= 24 &&
            pixels.size == width * height
    }

    data class Match(
        val clockwiseTurns: Int,
        val score: Double,
        val margin: Double,
        val scale: Double,
        val shiftX: Double,
        val shiftY: Double,
    ) {
        /** Map live-overlay corners into the aligned, clockwise-rotated JPEG. */
        fun mapPreviewQuad(quad: Quad): Quad? {
            fun point(p: PointF) = PointF(
                (.5 + (p.x.toDouble() - .5) * scale + shiftX).toFloat(),
                (.5 + (p.y.toDouble() - .5) * scale + shiftY).toFloat(),
            )
            val mapped = Quad(point(quad.topLeft), point(quad.topRight),
                point(quad.bottomRight), point(quad.bottomLeft))
            val points = listOf(mapped.topLeft, mapped.topRight,
                mapped.bottomRight, mapped.bottomLeft)
            return mapped.takeIf { points.all { p ->
                p.x in 0f..1f && p.y in 0f..1f
            } }
        }
    }

    private data class Alignment(
        val score: Double, val scale: Double, val shiftX: Double, val shiftY: Double,
    )

    /**
     * `previewRotation` is CameraX ImageAnalysis.imageInfo.rotationDegrees.
     * The still has already had its EXIF applied before this comparison.
     * Null means the frames cannot be registered reliably; do not infer a turn.
     */
    fun find(
        preview: Image,
        previewRotation: Int,
        still: Image,
    ): Match? {
        if (!preview.valid() || !still.valid()) return null
        val upright = ((previewRotation % 360) + 360) % 360
        if (upright !in listOf(0, 90, 180, 270)) return null

        // Search small framing shifts/zoom differences between Preview and
        // ImageCapture. This also prevents a different aspect ratio alone from
        // being mistaken for proof of a missing EXIF quarter-turn.
        val alignments = (0..3).map { turns ->
            var best = Alignment(-1.0, 1.0, 0.0, 0.0)
            for (scale in doubleArrayOf(.87, .94, 1.0, 1.07)) {
                for (shiftY in doubleArrayOf(-.09, 0.0, .09)) {
                    for (shiftX in doubleArrayOf(-.09, 0.0, .09)) {
                        val score = correlation(preview, upright, still, turns,
                            scale, shiftX, shiftY)
                        if (score > best.score) {
                            best = Alignment(score, scale, shiftX, shiftY)
                        }
                    }
                }
            }
            best
        }
        val ordered = alignments.indices.sortedByDescending { alignments[it].score }
        val first = ordered[0]
        val second = ordered[1]
        val winner = alignments[first]
        val margin = winner.score - alignments[second].score
        // A repeated/symmetric table pattern, plain paper or a changed scene
        // can give deceptively similar scores for multiple orientations.
        if (winner.score < .58 || margin < .14) return null
        return Match(first, winner.score, margin,
            winner.scale, winner.shiftX, winner.shiftY)
    }

    private fun correlation(
        preview: Image, rotation: Int, still: Image, turns: Int,
        scale: Double, shiftX: Double, shiftY: Double,
    ): Double {
        var sumA = 0.0
        var sumB = 0.0
        var sumAA = 0.0
        var sumBB = 0.0
        var sumAB = 0.0
        var count = 0
        // An interior grid keeps black preview controls, borders and tiny
        // position changes out of the comparison; its document/table texture
        // disambiguates quarter-turns on high-detail pages.
        for (y in 0 until 38) {
            val v = .10 + (y + .5) * .80 / 38
            for (x in 0 until 30) {
                val u = .10 + (x + .5) * .80 / 30
                val (pu, pv) = sourcePoint(u, v, rotation / 90)
                val su = .5 + (u - .5) * scale + shiftX
                val sv = .5 + (v - .5) * scale + shiftY
                if (su !in 0.0..1.0 || sv !in 0.0..1.0) continue
                val (cu, cv) = sourcePoint(su, sv, turns)
                val a = sample(preview, pu, pv)
                val b = sample(still, cu, cv)
                sumA += a
                sumB += b
                sumAA += a * a
                sumBB += b * b
                sumAB += a * b
                count++
            }
        }
        if (count < 900) return -1.0
        val varianceA = sumAA - sumA * sumA / count
        val varianceB = sumBB - sumB * sumB / count
        if (varianceA < count * 60.0 || varianceB < count * 60.0) return -1.0
        return ((sumAB - sumA * sumB / count) /
            sqrt(varianceA * varianceB)).coerceIn(-1.0, 1.0)
    }

    /** Inverse of a clockwise display rotation, in normalized coordinates. */
    private fun sourcePoint(x: Double, y: Double, turns: Int): Pair<Double, Double> =
        when (((turns % 4) + 4) % 4) {
            1 -> y to (1.0 - x)
            2 -> (1.0 - x) to (1.0 - y)
            3 -> (1.0 - y) to x
            else -> x to y
        }

    private fun sample(image: Image, x: Double, y: Double): Double {
        val px = (x * (image.width - 1)).coerceIn(0.0, (image.width - 1).toDouble())
        val py = (y * (image.height - 1)).coerceIn(0.0, (image.height - 1).toDouble())
        val x0 = floor(px).toInt()
        val y0 = floor(py).toInt()
        val x1 = (x0 + 1).coerceAtMost(image.width - 1)
        val y1 = (y0 + 1).coerceAtMost(image.height - 1)
        val tx = px - x0
        val ty = py - y0
        fun at(xx: Int, yy: Int) =
            (image.pixels[yy * image.width + xx].toInt() and 0xff).toDouble()
        val top = at(x0, y0) * (1.0 - tx) + at(x1, y0) * tx
        val bottom = at(x0, y1) * (1.0 - tx) + at(x1, y1) * tx
        return top * (1.0 - ty) + bottom * ty
    }
}
