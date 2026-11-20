// Host tests for libds_pdfcodec. Golden streams were checked byte-for-byte
// against libtiff's Group 4 encoder.
#include "../../main/cpp/ds_pdf_codec.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

namespace {

int failures = 0;

void Check(bool ok, const char* what) {
    if (!ok) {
        std::printf("FAIL: %s\n", what);
        ++failures;
    }
}

std::string Hex(const std::vector<uint8_t>& v) {
    static const char* digits = "0123456789abcdef";
    std::string s;
    for (uint8_t b : v) {
        s += digits[b >> 4];
        s += digits[b & 15];
    }
    return s;
}

}  // namespace

int main() {
    {
        std::vector<uint8_t> white(2 * 64, 255), out;
        Check(ds::EncodeG4(white.data(), 64, 2, 128, &out), "encode white");
        Check(Hex(out) == "c0040040", "white golden");
    }
    {
        std::vector<uint8_t> g(4 * 16, 255), out;
        for (int x = 4; x < 9; ++x) g[1 * 16 + x] = 0;
        for (int x = 3; x < 10; ++x) g[2 * 16 + x] = 0;
        for (int x = 0; x < 16; ++x) g[3 * 16 + x] = 0;
        Check(ds::EncodeG4(g.data(), 16, 4, 128, &out), "encode pattern");
        Check(Hex(out) == "9b3a70441735001001", "pattern golden");
    }
    {
        // Long runs use extended make-up codes without crashing.
        const int w = 5000, h = 3;
        std::vector<uint8_t> g(static_cast<size_t>(w) * h, 255), out;
        for (int x = 100; x < 4900; ++x) g[static_cast<size_t>(w) + x] = 0;
        Check(ds::EncodeG4(g.data(), w, h, 128, &out) && out.size() < 40, "wide page");
    }
    {
        std::vector<uint8_t> g(100 * 100, 128);
        Check(ds::BilevelShare(g.data(), 100, 100) < .01, "grey photo not bilevel");
        for (auto& v : g) v = 250;
        Check(ds::BilevelShare(g.data(), 100, 100) > .99, "white page bilevel");
        std::vector<uint32_t> argb(100 * 100, 0xffffffffU);
        Check(ds::ColourShare(argb.data(), 100, 100) < .001, "white has no colour");
        for (int i = 0; i < 1000; ++i) argb[static_cast<size_t>(i)] = 0xff2040c0U;
        Check(ds::ColourShare(argb.data(), 100, 100) > .05, "blue stamp is colour");
    }
    Check(!ds::EncodeG4(nullptr, 10, 10, 128, nullptr), "bad input");
    if (failures == 0) std::printf("ds_pdf_codec: all tests passed\n");
    return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
