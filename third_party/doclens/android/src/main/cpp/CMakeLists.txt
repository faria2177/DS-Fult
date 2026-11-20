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

# Dewarp: flattens bent, curled or bowed pages.
add_library(ds_dewarp SHARED
    ds_dewarp.cpp
    ds_dewarp_jni.cpp
)

foreach(target ds_pagescanner ds_scannercore ds_pdfcodec ds_dewarp)
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
# ncnn is built from its pinned source release with only what DocNet needs:
# float32 CPU inference, the layers below, no Vulkan / int8 / bf16 / OpenMP /
# runtime CPU dispatch. That keeps libds_docnet.so around 1 MB instead of the
# 5 MB the full prebuilt library produced.
include(FetchContent)
FetchContent_Declare(ncnn_source
    URL https://github.com/Tencent/ncnn/releases/download/20241226/ncnn-20241226-full-source.zip
    URL_HASH SHA256=b2145f7b01422f5ee66777d1c2c29de935191ed39865193951e1a7228202a6c1
)
FetchContent_GetProperties(ncnn_source)
if(NOT ncnn_source_POPULATED)
    FetchContent_Populate(ncnn_source)
endif()

foreach(option
    NCNN_VULKAN NCNN_INT8 NCNN_BF16 NCNN_OPENMP NCNN_RUNTIME_CPU
    NCNN_PIXEL_ROTATE NCNN_PIXEL_AFFINE NCNN_PIXEL_DRAWING NCNN_C_API
    NCNN_BUILD_TOOLS NCNN_BUILD_EXAMPLES NCNN_BUILD_BENCHMARK NCNN_BUILD_TESTS
    NCNN_INSTALL_SDK NCNN_SHARED_LIB
    # Without runtime dispatch every enabled ISA extension would be required
    # by the whole library (SIGILL on CPUs without it): keep the ABI baseline
    # only (NEON on arm64, SSE2 on x86_64).
    NCNN_ARM82 NCNN_ARM82DOT NCNN_ARM82FP16FML NCNN_ARM84BF16 NCNN_ARM84I8MM
    NCNN_ARM86SVE NCNN_ARM86SVE2 NCNN_ARM86SVEBF16 NCNN_ARM86SVEF32MM
    NCNN_ARM86SVEI8MM NCNN_AVX NCNN_AVX2 NCNN_AVX512 NCNN_AVX512BF16
    NCNN_AVX512FP16 NCNN_AVX512VNNI NCNN_AVXNECONVERT NCNN_AVXVNNI
    NCNN_AVXVNNIINT16 NCNN_AVXVNNIINT8 NCNN_F16C NCNN_FMA NCNN_XOP)
    set(${option} OFF CACHE BOOL "" FORCE)
endforeach()
# Layers DocNet uses (directly or inside ncnn) stay on: Input Convolution
# ConvolutionDepthWise Concat Interp Split ReLU Clip Sigmoid Mish HardSwish
# Padding Packing Cast Crop Flatten InnerProduct Convolution1D Bias Scale
# Noop Reshape. Every other layer is left out.
foreach(layer
    absval argmax batchnorm bnll deconvolution dropout
    eltwise elu embed exp log lrn
    memorydata mvn pooling power prelu proposal
    reduction roipooling slice softmax spp tanh
    threshold tile rnn lstm binaryop unaryop
    squeeze expanddims normalize permute priorbox detectionoutput
    deconvolutiondepthwise shufflechannel instancenorm reorg yolodetectionoutput quantize
    dequantize yolov3detectionoutput psroipooling roialign requantize hardsigmoid
    selu pixelshuffle deepcopy statisticspooling swish gemm
    groupnorm layernorm softplus gru multiheadattention gelu
    pooling1d convolutiondepthwise1d convolution3d convolutiondepthwise3d pooling3d matmul
    deconvolution1d deconvolutiondepthwise1d deconvolution3d deconvolutiondepthwise3d einsum deformableconv2d
    glu fold unfold gridsample cumulativesum copyto
    erf diag celu shrink rmsnorm spectrogram
    inversespectrogram)
    set(WITH_LAYER_${layer} OFF CACHE BOOL "" FORCE)
endforeach()
set(CMAKE_POLICY_VERSION_MINIMUM 3.5)
add_compile_options(-ffunction-sections -fdata-sections)
add_subdirectory(${ncnn_source_SOURCE_DIR} ${ncnn_source_BINARY_DIR} EXCLUDE_FROM_ALL)

add_library(ds_docnet SHARED ds_docnet_jni.cpp)
target_compile_features(ds_docnet PRIVATE cxx_std_17)
target_compile_options(ds_docnet PRIVATE -O3 -fno-rtti -fno-exceptions)
target_link_libraries(ds_docnet ncnn android log)
set_target_properties(ds_docnet PROPERTIES
    CXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN YES
)
target_link_options(ds_docnet PRIVATE -Wl,--gc-sections "-Wl,-z,max-page-size=16384")
