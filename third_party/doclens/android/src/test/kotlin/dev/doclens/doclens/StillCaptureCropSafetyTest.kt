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
