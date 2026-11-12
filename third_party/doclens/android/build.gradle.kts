import org.jetbrains.kotlin.gradle.dsl.JvmTarget

group = "dev.doclens.doclens"
version = "0.1.0"

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

android {
    namespace = "dev.doclens.doclens"

    compileSdk = 34

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
            // The user-supplied CamScanner JNI archive is retained in
            // src/main/jniLibs for analysis, but none of its proprietary
            // binaries are referenced by Doclens. Packaging them causes
            // duplicate native libs (e.g. datastore_shared_counter.so) and
            // may override Flutter's own libflutter.so. The OpenCV AAR below
            // independently packages its supported JNI library.
            jniLibs.setSrcDirs(listOf("src/main/managedJniLibs"))
        }
        getByName("test") {
            java.srcDirs("src/test/kotlin")
        }
    }

    defaultConfig {
        minSdk = 21
    }

    // Compile an independently authored document-contour engine. AGP
    // packages libds_pagescanner.so automatically for each target ABI;
    // the user-supplied proprietary JNI archive remains excluded.
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
        }
    }

}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    val cameraxVersion = "1.3.4"
    // Offline, on-device document boundary detection. This is the same
    // OpenCV version used by the working Kotlin scanner reference project.
    implementation("org.opencv:opencv:4.10.0")
    implementation("androidx.camera:camera-core:$cameraxVersion")
    implementation("androidx.camera:camera-camera2:$cameraxVersion")
    implementation("androidx.camera:camera-lifecycle:$cameraxVersion")
    implementation("androidx.camera:camera-view:$cameraxVersion")
    implementation("androidx.exifinterface:exifinterface:1.3.7")

    // ML Kit Document Scanner (Play Services-delivered module).
    // Dependency reference: https://developers.google.com/ml-kit/vision/doc-scanner/android
    implementation("com.google.android.gms:play-services-mlkit-document-scanner:16.0.0")

    // ML Kit Latin text recognition (Play Services-delivered, downloaded on
    // demand) — used only by `AutoOrientation.auto` to find a captured page's
    // upright direction. No model is bundled in the host APK.
    // Reference: https://developers.google.com/ml-kit/vision/text-recognition/v2/android
    implementation("com.google.android.gms:play-services-mlkit-text-recognition:19.0.1")

    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")

    testImplementation("org.jetbrains.kotlin:kotlin-test")
}
