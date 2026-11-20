#pragma once

#include <array>
#include <cstdint>
#include <vector>

// DocScanner dewarp (libds_dewarp.so): own C++17 code that flattens a bent,
// curled or bowed page.
//
// 1. The page quad is rectified with a margin, so a bulging edge stays in view.
// 2. Each side of the page is traced as a curve (the strongest
//    background→paper step along the side's normal), fitted robustly with a
//    cubic, and pinned to the page corners.
// 3. When at least one side is clearly curved, the page is resampled through
//    a Coons patch bounded by the four curves (then the perspective of the
//    quad), which straightens the sides and the text between them.
// Straight or unclear sides return false: the caller keeps its normal
// perspective crop.
namespace ds {

struct DewarpInfo {
    // Largest deviation of a side from a straight line, in page units.
    float max_bow = 0.0f;
    // Which sides were traced (top, right, bottom, left).
    std::array<bool, 4> traced{};
};

// src: ARGB width×height. quad: TL, TR, BR, BL in source pixels.
// out: out_width×out_height ARGB on success.
bool Dewarp(const uint32_t* src, int width, int height,
            const std::array<double, 8>& quad, int out_width, int out_height,
            std::vector<uint32_t>* out, DewarpInfo* info);

}  // namespace ds
