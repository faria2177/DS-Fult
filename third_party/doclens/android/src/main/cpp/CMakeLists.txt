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

foreach(target ds_pagescanner ds_scannercore)
    target_compile_features(${target} PRIVATE cxx_std_17)
    target_compile_options(${target} PRIVATE -O3 -Wall -Wextra -Wconversion)
    set_target_properties(${target} PROPERTIES
        CXX_VISIBILITY_PRESET hidden
        VISIBILITY_INLINES_HIDDEN YES
    )
    # 16 KB page alignment for Android 15+ devices.
    target_link_options(${target} PRIVATE "-Wl,-z,max-page-size=16384")
endforeach()
