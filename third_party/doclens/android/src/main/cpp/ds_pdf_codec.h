#pragma once

#include <cstdint>
#include <vector>

// DocScanner PDF codec (libds_pdfcodec.so): own C++17 implementation of
// CCITT Group 4 (ITU-T T.6) for black-and-white pages. A B&W page stored
// as 1-bit G4 in the PDF is typically 5–10× smaller than the same page as
// JPEG, with sharper text. PDF readers decode it with /CCITTFaxDecode.
namespace ds {

// Share of pixels that are clearly black (< 64) or clearly white (> 191).
// A page above ~0.97 is already black-and-white, so 1-bit loses nothing.
double BilevelShare(const uint8_t* gray, int width, int height);

// Share of clearly coloured pixels (max−min channel > 48) in ARGB pixels;
// a page with stamps or colour print must stay a colour image.
double ColourShare(const uint32_t* argb, int width, int height);

// ARGB → 8-bit luma.
void ArgbToGray(const uint32_t* argb, int width, int height, uint8_t* gray);

// Encodes gray (one byte per pixel, row-major) as T.6 with EOFB, MSB first.
// Pixels below threshold are black. Output matches /CCITTFaxDecode with
// /K -1 /Columns width /Rows height /BlackIs1 false.
bool EncodeG4(const uint8_t* gray, int width, int height, int threshold,
              std::vector<uint8_t>* out);

}  // namespace ds
