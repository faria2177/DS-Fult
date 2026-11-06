package dev.doclens.doclens

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.mockito.Mockito
import kotlin.test.Test

internal class DoclensPluginTest {
    @Test
    fun unrecognizedMethodReturnsNotImplemented() {
        val plugin = DoclensPlugin()
        // The plugin does not expose the historical getPlatformVersion demo
        // method. Check its real contract rather than expecting a method that
        // never existed in this scanner.
        val call = MethodCall("getPlatformVersion", null)
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)
        Mockito.verify(mockResult).notImplemented()
    }
}
