package dev.doclens.doclens

import android.Manifest
import android.content.ContentValues
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.graphics.ImageFormat
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import io.flutter.view.TextureRegistry
import java.io.File
import java.util.concurrent.Executors

private const val CAMERA_PERMISSION_REQUEST = 0x4F4E

class DoclensPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    PluginRegistry.RequestPermissionsResultListener,
    PluginRegistry.NewIntentListener {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var levelChannel: EventChannel
    private lateinit var textureRegistry: TextureRegistry
    private lateinit var context: Context

    private val eventStream = QuadEventStream()
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val backgroundExecutor = Executors.newSingleThreadExecutor()

    private var session: ScannerSession? = null
    private var pendingPermissionInit: (() -> Unit)? = null
    private var nativeUIScanner: NativeUIScanner? = null
    private var levelStream: DeviceLevelStream? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        textureRegistry = binding.textureRegistry
        methodChannel = MethodChannel(binding.binaryMessenger, "doclens/methods")
        methodChannel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, "doclens/events")
        eventChannel.setStreamHandler(eventStream)
        levelStream = DeviceLevelStream(context)
        levelChannel = EventChannel(binding.binaryMessenger, "doclens/level")
        levelChannel.setStreamHandler(levelStream)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        levelChannel.setStreamHandler(null)
        levelStream?.dispose()
        levelStream = null
        session?.dispose()
        session = null
        backgroundExecutor.shutdown()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
        binding.addOnNewIntentListener(this)
        val ui = NativeUIScanner(context).also { nativeUIScanner = it }
        binding.addActivityResultListener(ui)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding?.removeOnNewIntentListener(this)
        nativeUIScanner?.let { activityBinding?.removeActivityResultListener(it) }
        nativeUIScanner = null
        activity = null
        activityBinding = null
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> initialize(call, result)
            "dispose" -> { session?.dispose(); session = null; result.success(null) }
            "capture" -> {
                val s = session
                if (s == null) { result.error("init_failed", "Not initialized", null); return }
                s.capture(result)
            }
            "warpImage" -> handleWarp(call, result)
            "rotateImage" -> handleRotate(call, result)
            "recognizeText" -> handleRecognizeText(call, result)
            "setFlashMode" -> { session?.setFlashMode(call.argument<String>("mode") ?: "auto"); result.success(null) }
            "switchCamera" -> { session?.switchCamera(); result.success(null) }
            "pause" -> { session?.pause(); result.success(null) }
            "resume" -> { session?.resume(); result.success(null) }
            "focusAt" -> {
                val x = (call.argument<Number>("x") ?: 0.5).toFloat()
                val y = (call.argument<Number>("y") ?: 0.5).toFloat()
                session?.focus(x, y)
                result.success(null)
            }
            "getCaptureResolutions" -> {
                try {
                    val manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
                    val cameraId = manager.cameraIdList.firstOrNull { id ->
                        manager.getCameraCharacteristics(id).get(CameraCharacteristics.LENS_FACING) ==
                            CameraCharacteristics.LENS_FACING_BACK
                    }
                    val sizes = if (cameraId == null) emptyList() else {
                        val map = manager.getCameraCharacteristics(cameraId)
                            .get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
                        map?.getOutputSizes(ImageFormat.JPEG)?.toList() ?: emptyList()
                    }
                    // The scanner retains JPEG pixels up to 4096 px on the long
                    // side. Do not offer high-megapixel modes we would downscale.
                    val supported = sizes.filter { size ->
                        size.width >= 1600 && size.height >= 1000 &&
                            size.width <= 4096 && size.height <= 4096 &&
                            size.width.toLong() * size.height <= 13000000
                    }.distinctBy { size -> size.width to size.height }
                        .sortedByDescending { size -> size.width.toLong() * size.height }
                        .map { size -> listOf(size.width, size.height) }
                    result.success(supported)
                } catch (_: Exception) {
                    result.success(emptyList<List<Int>>())
                }
            }
            "saveImageToGallery" -> {
                val imagePath = call.argument<String>("imagePath")
                if (imagePath == null) {
                    result.error("invalid_image", "Missing image path", null)
                } else {
                    backgroundExecutor.execute {
                        val saved = saveImageToGallery(imagePath)
                        mainHandler.post { result.success(saved) }
                    }
                }
            }
            "pinDocumentShortcut" -> {
                val id = call.argument<String>("documentId")
                val title = call.argument<String>("title")
                if (id.isNullOrBlank() || title.isNullOrBlank()) {
                    result.error("invalid_document", "Missing document shortcut data", null)
                } else {
                    result.success(pinDocumentShortcut(id, title))
                }
            }
            "consumeLaunchDocumentShortcut" -> {
                val intent = activity?.intent
                val id = intent?.getStringExtra("docscanner_document_id")
                intent?.removeExtra("docscanner_document_id")
                result.success(id)
            }
            "scanWithNativeUI" -> handleNativeUIScan(call, result)
            "detectInImage" -> handleDetectInImage(call, result)
            else -> result.notImplemented()
        }
    }

    override fun onNewIntent(intent: Intent): Boolean {
        val documentId = intent.getStringExtra("docscanner_document_id") ?: return false
        activity?.intent = intent
        intent.removeExtra("docscanner_document_id")
        methodChannel.invokeMethod("openPinnedDocument", documentId)
        return true
    }

    private fun pinDocumentShortcut(documentId: String, title: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val shortcuts = context.getSystemService(ShortcutManager::class.java)
            ?: return false
        if (!shortcuts.isRequestPinShortcutSupported) return false
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: return false
        launch.action = "dev.doclens.docscanner.OPEN_DOCUMENT"
        launch.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or
            Intent.FLAG_ACTIVITY_SINGLE_TOP
        launch.putExtra("docscanner_document_id", documentId)
        val shortcut = ShortcutInfo.Builder(context, "docscanner_$documentId")
            .setShortLabel(title.take(30))
            .setLongLabel(title.take(90))
            .setIcon(Icon.createWithResource(context, android.R.drawable.ic_menu_gallery))
            .setIntent(launch)
            .build()
        return shortcuts.requestPinShortcut(shortcut, null)
    }

    private fun handleNativeUIScan(call: MethodCall, result: MethodChannel.Result) {
        val activity = this.activity
        val ui = nativeUIScanner
        if (activity == null || ui == null) {
            result.error("init_failed", "No activity attached", null); return
        }
        ui.launch(
            activity = activity,
            pageLimit = (call.argument<Int>("pageLimit") ?: 100),
            allowGalleryImport = call.argument<Boolean>("allowGalleryImport") ?: false,
            jpegQuality = call.argument<Int>("jpegQuality") ?: 100,
            result = result,
        )
    }

    private fun saveImageToGallery(path: String): Boolean {
        // Scoped-storage insertion avoids requesting broad media permissions.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        val source = File(path)
        if (!source.isFile) return false
        val extension = when (source.extension.lowercase()) {
            "png" -> "png"
            "webp" -> "webp"
            else -> "jpg"
        }
        val mimeType = when (extension) {
            "png" -> "image/png"
            "webp" -> "image/webp"
            else -> "image/jpeg"
        }
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME,
                "DocScanner_${System.currentTimeMillis()}_${source.nameWithoutExtension}.$extension")
            put(MediaStore.Images.Media.MIME_TYPE, mimeType)
            put(MediaStore.Images.Media.RELATIVE_PATH,
                Environment.DIRECTORY_PICTURES + "/DocScanner")
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            ?: return false
        return try {
            resolver.openOutputStream(uri)?.use { stream ->
                source.inputStream().use { input -> input.copyTo(stream) }
            } ?: throw IllegalStateException("Cannot open gallery output")
            values.clear()
            values.put(MediaStore.Images.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            true
        } catch (_: Exception) {
            resolver.delete(uri, null, null)
            false
        }
    }

    private fun handleWarp(call: MethodCall, result: MethodChannel.Result) {
        val rawPath = call.argument<String>("rawImagePath")
        val quadMap = call.argument<Map<String, Any?>>("quad")
        val quality = call.argument<Int>("jpegQuality") ?: 100
        val enhancement = call.argument<String>("enhancement") ?: "none"
        val autoOrientation = call.argument<String>("autoOrientation") ?: "none"
        if (rawPath == null || quadMap == null) {
            result.error("capture_failed", "Invalid warp args", null); return
        }
        backgroundExecutor.execute {
            try {
                val q = Quad.fromMap(quadMap)
                val out = ImageWarper.warpFile(rawPath, q, quality, enhancement, autoOrientation)
                mainHandler.post { result.success(out) }
            } catch (e: Exception) {
                mainHandler.post { result.error("capture_failed", e.message, null) }
            }
        }
    }

    private fun handleDetectInImage(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("imagePath")
        if (path == null) {
            result.error("capture_failed", "Invalid detectInImage args", null); return
        }
        // Detection polarity travels with the call rather than the session:
        // `detectInImage` is a pure file operation and works with no camera
        // session bound. Absent args fall back to the paper-bright default.
        val polarity = DetectionPolarity.from(call.argument<String>("detectionPolarity"))
        val thresholdOffset = call.argument<Int>("detectionThresholdOffset")
            ?: QuadDetector.DEFAULT_THRESHOLD_OFFSET
        backgroundExecutor.execute {
            try {
                val out = QuadDetector.detectInFile(path, polarity, thresholdOffset)
                mainHandler.post { result.success(out) }
            } catch (e: Exception) {
                mainHandler.post { result.error("capture_failed", e.message, null) }
            }
        }
    }

    private fun handleRecognizeText(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("imagePath")
        if (path == null) {
            result.error("capture_failed", "Invalid recognizeText args", null); return
        }
        backgroundExecutor.execute {
            try {
                val out = TextRecognizer.recognize(path)
                mainHandler.post { result.success(out) }
            } catch (e: Exception) {
                mainHandler.post { result.error("capture_failed", e.message, null) }
            }
        }
    }

    private fun handleRotate(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("imagePath")
        val quarterTurns = call.argument<Int>("quarterTurns") ?: 0
        val quality = call.argument<Int>("jpegQuality") ?: 100
        if (path == null) {
            result.error("capture_failed", "Invalid rotate args", null); return
        }
        backgroundExecutor.execute {
            try {
                val out = ImageWarper.rotateFile(path, quarterTurns, quality)
                mainHandler.post { result.success(out) }
            } catch (e: Exception) {
                mainHandler.post { result.error("capture_failed", e.message, null) }
            }
        }
    }

    private fun initialize(call: MethodCall, result: MethodChannel.Result) {
        val activity = this.activity
        if (activity == null) {
            result.error("init_failed", "No activity attached", null); return
        }
        // Tear down any previous session — never leak a running camera.
        session?.dispose()
        session = null

        val granted = ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED
        if (!granted) {
            pendingPermissionInit = { doInitialize(call, result) }
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(Manifest.permission.CAMERA),
                CAMERA_PERMISSION_REQUEST,
            )
            return
        }
        doInitialize(call, result)
    }

    @Suppress("UNCHECKED_CAST")
    private fun doInitialize(call: MethodCall, result: MethodChannel.Result) {
        val activity = this.activity ?: run {
            result.error("init_failed", "No activity attached", null); return
        }
        val cfg = ScannerConfig.fromMap(call.arguments as? Map<String, Any?> ?: emptyMap())
        val entry = textureRegistry.createSurfaceTexture()
        val s = ScannerSession(
            activity = activity,
            context = context,
            config = cfg,
            textureEntry = entry,
            eventSink = { eventStream.send(it) },
        )
        session = s
        s.start { startResult ->
            startResult.fold(
                onSuccess = { result.success(it) },
                onFailure = { err ->
                    val code = when (err) {
                        is ScannerException.PermissionDenied -> "permission_denied"
                        is ScannerException.Unavailable -> "unavailable"
                        else -> "init_failed"
                    }
                    entry.release()
                    session = null
                    result.error(code, err.message, null)
                },
            )
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != CAMERA_PERMISSION_REQUEST) return false
        val pending = pendingPermissionInit ?: return true
        pendingPermissionInit = null
        // Either way, invoke the pending init: on grant it will start the
        // session normally; on denial `ScannerSession.start` re-checks
        // permission and surfaces `permission_denied` via the Result's
        // failure path.
        mainHandler.post(pending)
        return true
    }
}

class QuadEventStream : EventChannel.StreamHandler {
    @Volatile private var sink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
    override fun onCancel(arguments: Any?) { sink = null }

    fun send(payload: Map<String, Any?>) {
        val s = sink ?: return
        mainHandler.post {
            try { s.success(payload) } catch (_: Exception) {}
        }
    }
}
