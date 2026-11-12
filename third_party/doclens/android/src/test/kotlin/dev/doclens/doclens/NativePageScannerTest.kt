package dev.doclens.doclens

import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

/** Pure JVM contract validation: no Android .so required for these tests. */
class NativePageScannerTest {
    private val sample = floatArrayOf(
        .20f, .20f, .80f, .20f, .80f, .75f, .20f, .75f,
        .91f, 0f
    )

    @Test fun acceptsACompleteColorCard() {
        val c = assertNotNull(NativePageScanner.validateResult(
            sample, 640, 480, preferCard = true))
        assertEquals(0, c.mode)
        assertEquals(.91f, c.confidence)
    }

    @Test fun refusesCrossedOrDegenerateCorners() {
        val crossed = sample.clone()
        crossed[2] = .20f
        crossed[3] = .75f
        assertNull(NativePageScanner.validateResult(
            crossed, 640, 480, preferCard = false))
    }

    @Test fun refusesOutOfBoundsAndNonFiniteValues() {
        val outside = sample.clone()
        outside[0] = -.5f
        assertNull(NativePageScanner.validateResult(
            outside, 640, 480, preferCard = true))
        val nan = sample.clone()
        nan[4] = Float.NaN
        assertNull(NativePageScanner.validateResult(
            nan, 640, 480, preferCard = true))
    }

    @Test fun refusesLowConfidenceAndBadMode() {
        val weak = sample.clone()
        weak[8] = .25f
        assertNull(NativePageScanner.validateResult(
            weak, 640, 480, preferCard = false))
        val mode = sample.clone()
        mode[9] = 25f
        assertNull(NativePageScanner.validateResult(
            mode, 640, 480, preferCard = false))
    }

    @Test fun refusesMissingNativeResultsWithoutCrashing() {
        assertNull(NativePageScanner.validateResult(null, 640, 480, true))
        assertNull(NativePageScanner.validateResult(floatArrayOf(1f), 640, 480, true))
        assertNull(NativePageScanner.detectArgb(IntArray(5), 640, 480))
    }
}
