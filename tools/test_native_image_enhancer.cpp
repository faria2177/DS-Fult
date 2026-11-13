// Standalone native regression test; requires C++17, no Android SDK.
// c++ -std=c++17 -O2 -fsanitize=address,undefined -fno-omit-frame-pointer \
//   tools/test_native_image_enhancer.cpp \
//   third_party/doclens/android/src/main/cpp/ds_image_enhancer.cpp \
//   -o /tmp/ds-native-test && /tmp/ds-native-test
#include "../third_party/doclens/android/src/main/cpp/ds_image_enhancer.h"

#include <cassert>
#include <cstdint>
#include <iostream>
#include <vector>

int main() {
    assert(!ds::EnhanceArgb(nullptr, 160, 120, true));

    const int width = 160, height = 120;
    std::vector<uint32_t> pixels(static_cast<size_t>(width) * height);
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            const int paper = 110 + x * 140 / width;
            const int light = (y > 30 && y < 36) ? paper * 65 / 100 : paper;
            pixels[static_cast<size_t>(y) * width + x] = 0xff000000u |
                (static_cast<uint32_t>(light) << 16) |
                (static_cast<uint32_t>(light) << 8) |
                static_cast<uint32_t>(light);
        }
    }
    assert(ds::EnhanceArgb(pixels.data(), width, height, true));
    for (int x : {10, 80, 150}) {
        assert((pixels[20 * width + x] & 255u) == 255u);
        assert((pixels[32 * width + x] & 255u) == 0u);
    }

    std::vector<uint32_t> colour(160 * 120, 0xffb0b0b0u);
    colour[60 * 160 + 60] = 0xffa03020u;
    assert(ds::EnhanceArgb(colour.data(), 160, 120, false));
    const uint32_t redInk = colour[60 * 160 + 60];
    assert(((redInk >> 16) & 255u) > ((redInk >> 8) & 255u));
    assert((redInk >> 24) == 255u);
    assert((colour[0] & 255u) > 176u);
    std::cout << "DocScanner native enhancement tests passed\n";
}
