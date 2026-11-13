#pragma once
#include <cstdint>

namespace ds {
// Independently implemented adaptive document enhancement.
// Mutates ARGB_8888 pixels only when inputs pass the safety checks.
bool EnhanceArgb(uint32_t* pixels, int width, int height, bool monochrome);
}  // namespace ds
