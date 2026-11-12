#pragma once

#include <array>
#include <cstdint>

namespace ds {

// Normalized TL, TR, BR, BL corners. A false result means "keep the source",
// not "warp a guessed inner rectangle". No OpenCV or proprietary dependency.
struct Boundary {
    std::array<float, 8> corners{};
    float confidence = 0.0f;  // Relative evidence score, not a calibrated probability.
    int mode = -1;            // 0: chroma, 1: bright, 2: dark, 3: BG difference, 4: neutral.
};

bool DetectDocument(const uint32_t* argb, int width, int height,
                    bool prefer_card, Boundary* output);

}  // namespace ds
