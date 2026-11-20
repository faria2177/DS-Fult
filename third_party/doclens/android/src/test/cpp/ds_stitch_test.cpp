// Host tests for libds_stitch.
#include "../../main/cpp/ds_stitch.h"

#include <algorithm>
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

constexpr int kW = 600;

// A long "receipt": text-like dark blocks of pseudo-random length per line.
std::vector<uint8_t> Receipt(int height, unsigned seed, bool repeating) {
    std::vector<uint8_t> px(static_cast<size_t>(kW) * height, 246);
    unsigned state = seed;
    auto next = [&state]() {
        state = state * 1103515245U + 12345U;
        return (state >> 16) & 0x7fffU;
    };
    for (int y = 30; y + 12 < height; y += repeating ? 30 : 26 + static_cast<int>(next() % 18)) {
        int x = 30;
        while (x < kW - 40) {
            const int word = repeating ? 120 : 20 + static_cast<int>(next() % 80);
            for (int yy = y; yy < y + 10; ++yy) {
                for (int xx = x; xx < std::min(kW - 30, x + word); ++xx) {
                    px[static_cast<size_t>(yy) * kW + xx] = 30;
                }
            }
            x += word + (repeating ? 40 : 10 + static_cast<int>(next() % 20));
        }
    }
    return px;
}

std::vector<uint8_t> Rows(const std::vector<uint8_t>& src, int from, int to) {
    return std::vector<uint8_t>(src.begin() + static_cast<std::ptrdiff_t>(from) * kW,
                                src.begin() + static_cast<std::ptrdiff_t>(to) * kW);
}

}  // namespace

int main() {
    const auto receipt = Receipt(2400, 7, false);
    {
        const auto a = Rows(receipt, 0, 1000);
        const auto b = Rows(receipt, 700, 1700);  // 300 rows repeat
        ds::Overlap o;
        Check(ds::FindOverlap(a.data(), 1000, b.data(), 1000, kW, &o), "overlap found");
        std::printf("overlap rows %d shift %d score %.3f\n", o.rows, o.shift, o.score);
        Check(o.rows >= 296 && o.rows <= 304, "overlap rows");
        Check(o.shift >= -2 && o.shift <= 2, "no shift");
    }
    {
        const auto a = Rows(receipt, 0, 1000);
        const auto other = Receipt(1000, 99, false);
        ds::Overlap o;
        Check(!ds::FindOverlap(a.data(), 1000, other.data(), 1000, kW, &o), "unrelated pages");
    }
    {
        const auto table = Receipt(2000, 1, true);
        const auto a = Rows(table, 0, 1000);
        const auto b = Rows(table, 700, 1700);
        ds::Overlap o;
        Check(!ds::FindOverlap(a.data(), 1000, b.data(), 1000, kW, &o),
              "repeating rows are ambiguous");
    }
    {
        std::vector<uint8_t> blank(static_cast<size_t>(kW) * 800, 246);
        ds::Overlap o;
        Check(!ds::FindOverlap(blank.data(), 800, blank.data(), 800, kW, &o), "blank pages");
    }
    if (failures == 0) std::printf("ds_stitch: all tests passed\n");
    return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
