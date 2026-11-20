package dev.doclens.doclens

import android.content.Context
import android.os.Build
import java.io.File
import java.util.zip.ZipFile

/**
 * Packaging diagnostics: never executes user-supplied native code.
 *
 * Android can load shared objects directly from an APK when native libraries
 * are uncompressed and extractNativeLibs=false. File.exists() alone misses
 * those libraries, so inspect base/split APK entries as well.
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

    private val ownNames = listOf("libds_pagescanner.so", "libds_scannercore.so", "libds_docnet.so")

    fun status(context: Context): Map<String, Any> {
        val info = context.applicationInfo
        val nativeDir = info.nativeLibraryDir?.let(::File)
        val supported = Build.SUPPORTED_ABIS.toList()
        // Some apps deliver architecture-specific native libs in split APKs.
        val installedApks = listOfNotNull(info.sourceDir) +
            (info.splitSourceDirs?.toList() ?: emptyList())
        val packaged = mutableSetOf<String>()
        val ownPackaged = mutableSetOf<String>()
        installedApks.forEach { path ->
            try {
                ZipFile(path).use { apk ->
                    for (abi in supported) {
                        for (name in ownNames) {
                            if (apk.getEntry("lib/$abi/$name") != null) ownPackaged.add(name)
                        }
                        for (name in importedNames) {
                            if (apk.getEntry("lib/$abi/$name") != null) {
                                packaged.add(name)
                            }
                        }
                    }
                }
            } catch (_: Exception) {
                // Invalid/unreadable container must not interrupt a scan.
            }
        }
        val present = importedNames.associateWith { name ->
            (nativeDir?.let { File(it, name).isFile } == true) ||
                name in packaged
        }
        return mapOf(
            "abi" to supported,
            "importedPresent" to present,
            "importedCount" to present.values.count { it },
            "importedComplete" to present.values.all { it },
            // A present ELF does not imply valid JNI methods, models or rights.
            "importedFunctionsEnabled" to false,
            "independentNativeEnhancer" to "ds_pagescanner",
            // DocScanner's own native libraries (built from src/main/cpp).
            "ownLibraries" to ownNames.associateWith { name ->
                (nativeDir?.let { File(it, name).isFile } == true) || name in ownPackaged
            },
            "scannerCoreLoaded" to NativeScannerCore.available,
            "docNetLoaded" to DocNetEngine.isLoaded,
            "fallbackEngine" to "kotlin",
        )
    }
}
