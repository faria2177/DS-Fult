package dev.doclens.doclens

import android.content.res.AssetManager
import android.graphics.BitmapFactory
import org.opencv.android.OpenCVLoader
import org.opencv.core.CvType
import org.opencv.core.Mat
import org.opencv.core.Size
import org.opencv.dnn.Dnn
import org.opencv.dnn.Net
import org.opencv.imgcodecs.Imgcodecs
import org.opencv.imgproc.Imgproc

/**
 * Runs the bundled open-source U²-Net (small) salient-object network on a
 * still photo and returns a 320x320 foreground-probability map together with
 * the matching 320x320 RGB thumbnail. Flutter turns that map into four
 * document corners; nothing leaves the device.
 */
internal object SalientMaskEngine {
    const val SIDE = 320
    private const val EDGE_SIDE = 640.0
    /** Finest-resolution output of the rembg `u2netp.onnx` export. */
    private const val OUTPUT = "1959"
    private val MEAN = floatArrayOf(0.485f, 0.456f, 0.406f)
    private val STD = floatArrayOf(0.229f, 0.224f, 0.225f)

    private var net: Net? = null
    private var loadedModel: String? = null
    private var openCvReady = false

    /**
     * Probability map (SIDE×SIDE, 0..255) for a live RGBA camera frame.
     * Shares the loaded network with [run]; both are synchronized.
     */
    @Synchronized
    fun probabilityForRgba(modelPath: String, rgba: ByteArray, width: Int,
                           height: Int): ByteArray? {
        if (!openCvReady) {
            openCvReady = OpenCVLoader.initLocal()
            if (!openCvReady) return null
        }
        if (width <= 0 || height <= 0 || rgba.size != width * height * 4) return null
        val frame = Mat(height, width, CvType.CV_8UC4)
        val small = Mat()
        val flat = Mat(1, 3 * SIDE * SIDE, CvType.CV_32F)
        var blob: Mat? = null
        var output: Mat? = null
        var row: Mat? = null
        try {
            frame.put(0, 0, rgba)
            Imgproc.resize(frame, small, Size(SIDE.toDouble(), SIDE.toDouble()),
                0.0, 0.0, Imgproc.INTER_AREA)
            val pixels = ByteArray(SIDE * SIDE * 4)
            small.get(0, 0, pixels)
            val plane = SIDE * SIDE
            val input = FloatArray(plane * 3)
            for (i in 0 until plane) {
                val r = pixels[i * 4].toInt() and 0xFF
                val g = pixels[i * 4 + 1].toInt() and 0xFF
                val b = pixels[i * 4 + 2].toInt() and 0xFF
                input[i] = (r / 255f - MEAN[0]) / STD[0]
                input[plane + i] = (g / 255f - MEAN[1]) / STD[1]
                input[2 * plane + i] = (b / 255f - MEAN[2]) / STD[2]
            }
            flat.put(0, 0, input)
            blob = flat.reshape(1, intArrayOf(1, 3, SIDE, SIDE))
            // DocNet (document-specific, own model) first; U²-Net otherwise.
            val docNet = if (assets != null && DocNetEngine.ensureLoaded(assets)) {
                docNetProbability(small)
            } else null
            if (docNet != null) {
                return finish(decoded, docNet, rgb, imageWidth, imageHeight, "docnet")
            }

            var network = net
            if (network == null || loadedModel != modelPath) {
                network = Dnn.readNetFromONNX(modelPath)
                net = network
                loadedModel = modelPath
            }
            network!!.setInput(blob)
            output = network.forward(OUTPUT)
            if (output.total() != plane.toLong()) return null
            row = output.reshape(1, 1)
            val values = FloatArray(plane)
            row.get(0, 0, values)
            val probability = ByteArray(plane)
            for (i in 0 until plane) {
                val v = values[i]
                val clamped = if (v < 0f) 0f else if (v > 1f) 1f else v
                probability[i] = (clamped * 255f + 0.5f).toInt().toByte()
            }
            return probability
        } finally {
            frame.release()
            small.release()
            flat.release()
            blob?.release()
            output?.release()
            row?.release()
        }
    }

