package dev.doclens.doclens

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import io.flutter.plugin.common.EventChannel
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2

/** Gravity-based two-axis level, sampled locally; never leaves the phone. */
class DeviceLevelStream(context: Context) : EventChannel.StreamHandler, SensorEventListener {
    private val manager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val accelerometer = manager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
    private var sink: EventChannel.EventSink? = null
    private var lastEmittedMs = 0L

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        accelerometer?.let { manager.registerListener(this, it, SensorManager.SENSOR_DELAY_UI) }
    }

    override fun onCancel(arguments: Any?) {
        manager.unregisterListener(this)
        sink = null
    }

    override fun onSensorChanged(event: SensorEvent) {
        if (event.sensor.type != Sensor.TYPE_ACCELEROMETER) return
        val now = System.currentTimeMillis()
        if (now - lastEmittedMs < 100) return
        lastEmittedMs = now
        val z = abs(event.values[2].toDouble()).coerceAtLeast(.01)
        val x = atan2(event.values[0].toDouble(), z) * 180.0 / PI
        val y = atan2(event.values[1].toDouble(), z) * 180.0 / PI
        sink?.success(mapOf("x" to x, "y" to y))
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    fun dispose() {
        manager.unregisterListener(this)
        sink = null
    }
}
