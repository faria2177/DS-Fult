package dev.doclens.doclens

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.view.Surface
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.os.Build
import android.util.Size
import android.util.Rational
import androidx.annotation.MainThread
import androidx.camera.core.CameraSelector
import androidx.camera.core.AspectRatio
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.core.SurfaceRequest
import androidx.camera.core.UseCaseGroup
import androidx.camera.core.ViewPort
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
    @Volatile private var sharedViewPortActive: Boolean = false
    @Volatile private var boundTargetRotation: Int = Surface.ROTATION_0

    private var lensFacing: Int = CameraSelector.LENS_FACING_BACK
    private var flashMode: Int = ImageCapture.FLASH_MODE_AUTO
    private var torch: Boolean = false

    @Volatile private var lastFrameWidth: Int = 0
    @Volatile private var lastFrameHeight: Int = 0
    @Volatile private var lastDetectionMs: Long = 0L
    private var lastClosePageRetryMs: Long = 0L
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
        sharedViewPortActive = false
        // A new binding invalidates the dimensions of all earlier frames.
        // Never map a green quad using orientation from a previous camera.
        latestFrameOrientation = null
        latestPagePreviewHint = null
        lastEmittedPreviewW = 0
        lastEmittedPreviewH = 0
        val targetRotation = activity.windowManager.defaultDisplay.rotation
        boundTargetRotation = targetRotation
        val selector = CameraSelector.Builder().requireLensFacing(lensFacing).build()
        val surfaceTexture = textureEntry.surfaceTexture()

        // Without a shared aspect ratio CameraX may pick a 16:9 preview and
        // a 4:3 analysis buffer. Normalized analysis corners then stretch
        // vertically on the preview (~33% error), even with a perfect quad.
        // Match preview, analysis and still-capture field of view on every
        // device. Flutter scales preview + overlay together using BoxFit.cover.
        preview = Preview.Builder()
            .setTargetRotation(targetRotation)
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
            .setTargetRotation(targetRotation)
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .setTargetAspectRatio(AspectRatio.RATIO_4_3)
            .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_YUV_420_888)
            .build()
            .also { a ->
                a.setAnalyzer(analysisExecutor) { proxy -> onFrame(proxy) }
            }

        val captureBuilder = ImageCapture.Builder()
            .setTargetRotation(targetRotation)
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
        // CameraX's same aspect-ratio settings do NOT guarantee the same
        // sensor field of view at different resolutions. A common ViewPort
        // guarantees matching Preview / Analysis / on-disk JPEG crop regions.
        // Use the portrait 3:4 (or landscape 4:3) visual camera field, not
        // the tall Flutter viewfinder which uses BoxFit.cover.
        fun bindMatchedViewPort(): androidx.camera.core.Camera {
            val portrait = targetRotation == Surface.ROTATION_0 ||
                targetRotation == Surface.ROTATION_180
            val ratio = if (portrait) Rational(3, 4) else Rational(4, 3)
            val viewPort = ViewPort.Builder(ratio, targetRotation).setScaleType(ViewPort.FILL_CENTER).build()
            return provider.bindToLifecycle(owner, selector,
                UseCaseGroup.Builder()
                    .addUseCase(checkNotNull(preview))
                    .addUseCase(checkNotNull(analysis))
                    .addUseCase(checkNotNull(imageCapture))
                    .setViewPort(viewPort)
                    .build()
            )
        }
        camera = try {
            bindMatchedViewPort()
        } catch (error: IllegalArgumentException) {
            if (requestedSize == null) throw error
            // Some cameras cannot stream their requested HD size with two
            // other use cases. Retry 4:3 Capture without losing the shared
            // sensor ViewPort. Falling back to an ungrouped bind would cause
            // the exact green-corner offset reported by users.
            provider.unbindAll()
            imageCapture = ImageCapture.Builder()
                .setTargetRotation(targetRotation)
                .setTargetAspectRatio(AspectRatio.RATIO_4_3)
                .setCaptureMode(ImageCapture.CAPTURE_MODE_MAXIMIZE_QUALITY)
                .setFlashMode(flashMode)
                .build()
            bindMatchedViewPort()
        }
        sharedViewPortActive = true
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
            // CameraX UseCaseGroup supplies a cropRect per stream. The full
            // YUV buffer can contain pixels not visible in the JPEG or Preview.
            // Detect ONLY the common ViewPort; normalized quad coordinates
            // then refer to that exact field without a second offset guess.
            val crop = YuvUtils.checkedCrop(
                image.width, image.height, proxy.cropRect)
            val downscaleTo = 384
            val (luma, width, height) =
                YuvUtils.extractLuma(image, downscaleTo, crop)
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
            val rgba = YuvUtils.extractRgba(
                image, YuvUtils.Luma(luma, width, height),
                downscaleTo, crop)
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
            val selected = if (config.preferIdCardBounds) detected else
                LiveBoundarySelector.choose(detected, null, width, height)
            // At close range the 384px analysis image can resolve sharply
            // printed letters but lose a faint outside A4 sheet boundary.
            // If a candidate has bright PAPER on at least three sides,
            // do one higher-resolution retry at most twice per second. This
            // only accepts another real four-corner candidate enclosing the
            // text block; it NEVER extrapolates/expands guessed corners.
            val printedInterior = !config.preferIdCardBounds &&
                rgba != null && selected != null &&
                LivePaperInteriorGuard.isPrintedInterior(
                    selected, rgba, width, height)
            val quad = if (printedInterior && selected != null) {
                var recovered: Quad? = null
                if (now - lastClosePageRetryMs >= 550L) {
                    lastClosePageRetryMs = now
                    val high = YuvUtils.extractLuma(image, 576, crop)
                    val highRgba = YuvUtils.extractRgba(
                        image, high, 576, crop)
                    if (highRgba != null) {
                        val suggested = openCvDetector.detectRgba(
                            highRgba, high.width, high.height, false)
                        val candidate = LivePaperInteriorGuard.recoveredOuterPage(
                            selected, suggested, high.width, high.height)
                        recovered = candidate?.takeUnless {
                            LivePaperInteriorGuard.isPrintedInterior(
                                it, highRgba, high.width, high.height)
                        }
                    }
                }
                // Better to show no green than to permanently crop only
                // the inside text rectangle. The raw capture stays editable.
                recovered
            } else selected
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
        sharedViewPortActive = false
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
        // A changed device rotation requires a new shared CameraX ViewPort.
        // Cropping with the earlier preview geometry would be destructive.
        if (activity.windowManager.defaultDisplay.rotation != boundTargetRotation) {
            cameraProvider?.let { bindUseCases(it) }
            result.error("camera_orientation_changed",
                "Camera orientation changed; please capture again", null)
            return
        }
        val shutterTime = System.currentTimeMillis()
        // Freeze binding geometry together with the green overlay at the
        // *tap*. Never infer it later from updated CameraX preview frames.
        val matchedViewPortAtShutter = sharedViewPortActive
        val file = File(context.cacheDir, "fnds_raw_${shutterTime}.jpg")
        // Record that Flutter was visibly showing a green quad even when
        // CameraX has temporarily stopped publishing orientation frames.
        // Never replace that on-screen selection with a different still
        // detector's contour merely because its mapping is unavailable.
        val visibleGreenAtShutter = !config.preferIdCardBounds &&
            displayedQuad != null
        // Orientation is binding metadata rather than a 1200ms detection
        // confidence signal. The detector may briefly stall while the green
        // box remains visible; keep its last known geometry until rebind.
        val frameOrientationAtShutter = latestFrameOrientation
        // The four-corner Flutter overlay may be smoothed/hysteresis-filtered
        // and differ from this frame's raw OpenCV proposal. Use exactly the
        // visible quad when it is plausible in the upright analysis space.
        // A shared CameraX ViewPort gives the preview and on-disk JPEG the
        // same sensor crop. Independently detected still boundaries are used
        // only when CameraX cannot establish this coordinate relationship.
        val displayedHint = displayedQuad?.let { visible ->
            frameOrientationAtShutter?.takeIf {
                StillCaptureCropSafety.isSafeDisplayedGreenForReview(
                    visible, it.width, it.height)
            }?.let { frame ->
                PagePreviewHint(visible, shutterTime, frame.width, frame.height)
            }
        }
        // Never replace the Flutter-painted quad with a raw detector hint
        // that the user did not actually see at the shutter.
        val previewHintAtShutter = displayedHint
        // Keep the JPEG's camera target orientation synchronized with what
        // Android is displaying at the shutter. CameraX writes the required
        // rotation into EXIF. Never infer an extra quarter-turn simply from
        // portrait-vs-landscape pixel dimensions: a notebook can legitimately
        // be sideways, and that heuristic rotated pages after capture.
        capture.targetRotation = boundTargetRotation
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
                    // The Flutter-painted green quad is frozen at shutter.
                    // CameraX's shared ViewPort makes that selection a
                    // geometric crop in the EXIF-upright JPEG space.
                    val liveHint = previewHintAtShutter?.takeIf {
                        !config.preferIdCardBounds
                    }
                    val liveGreenSeen = visibleGreenAtShutter
                    val mappedGreen = if (liveGreenSeen && matchedViewPortAtShutter &&
                        lensFacing == CameraSelector.LENS_FACING_BACK) {
                        liveHint?.let { hint ->
                            StillCaptureCropSafety.mapGreenToStill(
                                hint.quad, hint.width, hint.height,
                                rawSize.width, rawSize.height,
                            )
                        }
                    } else null

                    // The still-image detector is not allowed to overrule
                    // a screen-visible green outline. Only captures without
                    // an outline (or dedicated ID-card mode) detect again.
                    val ordinaryStillQuad = if (!liveGreenSeen ||
                        config.preferIdCardBounds) QuadDetector.detectInBitmap(
                            rotated, config.detectionPolarity,
                            config.detectionThresholdOffset,
                            config.preferIdCardBounds,
                        ) else null
                    val colourCard = if (!liveGreenSeen &&
                        !config.preferIdCardBounds)
                        QuadDetector.detectColoredCardInBitmap(rotated)
                        else null
                    val verifiedColourCard = !liveGreenSeen &&
                        !config.preferIdCardBounds &&
                        StillCaptureCropSafety.verifiedColorCardOverBackground(
                            ordinaryStillQuad, colourCard,
                            rawSize.width, rawSize.height)
                    val stillQuad = if (verifiedColourCard) colourCard
                        else ordinaryStillQuad

                    val matchedLiveOutline = liveGreenSeen && mappedGreen != null
                    val uncertainStill = if (liveGreenSeen) {
                        mappedGreen == null
                    } else {
                        !config.preferIdCardBounds && !verifiedColourCard &&
                            StillCaptureCropSafety.requiresManualReview(
                                stillQuad, rawSize.width, rawSize.height, null)
                    }
                    val q = StillCaptureCropSafety.cameraCaptureSelection(
                        liveGreenSeen = liveGreenSeen,
                        mappedGreen = mappedGreen,
                        ordinaryStill = if (uncertainStill) null else stillQuad,
                        independentlyVerifiedCard =
                            if (verifiedColourCard) colourCard else null,
                    )

                    // Pixel evidence is diagnostic confidence only. Neutral
                    // paper, dense writing and slightly inset outlines must
                    // NOT block the exact visible quad.
                    val photo = checkNotNull(rotated)
                    val borderConfidence = mappedGreen != null &&
                        StillCaptureCropSafety.hasCapturedGreenBorderEvidence(
                            mappedGreen, rawSize.width, rawSize.height,
                        ) { x, y -> photo.getPixel(x, y) }
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
                        "liveOutlineAtShutter" to liveGreenSeen,
                        // Informative only: never a crop authorization gate.
                        "borderConfidence" to borderConfidence,
                        // Image-space green outline for explicit manual
                        // acceptance when still evidence is inconclusive.
                        // Deliberately separate from the warp-only "quad".
                        "reviewQuad" to mappedGreen?.let { g ->
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
                        // True when the frozen green corners were mapped
                        // geometrically and successfully perspective-warped.
                        "liveOutlineMatched" to
                            (croppedPath != null && matchedLiveOutline),
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
