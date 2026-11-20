cmake_minimum_required(VERSION 3.18.1)
project(ds_native LANGUAGES CXX)

# Document boundary proposals + legacy enhancer.
add_library(ds_pagescanner SHARED
    ds_page_scanner.cpp
    ds_pagescanner_jni.cpp
    ds_image_enhancer.cpp
    ds_image_enhancer_jni.cpp
)

# Scanner core: paper-region crop and scanner-style (magic) enhancement.
add_library(ds_scannercore SHARED
    ds_scanner_core.cpp
    ds_scanner_core_jni.cpp
)

# PDF codec: CCITT Group 4 for black-and-white pages.
add_library(ds_pdfcodec SHARED
    ds_pdf_codec.cpp
    ds_pdf_codec_jni.cpp
)

foreach(target ds_pagescanner ds_scannercore ds_pdfcodec)
    target_compile_features(${target} PRIVATE cxx_std_17)
    target_compile_options(${target} PRIVATE -O3 -Wall -Wextra -Wconversion)
    set_target_properties(${target} PROPERTIES
        CXX_VISIBILITY_PRESET hidden
        VISIBILITY_INLINES_HIDDEN YES
    )
    # 16 KB page alignment for Android 15+ devices.
    target_link_options(${target} PRIVATE "-Wl,-z,max-page-size=16384")
endforeach()

# DocNet document-mask model on the ncnn inference engine (BSD-3-Clause).
# The prebuilt static ncnn for Android is downloaded at build time (pinned
# by hash); nothing binary is stored in the repository.
include(FetchContent)
FetchContent_Declare(ncnn_android
    URL https://github.com/Tencent/ncnn/releases/download/20241226/ncnn-20241226-android.zip
    URL_HASH SHA256=12d271f80caac740b7d485eaedde008ee21ebd448cb9352a061ce01810cef02a
)
FetchContent_GetProperties(ncnn_android)
if(NOT ncnn_android_POPULATED)
    FetchContent_Populate(ncnn_android)
endif()
set(ncnn_DIR "${ncnn_android_SOURCE_DIR}/${ANDROID_ABI}/lib/cmake/ncnn")
find_package(ncnn REQUIRED)

add_library(ds_docnet SHARED ds_docnet_jni.cpp)
target_compile_features(ds_docnet PRIVATE cxx_std_17)
target_compile_options(ds_docnet PRIVATE -O3 -fno-rtti -fno-exceptions)
target_link_libraries(ds_docnet ncnn android log)
set_target_properties(ds_docnet PROPERTIES
    CXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN YES
)
target_link_options(ds_docnet PRIVATE -static-openmp "-Wl,-z,max-page-size=16384")
