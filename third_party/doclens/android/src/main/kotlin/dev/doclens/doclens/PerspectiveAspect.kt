package dev.doclens.doclens

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.sqrt

/**
 * Recovers a document's real width:height from its four corners so the
 * straightened page keeps its true shape when photographed at an angle.
 * Same method and constants as `lib/src/services/perspective_aspect.dart`
 * (Zhang & He, "Whiteboard scanning and image enhancement", 2007), with a
 * typical phone main-camera focal length of 0.75 x the photo's long side.
 */
internal object PerspectiveAspect {
    private const val FOCAL_SCALE = 0.75
    private const val SNAP_TOLERANCE = 0.03
    private const val MAX_CHANGE = 1.25
    private val STANDARD = doubleArrayOf(1.41421, 1.29412, 1.58577)

    /** Corners in pixels: top-left, top-right, bottom-right, bottom-left. */
    fun widthToHeight(corners: DoubleArray, imageWidth: Int, imageHeight: Int): Double? {
        if (corners.size != 8 || imageWidth <= 0 || imageHeight <= 0) return null
        val u0 = imageWidth / 2.0
        val v0 = imageHeight / 2.0
        fun lift(i: Int) = doubleArrayOf(corners[2 * i] - u0, corners[2 * i + 1] - v0, 1.0)
        val m1 = lift(0)
        val m2 = lift(1)
        val m4 = lift(2)
        val m3 = lift(3)
        val d2 = dot(cross(m2, m4), m3)
        val d3 = dot(cross(m3, m4), m2)
        if (abs(d2) < 1e-9 || abs(d3) < 1e-9) return null
        val k2 = dot(cross(m1, m4), m3) / d2
        val k3 = dot(cross(m1, m4), m2) / d3
        if (!k2.isFinite() || !k3.isFinite() || k2 <= 0 || k3 <= 0) return null
        val n2 = DoubleArray(3) { k2 * m2[it] - m1[it] }
        val n3 = DoubleArray(3) { k3 * m3[it] - m1[it] }
        val f = FOCAL_SCALE * max(imageWidth, imageHeight)
        val f2 = f * f
        val w2 = (n2[0] * n2[0] + n2[1] * n2[1]) / f2 + n2[2] * n2[2]
        val h2 = (n3[0] * n3[0] + n3[1] * n3[1]) / f2 + n3[2] * n3[2]
        if (w2 <= 0 || h2 <= 0) return null
        val ratio = sqrt(w2 / h2)
        return if (ratio.isFinite() && ratio > 0) ratio else null
    }

    /** Keeps the naive area, takes the corrected (and snapped) proportions. */
    fun outputSize(corners: DoubleArray, imageWidth: Int, imageHeight: Int,
                   naiveWidth: Double, naiveHeight: Double): Pair<Double, Double> {
        if (naiveWidth <= 0 || naiveHeight <= 0) return naiveWidth to naiveHeight
        val naive = naiveWidth / naiveHeight
        val estimated = widthToHeight(corners, imageWidth, imageHeight)
            ?: return naiveWidth to naiveHeight
        val ratio = snap(estimated.coerceIn(naive / MAX_CHANGE, naive * MAX_CHANGE))
        val area = naiveWidth * naiveHeight
        return sqrt(area * ratio) to sqrt(area / ratio)
    }

    fun snap(ratio: Double): Double {
        for (standard in STANDARD) {
            for (candidate in doubleArrayOf(standard, 1 / standard)) {
                if (abs(ratio / candidate - 1) <= SNAP_TOLERANCE) return candidate
            }
        }
        return ratio
    }

    private fun cross(a: DoubleArray, b: DoubleArray) = doubleArrayOf(
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )

    private fun dot(a: DoubleArray, b: DoubleArray) = a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}
