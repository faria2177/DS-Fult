#pragma once

#include <array>
#include <cstdint>

// DocScanner scanner core (libds_scannercore.so).
//
// Independently written C++17, no OpenCV and no third-party code. It is the
// native twin of lib/src/services/paper_region_detector.dart and
// scanDocument() in lib/src/services/image_processor.dart; the Dart versions
// stay as the fallback and as the reference for tests.
namespace ds {

// True for a black-and-white page: mostly colourless and mostly bright.
bool IsNeutralDocument(const uint32_t* argb, int width, int height);

// Scanner-style enhancement of a cropped black-and-white page, in place:
// paper map (per-block 95th percentile, widened, smoothed) → divide →
// tone curve (paper white, ink dark) → light unsharp mask. Coloured ink
// keeps its colour. Returns false (pixels untouched) for bad input.
bool MagicEnhance(uint32_t* argb, int width, int height);

struct PaperRegion {
    // Normalised TL, TR, BR, BL. Valid only when found is true.
    std::array<float, 8> corners{};
    float paper_fraction = 0.0f;  // share of the photo that is paper
    bool found = false;
};

// Visible outline of a sheet that fills much of a photo, even when it runs
// off the frame. Expects a downscaled photo (long side about 420 px).
// Returns false only for unusable input; "no sheet" is found == false.
bool FindPaperRegion(const uint32_t* argb, int width, int height,
                     PaperRegion* output);

}  // namespace ds
