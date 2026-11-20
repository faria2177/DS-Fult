#pragma once

#include <cstdint>

// DocScanner long-image stitching (libds_stitch.so): own C++17 code that
// finds where the bottom of one scan and the top of the next show the same
// content (a long receipt or list photographed in parts, overlapping
// screenshots), so the parts can be joined without the repeated band.
namespace ds {

struct Overlap {
    int rows = 0;       // rows of B that repeat the bottom of A (0: none)
    int shift = 0;      // B's content sits this many pixels right of A's
    float score = 0.0f; // normalised cross-correlation of the matched band
};

// gray_a: width × height_a, gray_b: width × height_b (same width, 8-bit).
// Returns true and fills out when a clear, textured match exists.
bool FindOverlap(const uint8_t* gray_a, int height_a, const uint8_t* gray_b,
                 int height_b, int width, Overlap* out);

}  // namespace ds
