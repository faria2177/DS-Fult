package dev.doclens.doclens

import com.docscan.scanner.ScannerTuning
import org.opencv.core.Point
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class VisibleCornersTest {
    @Test
    fun centeredCardRemainsDetectable() {
        val card = arrayOf(
            Point(30.0, 30.0), Point(180.0, 25.0),
            Point(190.0, 115.0), Point(25.0, 120.0),
        )
        assertTrue(ScannerTuning.hasFourVisibleCorners(card, 240, 160))
    }

    @Test
    fun largeClippedFabricQuadrilateralIsNotAFullDocument() {
        val fabric = arrayOf(
            Point(17.0, 23.0), Point(250.0, 40.0),
            Point(237.0, 159.0), Point(11.0, 150.0),
        )
        assertFalse(ScannerTuning.hasFourVisibleCorners(fabric, 240, 160))
    }

    @Test
    fun frameTouchingAndNonFiniteCornersAreRejected() {
        val touching = arrayOf(
            Point(0.0, 20.0), Point(200.0, 20.0),
            Point(200.0, 130.0), Point(20.0, 130.0),
        )
        assertFalse(ScannerTuning.hasFourVisibleCorners(touching, 240, 160))
        val invalid = touching.copyOf()
        invalid[0] = Point(Double.NaN, 20.0)
        assertFalse(ScannerTuning.hasFourVisibleCorners(invalid, 240, 160))
    }
}
