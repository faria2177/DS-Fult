#pragma once

#include <array>
#include <cstdint>
#include <string>
#include <vector>

// DocScanner QR / barcode reader (libds_qr.so): a thin wrapper around the
// open-source zxing-cpp decoder (Apache-2.0). Reads QR, Micro QR, Data
// Matrix, Aztec, PDF417, EAN/UPC, Code 128/39/93, Codabar, ITF and more
// from an 8-bit luminance image, fully on-device.
namespace ds {

struct Code {
    std::string format;           // e.g. "QRCode", "EAN-13"
    std::string text;             // decoded content (UTF-8)
    std::array<int, 8> corners{}; // TL, TR, BR, BL in image pixels
};

// try_harder: slower, finds small / rotated / low-contrast codes (stills).
bool ReadCodes(const uint8_t* luma, int width, int height, bool try_harder,
               std::vector<Code>* out);

}  // namespace ds
