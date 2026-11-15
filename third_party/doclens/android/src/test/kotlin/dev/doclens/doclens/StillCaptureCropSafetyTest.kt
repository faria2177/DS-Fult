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
    fun sharedViewPortPreservesEveryVisibleCornerEvenWhenStillDetectorWouldMissPaper() {
        // YUV is 300x400 in display orientation; saved EXIF-upright JPEG
        // contains the same sensor viewport at 1200x1600.
        val green = Quad(
            PointF(.13f, .18f), PointF(.82f, .12f),
            PointF(.91f, .89f), PointF(.09f, .83f),
        )
        val mapped = StillCaptureCropSafety.sharedViewportGreen(
            green, 300, 400, 1200, 1600, 90, true,
        )
        assertTrue(mapped == green)
        // A second detector finding only a printed heading cannot replace
        // the shutter selection.
        val innerText = rect(.28f, .39f, .65f, .57f)
        assertTrue(StillCaptureCropSafety.selectCameraStillBoundary(
            mappedGreen = mapped, independentlyVerifiedCard = null,
            liveGreenSeen = true, ordinaryStill = innerText,
        ) == green)
    }

    @Test
    fun sharedViewPortRejectsTransposedStillInsteadOfGuessingRotation() {
        val green = rect(.21f, .20f, .78f, .84f)
        // An EXIF-upright JPEG should have the same ViewPort aspect.
        // An unexplained transpose must go to manual review.
        assertTrue(StillCaptureCropSafety.sharedViewportGreen(
            green, 300, 400, 1600, 1200, 90, true,
        ) == null)
    }

    @Test
    fun sharedViewPortNeverApprovesAnUnmatchedJpegOrDisabledBinding() {
        val green = rect(.21f, .20f, .78f, .84f)
        assertTrue(StillCaptureCropSafety.sharedViewportGreen(
            green, 300, 400, 1920, 1080, 90, true,
        ) == null)
        assertTrue(StillCaptureCropSafety.sharedViewportGreen(
            green, 300, 400, 1200, 1600, 90, false,
        ) == null)
    }

    @Test
    fun lowContrastDeskCannotRejectGeometricallyMatchedGreen() {
        val green = rect(.17f, .16f, .83f, .88f)
        val mapped = StillCaptureCropSafety.mapGreenToStill(
            green, 300, 400, 1200, 1600,
        )
        assertTrue(mapped == green)
        val confidence = StillCaptureCropSafety.hasCapturedGreenBorderEvidence(
            green, 240, 320) { _, _ -> 0xFFECEBE8.toInt() }
        assertFalse(confidence)
        // Content confidence is not passed as an authorization argument.
        // The original green geometry wins over a detected inner label.
        assertTrue(StillCaptureCropSafety.cameraCaptureSelection(
            liveGreenSeen = true, mappedGreen = mapped,
            ordinaryStill = rect(.30f, .38f, .70f, .58f),
            independentlyVerifiedCard = null,
        ) == green)
        assertTrue(StillCaptureCropSafety.cameraCaptureSelection(
            liveGreenSeen = true, mappedGreen = null,
            ordinaryStill = rect(.30f, .38f, .70f, .58f),
            independentlyVerifiedCard = null,
        ) == null)
    }

    @Test
    fun mapGreenToStillRejectsBadAspectOrSentinel() {
        val green = rect(.17f, .16f, .83f, .88f)
        assertTrue(StillCaptureCropSafety.mapGreenToStill(
            green, 300, 400, 1920, 1080) == null)
        assertTrue(StillCaptureCropSafety.mapGreenToStill(
            rect(0f, 0f, 1f, 1f), 300, 400, 1200, 1600) == null)
    }

    @Test
    fun shutterGreenAutoCropTrustsThreePhotoSidesEvenWithDenseHandwriting() {
        val width = 240
        val height = 320
        val pixels = IntArray(width * height) { 0xFF2B344C.toInt() }
        for (y in 70 until 262) {
            for (x in 48 until 192) {
                pixels[y * width + x] = 0xFFEAE7DF.toInt()
            }
        }
        // Dense interior writing must not replace the *outer* edges.
        for (y in 115 until 235 step 12) {
            for (x in 67 until 177) {
                pixels[y * width + x] = 0xFF283045.toInt()
            }
        }
        val visibleGreen = rect(.20f, 70f / height, .80f, 262f / height)
        assertTrue(StillCaptureCropSafety.hasCapturedGreenBorderEvidence(
            visibleGreen, width, height) { x, y -> pixels[y * width + x] })
        // Image processing uses exactly visibleGreen; the competing still
        // detector's inner text-box proposal cannot change this quad.
        val chosen = StillCaptureCropSafety.selectCameraStillBoundary(
            mappedGreen = visibleGreen,
            independentlyVerifiedCard = null,
            liveGreenSeen = true,
            ordinaryStill = rect(.29f, .39f, .72f, .66f),
        )
        assertTrue(chosen == visibleGreen)
    }

    @Test
    fun photographedPageMustNotAutoCropWithShiftedOrUnrelatedGreenBox() {
        val width = 240
        val height = 320
        val pixels = IntArray(width * height) { index ->
            val x = index % width
            val y = index / width
            if (x in 48 until 192 && y in 70 until 262)
                0xFFEAE7DF.toInt() else 0xFF2B344C.toInt()
        }
        // Same scene, but camera moved and the frozen quad no longer
        // follows the actual paper. Manual Adjust is the safe fallback.
        val shifted = rect(.30f, .31f, .90f, .91f)
        assertFalse(StillCaptureCropSafety.hasCapturedGreenBorderEvidence(
            shifted, width, height) { x, y -> pixels[y * width + x] })
        assertFalse(StillCaptureCropSafety.hasCapturedGreenBorderEvidence(
            shifted, width, height) { _, _ -> 0xFF777777.toInt() })
    }

    @Test
    fun printedColourStripeAloneCannotAuthorizeFourCornerCrop() {
        val width = 240
        val height = 320
        val pixels = IntArray(width * height) { index ->
            val y = index / width
            if (y in 135 until 153) 0xFFF4CE48.toInt()
            else 0xFF43546E.toInt()
        }
        val insideStripe = rect(.21f, .39f, .79f, .79f)
        assertFalse(StillCaptureCropSafety.hasCapturedGreenBorderEvidence(
            insideStripe, width, height) { x, y -> pixels[y * width + x] })
    }

    @Test
    fun shutterUsesExactlyGreenQuadWhenStillCorroboratesSamePaper() {
        val green = rect(.10f, .08f, .90f, .92f)
        val slightlyShiftedStill = rect(.115f, .095f, .885f, .905f)
        // Still-only detector may be 1–2% inside the true outside border.
        // Its corroboration licenses the *green* corners, not its own ones.
        assertTrue(StillCaptureCropSafety.sameDocumentAsLivePreview(
            green, slightlyShiftedStill, 900, 1200, 1800, 2400))
    }

    @Test
    fun shutterCannotReplaceGreenDocumentWithAnInnerPrintedTable() {
        val green = rect(.08f, .07f, .92f, .93f)
        val printedTable = rect(.19f, .25f, .81f, .76f)
        assertFalse(StillCaptureCropSafety.sameDocumentAsLivePreview(
            green, printedTable, 900, 1200, 1800, 2400))
    }

    @Test
    fun shutterNeverTrustsUnmatchedStillGeometryOrOrientation() {
        val green = rect(.10f, .08f, .90f, .92f)
        val shifted = rect(.21f, .08f, .99f, .92f)
        assertFalse(StillCaptureCropSafety.sameDocumentAsLivePreview(
            green, shifted, 900, 1200, 1800, 2400))
        assertFalse(StillCaptureCropSafety.sameDocumentAsLivePreview(
            green, green, 900, 1200, 2400, 1800))
        assertFalse(StillCaptureCropSafety.sameDocumentAsLivePreview(
            green, null, 900, 1200, 1800, 2400))
    }

    @Test
    fun greenOutsideEdgeCannotAuthorizeCropOfUnrelatedStill() {
        val green = rect(.10f, .08f, .90f, .92f)
        val almostFullFrame = rect(.01f, .01f, .99f, .99f)
        assertFalse(StillCaptureCropSafety.sameDocumentAsLivePreview(
            green, almostFullFrame, 900, 1200, 1800, 2400))
    }

    @Test
    fun visibleNotebookGreenIsSavedForReviewAcrossSizeClassGap() {
        val leftGreySheet = rect(.21f, .22f, .80f, .86f)
        // A prominent live green page can occupy 38% of the view, outside
        // the tiny-card gate and with perspective outside a strict A4 ratio.
        assertTrue(StillCaptureCropSafety.isSafeDisplayedGreenForReview(
            leftGreySheet, 360, 480))
        assertFalse(StillCaptureCropSafety.isCredibleSmallDisplayedCard(
            leftGreySheet, 360, 480))
        assertFalse(StillCaptureCropSafety.isSafeDisplayedGreenForReview(
            rect(0f, 0f, 1f, 1f), 360, 480))
    }

    @Test
    fun previewGreenKeepsExactlySameFourCornersInUprightStillReview() {
        // Portrait camera captures one page of an open notebook; the still
        // detector misses it because of pencil marks and a second ruled page.
        val green = rect(.22f, .22f, .80f, .84f)
        val mapped = StillCaptureCropSafety.projectGreenToCapturedStill(
            green, 300, 400, 1200, 1600, 90)
        assertTrue(mapped == green)
    }

    @Test
    fun portraitGreenCannotBeWarpedIntoIncompatibleLandscapeStill() {
        val green = rect(.21f, .20f, .78f, .84f)
        // No unverified 90/270 transform. Only the same EXIF-upright
        // camera ViewPort is eligible for an automatic crop.
        assertTrue(StillCaptureCropSafety.projectGreenToCapturedStill(
            green, 300, 400, 1600, 1200, 90) == null)
        assertTrue(StillCaptureCropSafety.projectGreenToCapturedStill(
            green, 300, 400, 1600, 1200, 270) == null)
    }

    @Test
    fun cameraGreenReviewNeverGuessesIncompatibleFovOrMissingRotation() {
        val green = rect(.21f, .20f, .78f, .84f)
        assertTrue(StillCaptureCropSafety.projectGreenToCapturedStill(
            green, 300, 400, 1920, 1080, 90) == null)
        assertTrue(StillCaptureCropSafety.projectGreenToCapturedStill(
            green, 300, 400, 1600, 1200, 0) == null)
        assertTrue(StillCaptureCropSafety.projectGreenToCapturedStill(
            rect(0f, 0f, 1f, 1f), 300, 400, 1200, 1600, 90) == null)
    }

    @Test
    fun unmatchedGreenMustNotBeReplacedByDifferentStillCardBoundary() {
        val previewGreen = rect(.34f, .35f, .61f, .67f)
        val stillCard = rect(.24f, .35f, .78f, .62f)
        val mistakenStillContour = rect(.39f, .37f, .59f, .67f)
        // This is what the latest three screenshots demonstrate: the
        // upright preview green shape cannot be copied to captured still
        // pixels after CameraX changes orientation and field of view.
        val chosen = StillCaptureCropSafety.selectCameraStillBoundary(
            mappedGreen = null,
            independentlyVerifiedCard = stillCard,
            liveGreenSeen = true,
            ordinaryStill = mistakenStillContour,
        )
        // The separate still card may be offset from the quad the user
        // actually saw. Never silently crop that other boundary.
        assertTrue(chosen == null)
        assertFalse(chosen == previewGreen)
        assertTrue(StillCaptureCropSafety.selectCameraStillBoundary(
            mappedGreen = null, independentlyVerifiedCard = null,
            liveGreenSeen = true, ordinaryStill = mistakenStillContour,
        ) == null)
        // Without visible green, traditional safe still-image selection is
        // still available (e.g. camera captured before detection appeared).
        assertTrue(StillCaptureCropSafety.selectCameraStillBoundary(
            mappedGreen = null, independentlyVerifiedCard = stillCard,
            liveGreenSeen = false, ordinaryStill = mistakenStillContour,
        ) == stillCard)
    }

    @Test
    fun cameraMappedGreenStillTakesPriorityWhenIndependentlyConfirmed() {
        val verifiedGreen = rect(.26f, .35f, .77f, .62f)
        val stillCard = rect(.24f, .33f, .80f, .65f)
        assertTrue(StillCaptureCropSafety.selectCameraStillBoundary(
            mappedGreen = verifiedGreen, independentlyVerifiedCard = stillCard,
            liveGreenSeen = true, ordinaryStill = null,
        ) == verifiedGreen)
    }

    @Test
    fun capturedSmallCardUsesRotatedGreenEdgesNotWiderClothBoundary() {
        // In the supplied video the live image is upright and portrait,
        // while the JPEG may contain the same card rotated clockwise.
        val visibleGreen = rect(.33f, .31f, .61f, .67f)
        val independentCard = rect(.341f, .340f, .681f, .600f)
        val verified = StillCaptureCropSafety.verifiedSmallGreenOnStill(
            visibleGreen, independentCard, 320, 420, 420, 320)
        assertTrue(verified != null)
        // The independent detector checks the paper but does NOT become
        // the crop target. Returned corners are the transformed GREEN box.
        assertTrue(kotlin.math.abs(verified.topLeft.x - .33f) < .0001f)
        assertTrue(kotlin.math.abs(verified.topLeft.y - .33f) < .0001f)
        assertTrue(kotlin.math.abs(verified.bottomRight.x - .69f) < .0001f)
        assertTrue(kotlin.math.abs(verified.bottomRight.y - .61f) < .0001f)
    }

    @Test
    fun greenCaptureRejectsUnrelatedLargeBackgroundRectangle() {
        val visibleGreen = rect(.33f, .31f, .61f, .67f)
        val largeCloth = rect(.05f, .05f, .95f, .95f)
        assertTrue(StillCaptureCropSafety.verifiedSmallGreenOnStill(
            visibleGreen, largeCloth, 320, 420, 420, 320) == null)
        assertTrue(StillCaptureCropSafety.verifiedSmallGreenOnStill(
            visibleGreen, null, 320, 420, 420, 320) == null)
    }

    @Test
    fun greenCaptureDoesNotForceCropOnIncompatibleSensorAspect() {
        val visibleGreen = rect(.33f, .31f, .61f, .67f)
        val captured = rect(.33f, .33f, .69f, .61f)
        assertTrue(StillCaptureCropSafety.verifiedSmallGreenOnStill(
            visibleGreen, captured, 320, 420, 1920, 1080) == null)
    }

    @Test
    fun video382753SmallGreenCardIsNotDiscardedByA4PageThreshold() {
        // Live frame: small, 90°-rotated landscape business card on patterned
        // fabric. Its four real corners cover only ~10% of the preview.
        val green = rect(.32f, .32f, .61f, .67f)
        assertFalse(StillCaptureCropSafety.isCrediblePage(green, 320, 420))
        assertTrue(StillCaptureCropSafety.isCredibleSmallDisplayedCard(
            green, 320, 420))
        // The still's different CameraX content orientation makes the SAME
        // card landscape and visually larger; do not compare raw x/y corners.
        val still = rect(.21f, .37f, .81f, .61f)
        assertTrue(StillCaptureCropSafety.sameSmallPaperCardAsLive(
            green, still, 320, 420, 320, 420))
        assertFalse(StillCaptureCropSafety.sameDocumentAsLivePreview(
            green, still, 320, 420, 320, 420))
    }

    @Test
    fun tinyNameBoxAndMismatchedCardCannotBorrowGreenCapture() {
        val green = rect(.32f, .32f, .61f, .67f)
        val tinyNameBox = rect(.41f, .47f, .58f, .54f)
        val otherCard = rect(.01f, .12f, .50f, .41f)
        assertFalse(StillCaptureCropSafety.isCredibleSmallDisplayedCard(
            tinyNameBox, 320, 420))
        assertFalse(StillCaptureCropSafety.sameSmallPaperCardAsLive(
            green, otherCard, 320, 420, 320, 420))
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

    @Test
    fun fullIdCardCanRecoverWhenOpenCvOnlyFindsAnInnerNameBlock() {
        val card = rect(.12f, .23f, .88f, .79f)
        val name = rect(.29f, .43f, .69f, .56f)
        assertTrue(StillCaptureCropSafety.isCredibleCard(card, 1200, 900))
        assertFalse(StillCaptureCropSafety.isCredibleCard(name, 1200, 900))
        assertTrue(StillCaptureCropSafety.chooseCardStillBoundary(
            name, card, null, 1200, 900) == card)
        assertTrue(StillCaptureCropSafety.chooseCardStillBoundary(
            null, card, null, 1200, 900) == card)
    }

    @Test
    fun cardFallbackCannotPreferUnrelatedOrDocumentSizedBackground() {
        val name = rect(.29f, .43f, .69f, .56f)
        val unrelated = rect(.02f, .20f, .65f, .70f)
        val wholeFrame = rect(.02f, .02f, .98f, .98f)
        assertFalse(StillCaptureCropSafety.isCredibleCard(wholeFrame, 1200, 900))
        assertTrue(StillCaptureCropSafety.chooseCardStillBoundary(
            name, unrelated, wholeFrame, 1200, 900) == name)
    }

    @Test
    fun ruledNotebookContourMustYieldToGoldCardPanel() {
        val notebook = rect(.03f, .03f, .97f, .97f)
        val goldCard = rect(.18f, .13f, .94f, .84f)
        assertFalse(StillCaptureCropSafety.isCredibleCard(notebook, 416, 741))
        assertTrue(StillCaptureCropSafety.isCredibleCard(goldCard, 416, 741))
        assertTrue(StillCaptureCropSafety.chooseCardStillBoundary(
            notebook, null, null, 416, 741, saturated = goldCard) == goldCard)
        // The opposite direction would erase an already correct outside card.
        assertTrue(StillCaptureCropSafety.chooseCardStillBoundary(
            goldCard, null, null, 416, 741, saturated = rect(.30f, .40f, .75f, .63f))
            == goldCard)
    }

    @Test
    fun independentColorEvidenceRecoversSmallCardWithoutRelaxingPageRules() {
        val notebook = rect(.02f, .02f, .98f, .98f)
        val smallCard = rect(.295f, .26f, .705f, .75f)
        assertFalse(StillCaptureCropSafety.isCredibleCard(smallCard, 320, 420))
        assertTrue(StillCaptureCropSafety.isCredibleColorCard(smallCard, 320, 420))
        assertTrue(StillCaptureCropSafety.chooseCardStillBoundary(
            notebook, null, null, 320, 420, colorCard = smallCard) == smallCard)

        val innerLabel = rect(.39f, .44f, .62f, .57f)
        assertFalse(StillCaptureCropSafety.isCredibleColorCard(innerLabel, 320, 420))
        assertTrue(StillCaptureCropSafety.chooseCardStillBoundary(
            notebook, null, null, 320, 420, colorCard = innerLabel) == notebook)
    }

    @Test
    fun cameraShutterMayTrustVerifiedCardButNotPrintedA4Label() {
        val notebook = rect(.02f, .02f, .98f, .98f)
        val wholeA4 = rect(.10f, .10f, .90f, .90f)
        val card = rect(.295f, .26f, .705f, .75f)
        assertTrue(StillCaptureCropSafety.verifiedColorCardOverBackground(
            notebook, card, 320, 420))
        assertTrue(StillCaptureCropSafety.verifiedColorCardOverBackground(
            null, card, 320, 420))
        assertTrue(StillCaptureCropSafety.verifiedColorCardOverBackground(
            card, card, 320, 420))
        assertFalse(StillCaptureCropSafety.verifiedColorCardOverBackground(
            wholeA4, card, 320, 420))
        assertFalse(StillCaptureCropSafety.verifiedColorCardOverBackground(
            notebook, rect(.40f, .45f, .60f, .58f), 320, 420))
    }
}
