cmake_minimum_required(VERSION 3.18.1)
project(ds_pagescanner LANGUAGES CXX)

add_library(ds_pagescanner SHARED
    ds_page_scanner.cpp
    ds_pagescanner_jni.cpp
)
target_compile_features(ds_pagescanner PRIVATE cxx_std_17)
target_compile_options(ds_pagescanner PRIVATE -O3 -Wall -Wextra -Wconversion)
set_target_properties(ds_pagescanner PROPERTIES
    CXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN YES
)
