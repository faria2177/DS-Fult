// Host tests for libds_dewarp.
#include "../../main/cpp/ds_dewarp.h"

#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <vector>

namespace {

int failures = 0;

void Check(bool ok, const char* what) {
    if (!ok) {
        std::printf("FAIL: %s\n", what);
        ++failures;
    }
}

constexpr int kW = 900, kH = 1100;
// Page occupies x 100..800, y 100..1000 when flat; the sheet is bowed by
// bow·sin(πu) (pixels), more at the bottom than at the top.
std::vector<uint32_t> Scene(double bow, bool curl = false) {
    std::vector<uint32_t> px(static_cast<size_t>(kW) * kH, 0xff3c2814U);
    for (int y = 0; y < kH; ++y) {
        for (int x = 100; x < 800; ++x) {
            const double u = (x - 100) / 700.0;
            const double v_flat = (y - 100) / 900.0;
            // Invert y = 100 + 900 v + bow·sin(πu)·g(v) for v; g is linear
            // (0.4 + 0.6 v) or, for a curl, quadratic (0.2 + 0.8 v²).
            const double s = bow * std::sin(M_PI * u);
            double v = v_flat;
            for (int it = 0; it < 30; ++it) {
                const double g = curl ? 0.2 + 0.8 * v * v : 0.4 + 0.6 * v;
                v = (v_flat * 900.0 - s * g) / 900.0;
            }
            if (v < 0 || v > 1) continue;
            const int line = static_cast<int>(v * 900.0) % 30;
            const bool ink = line >= 12 && line < 18 && u > .05 && u < .95;
            px[static_cast<size_t>(y) * kW + x] = ink ? 0xff202020U : 0xfff2f2f2U;
        }
    }
    return px;
}

// Row (in the output) of the ink line nearest to 'near' at column x.
int InkRow(const std::vector<uint32_t>& out, int w, int x, int near) {
    int best = -1;
    for (int d = 0; d < 20; ++d) {
        for (int y : {near - d, near + d}) {
            if (y < 0 || y >= static_cast<int>(out.size()) / w) continue;
            if ((out[static_cast<size_t>(y) * w + x] & 255U) < 100) return y;
        }
    }
    return best;
}

}  // namespace

int main() {
    const std::array<double, 8> quad = {100, 100, 800, 100, 800, 1000, 100, 1000};
    {
        const auto flat = Scene(0);
        std::vector<uint32_t> out;
        ds::DewarpInfo info;
        Check(!ds::Dewarp(flat.data(), kW, kH, quad, 700, 900, &out, &info),
              "flat page is left to the perspective crop");
        Check(info.max_bow < .004f, "flat page has no bow");
    }
    {
        const auto bent = Scene(36);  // 4 % of the page height
        std::vector<uint32_t> out;
        ds::DewarpInfo info;
        Check(ds::Dewarp(bent.data(), kW, kH, quad, 700, 900, &out, &info),
              "bowed page is dewarped");
        Check(info.max_bow > .02f && info.max_bow < .06f, "bow measured");
        Check(info.traced[0] && info.traced[2], "top and bottom traced");
        // A text line near the bottom must be level after dewarping.
        const int y = 900 - 120;
        const int a = InkRow(out, 700, 70, y);
        const int b = InkRow(out, 700, 350, y);
        const int c = InkRow(out, 700, 630, y);
        std::printf("ink rows %d %d %d (bow %.3f)\n", a, b, c, info.max_bow);
        Check(a >= 0 && b >= 0 && c >= 0, "ink found");
        Check(std::abs(a - b) <= 4 && std::abs(c - b) <= 4, "line is straight");
    }
    {
        // A curl: the middle of the page waves differently from its sides;
        // the text-line step straightens it.
        const auto curled = Scene(40, true);
        std::vector<uint32_t> out;
        ds::DewarpInfo info;
        Check(ds::Dewarp(curled.data(), kW, kH, quad, 700, 900, &out, &info),
              "curled page is dewarped");
        const int y = 900 / 2 + 15;
        const int a = InkRow(out, 700, 70, y);
        const int b = InkRow(out, 700, 350, y);
        const int c = InkRow(out, 700, 630, y);
        std::printf("curl rows %d %d %d (text lines %d, shift %.1f)\n", a, b, c,
                    info.text_lines, info.text_shift);
        Check(a >= 0 && b >= 0 && c >= 0, "curl ink found");
        Check(std::abs(a - b) <= 3 && std::abs(c - b) <= 3, "curled line is straight");
    }
    {
        std::vector<uint32_t> out;
        Check(!ds::Dewarp(nullptr, 10, 10, quad, 100, 100, &out, nullptr), "bad input");
    }
    if (failures == 0) std::printf("ds_dewarp: all tests passed\n");
    return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
