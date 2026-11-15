package dev.doclens.doclens

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.os.Build
import android.util.Size
import androidx.annotation.MainThread
import androidx.camera.core.CameraSelector
import androidx.camera.core.AspectRatio
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.core.SurfaceRequest
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.io.File
import java.util.concurrent.Executors

class ScannerSession(
    private val activity: Activity,
    private val context: Context,
    private val config: ScannerConfig,
    private val textureEntry: TextureRegistry.SurfaceTextureEntry,
    private val eventSink: (Map<String, Any?>) -> Unit,
) {
    private val analysisExecutor = Executors.newSingleThreadExecutor()
    private val captureExecutor = Executors.newSingleThreadExecutor()
    private val openCvDetector = OpenCvBoundaryAdapter()

    private var cameraProvider: ProcessCameraProvider? = null
    private var preview: Preview? = null
    private var analysis: ImageAnalysis? = null
    private var imageCapture: ImageCapture? = null
    private var camera: androidx.camera.core.Camera? = null

    private var lensFacing: Int = CameraSelector.LENS_FACING_BACK
    private var flashMode: Int = ImageCapture.FLASH_MODE_AUTO
    private var torch: Boolean = false

    @Volatile private var lastFrameWidth: Int = 0
    @Volatile private var lastFrameHeight: Int = 0
    @Volatile private var lastDetectionMs: Long = 0L
    @Volatile private var previewSurfaceWidth: Int = 0
    @Volatile private var previewSurfaceHeight: Int = 0
    @Volatile private var lastEmittedPreviewW: Int = 0
    @Volatile private var lastEmittedPreviewH: Int = 0
    /** Latest page-like preview shape, retained only briefly for safe review. */
    private data class PagePreviewHint(
        val quad: Quad, val timestampMs: Long, val width: Int, val height: Int,
    )
    @Volatile private var latestPagePreviewHint: PagePreviewHint? = null
    private data class FrameOrientation(
        val width: Int, val height: Int, val rotationDegrees: Int,
        val timestampMs: Long,
    )
    @Volatile private var latestFrameOrientation: FrameOrientation? = null

    init {
        lensFacing = if (config.initialLens == "front") CameraSelector.LENS_FACING_FRONT
                     else CameraSelector.LENS_FACING_BACK
        flashMode = when (config.initialFlashMode) {
            "off" -> ImageCapture.FLASH_MODE_OFF
            "on" -> ImageCapture.FLASH_MODE_ON
            "torch" -> { torch = true; ImageCapture.FLASH_MODE_OFF }
            else -> ImageCapture.FLASH_MODE_AUTO
        }
    }

    @MainThread
    fun start(completion: (Result<Long>) -> Unit) {
        if (ContextCompat.checkSelfPermission(context, android.Manifest.permission.CAMERA)
            != PackageManager.PERMISSION_GRANTED) {
            completion(Result.failure(ScannerException.PermissionDenied()))
            return
        }
        val providerFuture = ProcessCameraProvider.getInstance(context)
        providerFuture.addListener({
            try {
                val provider = providerFuture.get()
                cameraProvider = provider
                val selector = CameraSelector.Builder().requireLensFacing(lensFacing).build()
                if (!provider.hasCamera(selector)) {
                    completion(Result.failure(
                        ScannerException.Unavailable("No camera for requested lens")))
                    return@addListener
                }
                bindUseCases(provider)
                completion(Result.success(textureEntry.id()))
            } catch (e: ScannerException) {
                completion(Result.failure(e))
            } catch (e: Exception) {
                completion(Result.failure(ScannerException.InitFailed(e.message ?: "unknown")))
            }
        }, ContextCompat.getMainExecutor(context))
    }

    private fun bindUseCases(provider: ProcessCameraProvider) {
        provider.unbindAll()
        val selector = CameraSelector.Builder().requireLensFacing(lensFacing).build()
        val surfaceTexture = textureEntry.surfaceTexture()

        // Without a shared aspect ratio CameraX may pick a 16:9 preview and
        // a 4:3 analysis buffer. Normalized analysis corners then stretch
        // vertically on the preview (~33% error), even with a perfect quad.
        // Match preview, analysis and still-capture field of view on every
        // device. Flutter scales preview + overlay together using BoxFit.cover.
        preview = Preview.Builder()
            .setTargetAspectRatio(AspectRatio.RATIO_4_3)
            .build().also { p ->
            p.setSurfaceProvider { request: SurfaceRequest ->
                val res = request.resolution
                previewSurfaceWidth = res.width
                previewSurfaceHeight = res.height
                surfaceTexture.setDefaultBufferSize(res.width, res.height)

                // `request.resolution` is the sensor-natural buffer size, which
                // is landscape (e.g. 1920x1080). CameraX rotates the buffer to
                // the display orientation before it reaches the SurfaceTexture,
                // so the pixels Flutter renders are upright. Report the size in
                // that rotated orientation — for a 90/270 rotation the displayed
                // size is the transpose — otherwise Flutter's BoxFit.cover scales
                // a landscape box onto a portrait screen and the preview stretches.
                //
                // The transformation info can fire more than once per bind (and
                // again on every resume()). Dedupe identical sizes so a repeat
                // emission with the same orientation is a no-op, and never emit
                // a 0x0 — both would let a transient/stale event corrupt the
                // layout the Flutter side already computed.
                request.setTransformationInfoListener(
                    ContextCompat.getMainExecutor(context)
                ) { info ->
                    val swap = info.rotationDegrees % 180 != 0
                    val w = if (swap) res.height else res.width
                    val h = if (swap) res.width else res.height
                    if (w <= 0 || h <= 0) return@setTransformationInfoListener
                    if (w == lastEmittedPreviewW && h == lastEmittedPreviewH) {
                        return@setTransformationInfoListener
                    }
                    lastEmittedPreviewW = w
                    lastEmittedPreviewH = h
                    eventSink(mapOf(
                        "previewSize" to listOf(w.toDouble(), h.toDouble()),
                    ))
                }

                val surface = android.view.Surface(surfaceTexture)
                request.provideSurface(surface, ContextCompat.getMainExecutor(context)) {
                    surface.release()
                }
            }
        }

        analysis = ImageAnalysis.Builder()
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .setTargetAspectRatio(AspectRatio.RATIO_4_3)
            .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_YUV_420_888)
            .build()
            .also { a ->
                a.setAnalyzer(analysisExecutor) { proxy -> onFrame(proxy) }
            }

        val captureBuilder = ImageCapture.Builder()
            .setCaptureMode(ImageCapture.CAPTURE_MODE_MAXIMIZE_QUALITY)
            .setFlashMode(flashMode)
        val requestedSize = config.captureSize?.let { captureSize ->
            val parts = captureSize.split('x')
            val w = parts.getOrNull(0)?.toIntOrNull()
            val h = parts.getOrNull(1)?.toIntOrNull()
            if (parts.size == 2 && w != null && h != null &&
                w in 640..4300 && h in 480..4300 && w * h <= 13000000) {
                Size(w, h)
            } else null
        }
        if (requestedSize != null) {
            @Suppress("DEPRECATION")
            captureBuilder.setTargetResolution(requestedSize)
        } else {
            captureBuilder.setTargetAspectRatio(AspectRatio.RATIO_4_3)
        }
        imageCapture = captureBuilder.build()

        val owner = activity as? LifecycleOwner
            ?: throw ScannerException.InitFailed("Activity must be LifecycleOwner")
        camera = try {
            provider.bindToLifecycle(owner, selector, preview, analysis, imageCapture)
        } catch (error: IllegalArgumentException) {
            if (requestedSize == null) throw error
            // A JPEG size can be listed by Camera2 yet be incompatible with
            // concurrent Preview + Analysis on older hardware. Keep the live
            // scanner functional if CameraX rejects that combination.
            provider.unbindAll()
            imageCapture = ImageCapture.Builder()
                .setTargetAspectRatio(AspectRatio.RATIO_4_3)
                .setCaptureMode(ImageCapture.CAPTURE_MODE_MAXIMIZE_QUALITY)
                .setFlashMode(flashMode)
                .build()
            provider.bindToLifecycle(owner, selector, preview, analysis, imageCapture)
        }
        if (torch) camera?.cameraControl?.enableTorch(true)
    }

    @SuppressLint("UnsafeOptInUsageError")
    private fun onFrame(proxy: ImageProxy) {
        try {
            if (!config.enableLiveDetection) return
            val now = System.currentTimeMillis()
            val intervalMs = (1000.0 / config.detectionThrottleHz).toLong().coerceAtLeast(33L)
            if (now - lastDetectionMs < intervalMs) return
            lastDetectionMs = now

            val image = proxy.image ?: return
            val rotation = proxy.imageInfo.rotationDegrees
            // The reference detector needs enough pixels to resolve the page
            // outline, particularly for ID cards and textured backgrounds.
            val downscaleTo = 384
            val (luma, width, height) = YuvUtils.extractLuma(image, downscaleTo)
            lastFrameWidth = width
            lastFrameHeight = height
            val uprightFrameWidth = if (rotation % 180 == 0) width else height
            val uprightFrameHeight = if (rotation % 180 == 0) height else width
            latestFrameOrientation = FrameOrientation(
                uprightFrameWidth, uprightFrameHeight, rotation, now,
            )
            // Keep the chroma information: a similarly bright card and desk
            // can be separated by saturation edges that luma alone misses.
            // If a device supplies an invalid chroma plane, preserve the
            // existing grayscale and connected-component fallbacks.
            val rgba = YuvUtils.extractRgba(image, YuvUtils.Luma(luma, width, height), downscaleTo)
            val detected = (if (rgba != null) {
                openCvDetector.detectRgba(rgba, width, height,
                    config.preferIdCardBounds)
            } else {
                openCvDetector.detectLuma(luma, width, height,
                    config.preferIdCardBounds)
            })
                ?: (if (config.preferIdCardBounds) null else QuadDetector.detect(
                luma, width, height,
                config.detectionPolarity, config.detectionThresholdOffset,
            ))
            // The last-resort luma detector can also follow a sharp printed
            // line or a coloured half of a notebook. Validate its four outer
            // sides with the SAME safety gate as the OpenCV live detector.
            val quad = if (config.preferIdCardBounds) detected else
                LiveBoundarySelector.choose(detected, null, width, height)
            // Rotate quad coordinates into the displayed (rotated) coordinate
            // space so that normalized values match what users see.
            val rotated = quad?.let { rotateNormalizedQuad(it, rotation) }
            // This is the *same* detected outline emitted to Flutter for
            // the green overlay. Clear an obsolete outline when the detector
            // loses the page, so a shutter press never inherits a vanished box.
            val uprightW = if (rotation % 180 == 0) width else height
            val uprightH = if (rotation % 180 == 0) height else width
            latestPagePreviewHint = if (!config.preferIdCardBounds &&
                rotated != null &&
                StillCaptureCropSafety.isCrediblePage(rotated, uprightW, uprightH)) {
                PagePreviewHint(rotated, now, uprightW, uprightH)
            } else null

            val lowLight = config.enableLowLightDetection && LumaEstimator.isLowLight(luma)

            // Score sharpness over the detected quad's bbox. Use the
            // pre-rotation `quad` (same coordinate space as `luma`), not
            // `rotated` which is in displayed space.
            val sharpness = if (quad != null) {
                val xs = listOf(quad.topLeft.x, quad.topRight.x,
                                quad.bottomRight.x, quad.bottomLeft.x)
                val ys = listOf(quad.topLeft.y, quad.topRight.y,
                                quad.bottomRight.y, quad.bottomLeft.y)
                SharpnessEstimator.sharpness(
                    luma, width, height,
                    xs.min(), ys.min(), xs.max(), ys.max(),
                )
            } else {
                SharpnessEstimator.sharpness(luma, width, height)
            }

            eventSink(mapOf(
                "quad" to rotated?.toMap(),
                "lowLight" to lowLight,
                "sharpness" to sharpness,
            ))
        } finally {
            proxy.close()
        }
    }

    private fun rotateNormalizedQuad(q: Quad, deg: Int): Quad {
        fun r(p: PointF): PointF = when (((deg % 360) + 360) % 360) {
            0 -> p
            90 -> PointF(1f - p.y, p.x)
            180 -> PointF(1f - p.x, 1f - p.y)
            270 -> PointF(p.y, 1f - p.x)
            else -> p
        }
        // Re-order corners to maintain TL/TR/BR/BL after rotation.
        val rotated = listOf(r(q.topLeft), r(q.topRight), r(q.bottomRight), r(q.bottomLeft))
        return QuadOrdering.reorderClockwise(rotated)
    }

    @MainThread
    fun setFlashMode(mode: String) {
        flashMode = when (mode) {
            "off" -> { torch = false; ImageCapture.FLASH_MODE_OFF }
            "on" -> { torch = false; ImageCapture.FLASH_MODE_ON }
            "auto" -> { torch = false; ImageCapture.FLASH_MODE_AUTO }
            "torch" -> { torch = true; ImageCapture.FLASH_MODE_OFF }
            else -> ImageCapture.FLASH_MODE_AUTO
        }
        imageCapture?.flashMode = flashMode
        camera?.cameraControl?.enableTorch(torch)
    }

    @MainThread
    fun switchCamera() {
        latestPagePreviewHint = null
        lensFacing = if (lensFacing == CameraSelector.LENS_FACING_BACK)
            CameraSelector.LENS_FACING_FRONT else CameraSelector.LENS_FACING_BACK
        cameraProvider?.let { bindUseCases(it) }
    }

    @MainThread
    fun pause() {
        latestPagePreviewHint = null
        cameraProvider?.unbindAll()
    }

    @MainThread
    fun resume() {
        cameraProvider?.let { bindUseCases(it) }
    }

    /// Tap-to-focus. [normX], [normY] are in the Flutter widget's portrait
    /// [0, 1] space (origin top-left). We build a metering point on the
    /// preview Surface's native coordinate space using
    /// [SurfaceOrientedMeteringPointFactory], which is the correct factory
    /// for textures (see CameraX docs). Auto-cancel after 3 s drops back
    /// to continuous autofocus.
    @MainThread
    fun focus(normX: Float, normY: Float) {
        val camera = this.camera ?: return
        val w = previewSurfaceWidth
        val h = previewSurfaceHeight
        if (w <= 0 || h <= 0) return
        val factory = androidx.camera.core.SurfaceOrientedMeteringPointFactory(
            w.toFloat(), h.toFloat(),
        )
        val point = factory.createPoint(
            (normX.coerceIn(0f, 1f)) * w,
            (normY.coerceIn(0f, 1f)) * h,
        )
        val action = androidx.camera.core.FocusMeteringAction.Builder(
            point,
            androidx.camera.core.FocusMeteringAction.FLAG_AF or
                androidx.camera.core.FocusMeteringAction.FLAG_AE,
        ).setAutoCancelDuration(3, java.util.concurrent.TimeUnit.SECONDS)
         .build()
        if (camera.cameraInfo.isFocusMeteringSupported(action)) {
            try {
                camera.cameraControl.startFocusAndMetering(action)
            } catch (_: Exception) {
                // Best-effort.
            }
        }
    }

    @MainThread
    fun capture(result: MethodChannel.Result, displayedQuad: Quad? = null) {
        val capture = imageCapture
        if (capture == null) {
            result.error("init_failed", "ImageCapture not ready", null); return
        }
        val shutterTime = System.currentTimeMillis()
        val file = File(context.cacheDir, "fnds_raw_${shutterTime}.jpg")
        val rawNativeHint = latestPagePreviewHint?.takeIf {
            shutterTime - it.timestampMs in 0L..900L
        }
        val frameOrientationAtShutter = latestFrameOrientation?.takeIf {
            shutterTime - it.timestampMs in 0L..1200L
        }
        // The four-corner Flutter overlay may be smoothed/hysteresis-filtered
        // and differ from this frame's raw OpenCV proposal. Use exactly the
        // visible quad when it is plausible in the upright analysis space.
        // Its *actual still-image pixels* must separately corroborate that
        // shape before any automatic perspective warp is allowed.
        val displayedHint = displayedQuad?.let { visible ->
            frameOrientationAtShutter?.takeIf {
                StillCaptureCropSafety.isSafeDisplayedGreenForReview(
                    visible, it.width, it.height)
            }?.let { frame ->
                PagePreviewHint(visible, shutterTime, frame.width, frame.height)
            }
        }
        val previewHintAtShutter = displayedHint ?: rawNativeHint
        // Keep the JPEG's camera target orientation synchronized with what
        // Android is displaying at the shutter. CameraX writes the required
        // rotation into EXIF. Never infer an extra quarter-turn simply from
        // portrait-vs-landscape pixel dimensions: a notebook can legitimately
        // be sideways, and that heuristic rotated pages after capture.
        capture.targetRotation = activity.windowManager.defaultDisplay.rotation
        val options = ImageCapture.OutputFileOptions.Builder(file).build()
        capture.takePicture(options, captureExecutor, object : ImageCapture.OnImageSavedCallback {
            override fun onError(exception: ImageCaptureException) {
                activity.runOnUiThread {
                    result.error("capture_failed", exception.message, null)
                }
            }
            override fun onImageSaved(output: ImageCapture.OutputFileResults) {
                var raw: Bitmap? = null
                var rotated: Bitmap? = null
                try {
                    // Keep the selected 12MP/8MP HD still instead of silently
                    // subsampling it to 3MP before applying the perspective warp.
                    raw = decodeDownscaled(file.absolutePath, maxDimension = 4096)
                        ?: throw ScannerException.CaptureFailed("Decode failed")
                    // EXIF is authoritative when present. HONOR CameraX
                    // can nevertheless save LANDSCAPE pixel data without
                    // its expected 90/270 EXIF while the analysis preview is
                    // portrait (the user's scan then appeared rotated in
                    // Adjust Corners). Recover a missing EXIF quarter-turn
                    // ONLY on an exact transposed 4:3 aspect match AND a
                    // known 90/270 frame rotation. Never guess based merely
                    // on document text direction or a square subject.
                    val exifUpright = ExifRotator.rotated(raw, file.absolutePath)
                    val missingTurns = frameOrientationAtShutter?.let { frame ->
                        StillCaptureCropSafety.missingExifQuarterTurns(
                            frame.width, frame.height,
                            exifUpright.width, exifUpright.height,
                            frame.rotationDegrees,
                        )
                    } ?: 0
                    rotated = if (missingTurns == 0) exifUpright else
                        ImageWarper.rotateBitmap(exifUpright, missingTurns)
                    if (rotated !== exifUpright && exifUpright !== raw) {
                        exifUpright.recycle()
                    }
                    val rawSize = Size(rotated.width, rotated.height)
                    // The preview quad is measured on a low-resolution YUV
                    // stream and can drift if a phone uses a different sensor
                    // crop for still capture. Re-detect against the actual
                    // upright captured pixels before the irreversible warp.
                    // Do NOT apply a stale preview quad if still detection
                    // fails. CameraX stills can have a different crop/zoom;
                    // preserving the whole original lets the user adjust
                    // all four corners without irreversible mis-cropping.
                    val ordinaryStillQuad = QuadDetector.detectInBitmap(
                        rotated,
                        config.detectionPolarity,
                        config.detectionThresholdOffset,
                        config.preferIdCardBounds,
                    )
                    // A coloured card on ruled paper can appear as a small
                    // object *inside* the large notebook quad detected by
                    // ordinary page edges. Verify its physical outer border
                    // independently before warping any captured pixels.
                    // This stays entirely offline and never synthesizes or
                    // rewrites the person's portrait or card text.
                    val colourCard = if (config.preferIdCardBounds) null else
                        QuadDetector.detectColoredCardInBitmap(rotated)
                    val verifiedColourCard = !config.preferIdCardBounds &&
                        StillCaptureCropSafety.verifiedColorCardOverBackground(
                            ordinaryStillQuad, colourCard,
                            rawSize.width, rawSize.height)
                    val stillQuad = if (verifiedColourCard) colourCard
                        else ordinaryStillQuad
                    // CameraX can have a different sensor crop or EXIF rotation
                    // from the low-resolution preview. Lock the *actual green*
                    // four-corner quad from the shutter frame only when still
                    // detection independently corroborates the very same page.
                    // Do not silently replace it with a different inner table.
                    val liveHint = previewHintAtShutter?.takeIf {
                        !config.preferIdCardBounds
                    }
                    // Capture a separate REVIEW quad even when the STILL
                    // detector cannot independently verify the paper.
                    // The old sentinel full-frame quad discarded the green
                    // coordinates and made the editor select patterned cloth.
                    // Review metadata never authorizes an automatic warp.
                    val reviewGreen = liveHint?.let { hint ->
                        StillCaptureCropSafety.projectGreenToCapturedStill(
                            hint.quad, hint.width, hint.height,
                            rawSize.width, rawSize.height,
                            frameOrientationAtShutter?.rotationDegrees ?: 0,
                        )
                    }
                    // Exact GREEN corners are the crop target when the
                    // captured still independently confirms those edges,
                    // including after a 90/270-degree sensor transformation.
                    val matchedPageOutline = reviewGreen != null && liveHint != null &&
                        StillCaptureCropSafety.sameDocumentAsLivePreview(
                            reviewGreen, stillQuad,
                            rawSize.width, rawSize.height,
                            rawSize.width, rawSize.height)
                    // A *small* paper card may cover only ~10% of the live
                    // view (video 382753.mp4). A4-only gates discard its
                    // otherwise correct green box and the still detector
                    // may prefer the patterned cloth. Segment the actual
                    // neutral WHITE card on the shutter bitmap instead.
                    // It must pass independent outside-edge contrast and
                    // live-document aspect/position checks. This is NOT the
                    // gallery/import detector and never changes that flow.
                    //
                    // A CameraX/EXIF 90-degree content rotation may change
                    // normalized coordinates: use verified STILL corners
                    // rather than blindly scaling the green coordinates in
                    // that case. They represent the same physical 4 edges.
                    val recoveredSmallCard = if (!config.preferIdCardBounds &&
                        liveHint != null &&
                        StillCaptureCropSafety.isCredibleSmallDisplayedCard(
                            liveHint.quad, liveHint.width, liveHint.height)) {
                        QuadDetector.detectSmallNeutralCardInBitmap(
                            rotated, liveHint.quad,
                            liveHint.width, liveHint.height)
                    } else null
                    // On small cards the old A4-only comparator always
                    // failed, then selected the white-card segmentation quad
                    // instead of the *visible* green corners. That can leave
                    // strips of fabric around an otherwise correct scan.
                    // Use the independent white-card boundary as verification
                    // evidence; warp using GREEN coordinates in still space.
                    val verifiedSmallGreen = liveHint?.let { hint ->
                        recoveredSmallCard?.let { paper ->
                            StillCaptureCropSafety.verifiedSmallGreenOnStill(
                                hint.quad, paper, hint.width, hint.height,
                                rawSize.width, rawSize.height)
                        }
                    }
                    // The full-resolution JPEG can use a different view
                    // orientation AND camera crop than the analysis stream.
                    // If mapping the exact green quad fails, a white-paper
                    // component that independently matches the visible small
                    // card is a safe still-space boundary. Crucially, NEVER
                    // fall back to the unrotated portrait green rectangle on
                    // a landscape card photo: that was the user's narrow
                    // 4-handle crop in the 15 Nov 2026 screenshots.
                    val matchedLiveOutline =
                        matchedPageOutline || verifiedSmallGreen != null
                    val verifiedSmallCardBoundary = recoveredSmallCard != null
                    val uncertainStill = when {
                        matchedLiveOutline || verifiedSmallCardBoundary -> false
                        liveHint != null -> true
                        else -> !config.preferIdCardBounds && !verifiedColourCard &&
                            StillCaptureCropSafety.requiresManualReview(
                                stillQuad, rawSize.width, rawSize.height, null)
                    }
                    val q = StillCaptureCropSafety.selectCameraStillBoundary(
                        mappedGreen = verifiedSmallGreen ?:
                            if (matchedPageOutline) reviewGreen else null,
                        independentlyVerifiedCard = recoveredSmallCard,
                        liveGreenSeen = liveHint != null,
                        ordinaryStill = if (uncertainStill) null else stillQuad,
                    )
                    val pixelQuad = q?.let {
                        Quad(
                            PointF(it.topLeft.x * rawSize.width, it.topLeft.y * rawSize.height),
                            PointF(it.topRight.x * rawSize.width, it.topRight.y * rawSize.height),
                            PointF(it.bottomRight.x * rawSize.width, it.bottomRight.y * rawSize.height),
                            PointF(it.bottomLeft.x * rawSize.width, it.bottomLeft.y * rawSize.height),
                        )
                    }
                    var croppedPath: String? = null
                    var warpError: String? = null
                    if (config.enablePerspectiveWarp && pixelQuad != null &&
                        !uncertainStill) {
                        try {
                            croppedPath = ImageWarper.warp(rotated, pixelQuad,
                                config.jpegQuality, config.imageEnhancement, config.autoOrientation)
                        } catch (e: Exception) {
                            // The raw capture remains usable for manual crop.
                            warpError = e.message ?: "Perspective crop failed"
                        }
                    }
                    // Always persist the upright bitmap we actually measured
                    // (`rotated`) so the returned rawImagePath's pixel
                    // dimensions exactly match `rawImageSize` — and therefore
                    // the reported quad. We can't return the original on-disk
                    // file here: `decodeDownscaled` may have shrunk large
                    // captures (e.g. 4000x3000 -> 2000x1500), so the original
                    // file would be full-resolution while rawImageSize/quad
                    // describe the downscaled space. A later re-warp via
                    // EditCorners decodes that file at full resolution and
                    // applies the half-scale quad, cropping the wrong region.
                    val rawPathToReturn = run {
                        val out = File(context.cacheDir, "fnds_raw_upright_${System.currentTimeMillis()}.jpg")
                        out.outputStream().use { rotated.compress(Bitmap.CompressFormat.JPEG, config.jpegQuality, it) }
                        // Original on-disk file is now stale (rotated and/or
                        // downscaled relative to what we return).
                        file.delete()
                        out.absolutePath
                    }

                    val payload = mapOf(
                        "croppedImagePath" to croppedPath,
                        "rawImagePath" to rawPathToReturn,
                        "warpError" to warpError,
                        // Camera-only metadata: gallery/import does not
                        // receive or depend on either of these fields.
                        "liveOutlineAtShutter" to (liveHint != null),
                        // Image-space green outline for explicit manual
                        // acceptance when still evidence is inconclusive.
                        // Deliberately separate from the warp-only "quad".
                        "reviewQuad" to reviewGreen?.let { g ->
                            Quad(
                                PointF(g.topLeft.x * rawSize.width,
                                    g.topLeft.y * rawSize.height),
                                PointF(g.topRight.x * rawSize.width,
                                    g.topRight.y * rawSize.height),
                                PointF(g.bottomRight.x * rawSize.width,
                                    g.bottomRight.y * rawSize.height),
                                PointF(g.bottomLeft.x * rawSize.width,
                                    g.bottomLeft.y * rawSize.height),
                            ).toMap()
                        },
                        // True only if a perspective crop was actually
                        // generated from a verified SAME document boundary.
                        // Previously a tentative recovered card flagged this
                        // true even when no native crop was returned.
                        "liveOutlineMatched" to
                            (croppedPath != null &&
                                (matchedLiveOutline || verifiedSmallCardBoundary)),
                        "quad" to (pixelQuad ?: Quad(
                            PointF(0f, 0f),
                            PointF(rawSize.width.toFloat(), 0f),
                            PointF(rawSize.width.toFloat(), rawSize.height.toFloat()),
                            PointF(0f, rawSize.height.toFloat()),
                        )).toMap(),
                        "rawImageSize" to listOf(rawSize.width.toDouble(), rawSize.height.toDouble()),
                    )
                    activity.runOnUiThread { result.success(payload) }
                } catch (e: Exception) {
                    activity.runOnUiThread {
                        result.error("capture_failed", e.message, null)
                    }
                } finally {
                    if (rotated != null && rotated !== raw) rotated.recycle()
                    raw?.recycle()
                }
            }
        })
    }

    private fun decodeDownscaled(path: String, maxDimension: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (bounds.outWidth / sample > maxDimension ||
               bounds.outHeight / sample > maxDimension) {
            sample *= 2
        }
        val opts = BitmapFactory.Options().apply { inSampleSize = sample }
        return BitmapFactory.decodeFile(path, opts)
    }

    @MainThread
    fun dispose() {
        cameraProvider?.unbindAll()
        cameraProvider = null
        // Analyzer and native mats must not be released while a frame runs.
        analysisExecutor.execute { openCvDetector.release() }
        analysisExecutor.shutdown()
        captureExecutor.shutdown()
        textureEntry.release()
    }
}