    @Synchronized
    fun run(modelPath: String, imagePath: String,
            assets: AssetManager? = null): Map<String, Any>? {
        if (!openCvReady) {
            openCvReady = OpenCVLoader.initLocal()
            if (!openCvReady) return null
        }
        // Read only the header first so a very large photo is decoded at a
        // reduced size instead of exhausting memory.
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(imagePath, bounds)
        val longest = maxOf(bounds.outWidth, bounds.outHeight)
        if (longest <= 0) return null
        val flag = when {
            longest > 8000 -> Imgcodecs.IMREAD_REDUCED_COLOR_8
            longest > 4000 -> Imgcodecs.IMREAD_REDUCED_COLOR_4
            longest > 2000 -> Imgcodecs.IMREAD_REDUCED_COLOR_2
            else -> Imgcodecs.IMREAD_COLOR
        }
        // imread applies the EXIF orientation, matching what the user sees.
        val decoded = Imgcodecs.imread(imagePath, flag)
        if (decoded.empty()) {
            decoded.release()
            return null
        }
        val small = Mat()
        val flat = Mat(1, 3 * SIDE * SIDE, CvType.CV_32F)
        var blob: Mat? = null
        var output: Mat? = null
        var row: Mat? = null
        try {
            val uprightIsLandscape = decoded.cols() > decoded.rows()
            val headerIsLandscape = bounds.outWidth > bounds.outHeight
            val imageWidth: Int
            val imageHeight: Int
            if (uprightIsLandscape == headerIsLandscape) {
                imageWidth = bounds.outWidth; imageHeight = bounds.outHeight
            } else {
                imageWidth = bounds.outHeight; imageHeight = bounds.outWidth
            }
            Imgproc.resize(decoded, small, Size(SIDE.toDouble(), SIDE.toDouble()),
                0.0, 0.0, Imgproc.INTER_AREA)
            val bgr = ByteArray(SIDE * SIDE * 3)
            small.get(0, 0, bgr)
            val plane = SIDE * SIDE
            val rgb = ByteArray(plane * 3)
            val input = FloatArray(plane * 3)
            for (i in 0 until plane) {
                val b = bgr[i * 3].toInt() and 0xFF
                val g = bgr[i * 3 + 1].toInt() and 0xFF
                val r = bgr[i * 3 + 2].toInt() and 0xFF
                rgb[i * 3] = r.toByte()
                rgb[i * 3 + 1] = g.toByte()
                rgb[i * 3 + 2] = b.toByte()
                input[i] = (r / 255f - MEAN[0]) / STD[0]
                input[plane + i] = (g / 255f - MEAN[1]) / STD[1]
                input[2 * plane + i] = (b / 255f - MEAN[2]) / STD[2]
            }
            flat.put(0, 0, input)
            blob = flat.reshape(1, intArrayOf(1, 3, SIDE, SIDE))

            var network = net
            if (network == null || loadedModel != modelPath) {
                network = Dnn.readNetFromONNX(modelPath)
                net = network
                loadedModel = modelPath
            }
            network!!.setInput(blob)
            output = network.forward(OUTPUT)
            if (output.total() != plane.toLong()) return null
            row = output.reshape(1, 1)
            val values = FloatArray(plane)
            row.get(0, 0, values)
            val probability = ByteArray(plane)
            for (i in 0 until plane) {
                val v = values[i]
                val clamped = if (v < 0f) 0f else if (v > 1f) 1f else v
                probability[i] = (clamped * 255f + 0.5f).toInt().toByte()
            }
            return finish(decoded, probability, rgb, imageWidth, imageHeight, "u2netp")
        } finally {
            decoded.release()
            small.release()
            flat.release()
            blob?.release()
            output?.release()
            row?.release()
        }
    }

    private fun docNetProbability(small: Mat): ByteArray? {
        val input = Mat()
        val rgbMat = Mat()
        val probMat = Mat(DocNetEngine.OUTPUT, DocNetEngine.OUTPUT, CvType.CV_32F)
        val upscaled = Mat()
        try {
            Imgproc.resize(small, input, Size(DocNetEngine.INPUT.toDouble(),
                DocNetEngine.INPUT.toDouble()), 0.0, 0.0, Imgproc.INTER_AREA)
            Imgproc.cvtColor(input, rgbMat, Imgproc.COLOR_BGR2RGB)
            val bytes = ByteArray(DocNetEngine.INPUT * DocNetEngine.INPUT * 3)
            rgbMat.get(0, 0, bytes)
            val prob = DocNetEngine.run(bytes) ?: return null
            probMat.put(0, 0, prob)
            Imgproc.resize(probMat, upscaled, Size(SIDE.toDouble(), SIDE.toDouble()),
                0.0, 0.0, Imgproc.INTER_LINEAR)
            val values = FloatArray(SIDE * SIDE)
            upscaled.get(0, 0, values)
            return ByteArray(SIDE * SIDE) { i ->
                val v = values[i]
                val clamped = if (v < 0f) 0f else if (v > 1f) 1f else v
                (clamped * 255f + 0.5f).toInt().toByte()
            }
        } finally {
            input.release()
            rgbMat.release()
            probMat.release()
            upscaled.release()
        }
    }

    private fun finish(decoded: Mat, probability: ByteArray, rgb: ByteArray,
                       imageWidth: Int, imageHeight: Int,
                       engine: String): Map<String, Any> {
        // A sharper, aspect-correct colour copy (long side 640) so Flutter
        // can check that every side of the outline sits on a real edge.
        val longSide = maxOf(decoded.cols(), decoded.rows()).toDouble()
        val scale = minOf(1.0, EDGE_SIDE / longSide)
        val edgeW = maxOf(1, Math.round(decoded.cols() * scale).toInt())
        val edgeH = maxOf(1, Math.round(decoded.rows() * scale).toInt())
        val edge = Mat()
        val edgeRgbMat = Mat()
        val edgeRgb = ByteArray(edgeW * edgeH * 3)
        try {
            Imgproc.resize(decoded, edge, Size(edgeW.toDouble(), edgeH.toDouble()),
                0.0, 0.0, Imgproc.INTER_AREA)
            Imgproc.cvtColor(edge, edgeRgbMat, Imgproc.COLOR_BGR2RGB)
            Imgproc.GaussianBlur(edgeRgbMat, edgeRgbMat, Size(3.0, 3.0), 0.0)
            edgeRgbMat.get(0, 0, edgeRgb)
        } finally {
            edge.release()
            edgeRgbMat.release()
        }
        return mapOf(
            "edgeWidth" to edgeW,
            "edgeHeight" to edgeH,
            "edgeRgb" to edgeRgb,
            "width" to SIDE,
            "height" to SIDE,
            "probability" to probability,
            "rgb" to rgb,
            "imageWidth" to imageWidth,
            "imageHeight" to imageHeight,
            "engine" to engine,
        )
    }
}
