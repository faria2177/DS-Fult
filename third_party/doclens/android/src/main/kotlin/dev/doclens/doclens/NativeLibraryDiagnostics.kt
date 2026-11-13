package dev.doclens.doclens

import android.content.Context
import java.io.File

/**
 * Reports package presence only: no proprietary .so is loaded or executed.
 * Available for native-build smoke tests via "getNativeLibraryStatus".
 */
internal object NativeLibraryDiagnostics {
    private val importedNames = listOf(
        "libpagescanner.so",
        "libscannercs.so",
        "libopencv.so",
        "libimageprocessor.so",
        "libmagicenhancer.so",
        "libenhance4draft.so",
        "liboctopus_classifier.so",
        "libMNN.so",
        "libncnn.so",
        "libCVNN.so",
        "libmainstone.so",
    )

    fun status(context: Context): Map<String, Any> {
        val libraryDir = File(context.applicationInfo.nativeLibraryDir ?: "")
        val available = importedNames.associateWith { name ->
            libraryDir.isDirectory && File(libraryDir, name).isFile
        }
        return mapOf(
            "abi" to android.os.Build.SUPPORTED_ABIS.toList(),
            "importedPresent" to available,
            "importedCount" to available.values.count { it },
            "importedComplete" to available.values.all { it },
            // Presence/packaging is not an implementation of an API bridge.
            "importedFunctionsEnabled" to false,
            "independentNativeEnhancer" to "ds_pagescanner",
            "fallbackEngine" to "kotlin",
        )
    }
}
