#include "ds_image_enhancer.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace ds {

// Estimates the paper's local brightness from each tile's 85th percentile
// instead of its mean. This avoids treating dark letters as shadow.
bool EnhanceArgb(uint32_t* pixels, int width, int height, bool monochrome) {
    if (!pixels || width < 8 || height < 8 || width > 3200 || height > 3200 ||
        static_cast<int64_t>(width) * height > 8000000) return false;

    const int tile = std::max(24, std::max(width, height) / 80);
    const int cols = (width + tile - 1) / tile;
    const int rows = (height + tile - 1) / tile;
    using Histogram = std::array<uint32_t, 16>;
    std::vector<Histogram> histogram(static_cast<size_t>(cols) * rows);
    std::vector<uint32_t> count(static_cast<size_t>(cols) * rows);

    for (int y = 0; y < height; ++y) {
        const int block_row = (y / tile) * cols;
        for (int x = 0; x < width; ++x) {
            const uint32_t p = pixels[static_cast<size_t>(y) * width + x];
            const int r = (p >> 16) & 255, g = (p >> 8) & 255, b = p & 255;
            const int luminance = (77 * r + 150 * g + 29 * b) >> 8;
            const size_t cell = static_cast<size_t>(block_row + x / tile);
            ++histogram[cell][luminance >> 4];
            ++count[cell];
        }
    }

    std::vector<float> background(count.size());
    for (size_t k = 0; k < count.size(); ++k) {
        uint32_t accum = 0;
        const uint32_t percentile = (count[k] * 85U + 99U) / 100U;
        int level = 15;
        for (int i = 0; i < 16; ++i) {
            accum += histogram[k][i];
            if (accum >= percentile) { level = i; break; }
        }
        background[k] = static_cast<float>(level * 16 + 8);
    }

    // Bilinear interpolation avoids hard seams between tiles.
    for (int y = 0; y < height; ++y) {
        const float gy = (static_cast<float>(y) + 0.5f) /
            static_cast<float>(tile) - 0.5f;
        const int iy = static_cast<int>(std::floor(gy));
        const int y0 = std::clamp(iy, 0, rows - 1);
        const int y1 = std::clamp(iy + 1, 0, rows - 1);
        const float fy = std::clamp(gy - static_cast<float>(iy), 0.f, 1.f);
        for (int x = 0; x < width; ++x) {
            const float gx = (static_cast<float>(x) + 0.5f) /
                static_cast<float>(tile) - 0.5f;
            const int ix = static_cast<int>(std::floor(gx));
            const int x0 = std::clamp(ix, 0, cols - 1);
            const int x1 = std::clamp(ix + 1, 0, cols - 1);
            const float fx = std::clamp(gx - static_cast<float>(ix), 0.f, 1.f);
            const float top = background[y0 * cols + x0] * (1 - fx) +
                background[y0 * cols + x1] * fx;
            const float bottom = background[y1 * cols + x0] * (1 - fx) +
                background[y1 * cols + x1] * fx;
            const float bg = std::max(32.f, top * (1 - fy) + bottom * fy);

            uint32_t& p = pixels[static_cast<size_t>(y) * width + x];
            const int r = (p >> 16) & 255, g = (p >> 8) & 255, b = p & 255;
            const int lum = (77 * r + 150 * g + 29 * b) >> 8;
            const float normalized = static_cast<float>(lum) *
                std::min(2.2f, 250.f / bg);

            if (monochrome) {
                const uint32_t v = normalized >= 209.f ? 255U : 0U;
                p = 0xff000000U | (v << 16) | (v << 8) | v;
            } else {
                const float target = std::clamp(
                    (normalized - 208.f) * 1.10f + 208.f, 0.f, 255.f);
                const float gain = target /
                    static_cast<float>(std::max(1, lum));
                auto channel = [gain](int c) -> uint32_t {
                    return static_cast<uint32_t>(std::clamp(
                        static_cast<float>(c) * gain, 0.f, 255.f) + 0.5f);
                };
                p = 0xff000000U | (channel(r) << 16) |
                    (channel(g) << 8) | channel(b);
            }
        }
    }
    return true;
}
}  // namespace ds
