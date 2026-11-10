package dev.doclens.doclens

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class StillCaptureCropSafetyTest {
    private fun rect(left: Float, top: Float, right: Float, bottom: Float) = Quad(
        PointF(left, top), PointF(right, top),
        PointF(right, bottom), PointF(left, bottom),
    )

    @Test
    fun portraitDocumentIsACrediblePreviewHint() {
        val page = rect(.10f, .08f, .90f, .92f)
        assertTrue(StillCaptureCropSafety.isCrediblePage(page, 900, 1200))
        assertFalse(StillCaptureCropSafety.isSuspiciousInteriorStrip(page, 900, 1200))
    }

    @Test
    fun letterBodyInsidePortraitPageMustNotBeAutoCropped() {
        val innerText = rect(.10f, .42f, .90f, .62f)
        assertTrue(StillCaptureCropSafety.isSuspiciousInteriorStrip(innerText, 900, 1200))
        assertFalse(StillCaptureCropSafety.isCrediblePage(innerText, 900, 1200))
    }

    @Test
    fun saturatedPosterWithSmallYellowLandscapeTitleKeepsWholeOriginal() {
        // Regression for video 381526.mp4: live tracking framed the full blue
        // portrait sign, but the shutter still returned only its yellow label.
        val bluePoster = rect(.16f, .22f, .84f, .83f)
        val yellowTitle = rect(.28f, .46f, .72f, .64f)
        assertFalse(StillCaptureCropSafety.isSuspiciousInteriorStrip(bluePoster, 900, 1200))
        assertTrue(StillCaptureCropSafety.isSuspiciousInteriorStrip(yellowTitle, 900, 1200))
        assertTrue(StillCaptureCropSafety.significantlySmallerThan(yellowTitle, bluePoster))
        assertTrue(StillCaptureCropSafety.encloses(bluePoster, yellowTitle))
        assertFalse(StillCaptureCropSafety.encloses(yellowTitle, bluePoster))
        assertTrue(StillCaptureCropSafety.requiresManualReview(
            yellowTitle, 900, 1200, bluePoster))
        assertFalse(StillCaptureCropSafety.requiresManualReview(
            bluePoster, 900, 1200, bluePoster))
    }

    @Test
    fun compactInteriorLabelIsUnsafeWhenStillPixelsAreLandscape() {
        val yellowTitle = rect(.29f, .41f, .71f, .59f)
        assertTrue(StillCaptureCropSafety.isSuspiciousInteriorStrip(yellowTitle, 1200, 900))
        assertTrue(StillCaptureCropSafety.requiresManualReview(
            yellowTitle, 1200, 900, null))
    }

    @Test
    fun compactInteriorLabelIsUnsafeWhenStillPixelsAreRotated() {
        val rotatedTitle = rect(.41f, .29f, .59f, .71f)
        assertTrue(StillCaptureCropSafety.isSuspiciousInteriorStrip(rotatedTitle, 900, 1200))
    }

    @Test
    fun fullLandscapePageAndEdgeTouchingDocumentAreNotRejected() {
        val landscapePage = rect(.06f, .16f, .94f, .84f)
        val closeCrop = rect(.01f, .38f, .99f, .62f)
        assertFalse(StillCaptureCropSafety.isSuspiciousInteriorStrip(landscapePage, 900, 1200))
        assertFalse(StillCaptureCropSafety.isSuspiciousInteriorStrip(closeCrop, 900, 1200))
    }

    @Test
    fun missingStillOutlineUsesRawPhotoForReview() {
        assertTrue(StillCaptureCropSafety.requiresManualReview(null, 900, 1200, null))
    }

    @Test
    fun suddenlySmallerStillQuadRequiresReview() {
        val livePage = rect(.09f, .06f, .91f, .94f)
        val innerBand = rect(.12f, .43f, .88f, .62f)
        assertTrue(StillCaptureCropSafety.significantlySmallerThan(innerBand, livePage))
        assertFalse(StillCaptureCropSafety.significantlySmallerThan(livePage, livePage))
    }

    @Test
    fun previewReviewHintRequiresCompatibleImageOrientation() {
        assertTrue(StillCaptureCropSafety.compatibleView(300, 400, 900, 1200))
        assertFalse(StillCaptureCropSafety.compatibleView(300, 400, 1920, 1080))
    }

    @Test
    fun cameraXPortraitPreviewCorrectsLandscapeJpegOnlyWhenExifIsMissing() {
        assertTrue(StillCaptureCropSafety.missingExifQuarterTurns(
            300, 400, 1200, 900, 90) == 1)
        assertTrue(StillCaptureCropSafety.missingExifQuarterTurns(
            300, 400, 1200, 900, 270) == 3)
        assertTrue(StillCaptureCropSafety.missingExifQuarterTurns(
            300, 400, 900, 1200, 90) == 0)
        assertTrue(StillCaptureCropSafety.missingExifQuarterTurns(
            400, 300, 1200, 900, 90) == 0)
        assertTrue(StillCaptureCropSafety.missingExifQuarterTurns(
            300, 400, 1920, 1080, 90) == 0)
        assertTrue(StillCaptureCropSafety.missingExifQuarterTurns(
            300, 400, 1200, 900, 0) == 0)
    }

    @Test
    fun video381772DenseInnerTableMustNotReplaceLiveA4Page() {
        val fullA4 = rect(.08f, .07f, .92f, .93f)
        val partialTable = rect(.12f, .28f, .88f, .73f)
        assertTrue(StillCaptureCropSafety.isCrediblePage(fullA4, 900, 1200))
        // A dense table can itself have four convex corners. Comparing the
        // captured still against the live sheet is required to reject it.
        assertTrue(StillCaptureCropSafety.isCrediblePage(partialTable, 900, 1200))
        assertTrue(StillCaptureCropSafety.requiresManualReview(
            partialTable, 900, 1200, fullA4))
        assertFalse(StillCaptureCropSafety.requiresManualReview(
            fullA4, 900, 1200, fullA4))
    }

    @Test
    fun outOfBoundsOrExtremelySmallQuadCannotSeedReview() {
        assertFalse(StillCaptureCropSafety.isCrediblePage(
            rect(-.05f, .01f, .90f, .95f), 900, 1200))
        assertFalse(StillCaptureCropSafety.isCrediblePage(
            rect(.35f, .40f, .65f, .60f), 900, 1200))
    }

    @Test
    fun fullPaperMaskReplacesInnerTextButNotAccuratePageCorners() {
        val wholePaper = rect(.11f, .09f, .89f, .91f)
        val innerText = rect(.15f, .44f, .85f, .61f)
        val alreadyAccuratePage = rect(.13f, .12f, .87f, .88f)
        assertTrue(StillCaptureCropSafety.shouldPreferPaperMask(
            innerText, wholePaper, 900, 1200))
        assertFalse(StillCaptureCropSafety.shouldPreferPaperMask(
            alreadyAccuratePage, wholePaper, 900, 1200))
    }
}
