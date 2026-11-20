// Host tests for libds_scannercore (g++ -std=c++17, no Android needed).
#include "../../main/cpp/ds_scanner_core.h"

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

uint32_t Rgb(int r, int g, int b) {
    return 0xff000000U | (static_cast<uint32_t>(r) << 16) |
           (static_cast<uint32_t>(g) << 8) | static_cast<uint32_t>(b);
}

int R(uint32_t p) { return static_cast<int>((p >> 16) & 255U); }
int B(uint32_t p) { return static_cast<int>(p & 255U); }

void ShadowedPageBecomesWhiteWithDarkText() {
    const int w = 300, h = 400;
    std::vector<uint32_t> px(static_cast<size_t>(w) * h);
    for (int y = 0; y < h; ++y) {
        for (int x = 0; x < w; ++x) {
            const double v = 190 - 60 * (x / 300.0 + y / 400.0) / 2;
            px[static_cast<size_t>(y) * w + x] = Rgb(static_cast<int>(std::lround(v)),
                static_cast<int>(std::lround(v + 6)), static_cast<int>(std::lround(v + 10)));
        }
    }
    for (int row = 0; row < 12; ++row) {
        const int y = 30 + row * 30;
        for (int x = 30; x < 270; ++x) {
            for (int t = 0; t < 3; ++t) px[static_cast<size_t>(y + t) * w + x] = Rgb(55, 55, 60);
        }
    }
    Check(ds::IsNeutralDocument(px.data(), w, h), "grey page is neutral");
    Check(ds::MagicEnhance(px.data(), w, h), "enhance runs");
    auto at = [&](int x, int y) { return px[static_cast<size_t>(y) * w + x]; };
    Check(R(at(20, 15)) > 245, "bright paper white");
    Check(R(at(285, 380)) > 245, "shadowed paper white");
    Check(R(at(100, 31)) < 70, "text dark (top)");
    Check(R(at(250, 361)) < 70, "text dark (shadow)");
}

void StampKeepsColour() {
    const int w = 200, h = 200;
    std::vector<uint32_t> px(static_cast<size_t>(w) * h, Rgb(200, 200, 196));
    for (int y = 90; y < 110; ++y) {
        for (int x = 90; x < 110; ++x) px[static_cast<size_t>(y) * w + x] = Rgb(40, 60, 170);
    }
    ds::MagicEnhance(px.data(), w, h);
    const uint32_t ink = px[100 * w + 100];
    Check(B(ink) > R(ink) + 40, "blue ink stays blue");
    Check(R(px[20 * w + 20]) == 255, "paper pure white");
}

void GoldCardIsNotNeutral() {
    const int w = 160, h = 200;
    std::vector<uint32_t> px(static_cast<size_t>(w) * h, Rgb(190, 170, 123));
    Check(!ds::IsNeutralDocument(px.data(), w, h), "gold card is not neutral");
}

// 386313: page runs off top and bottom; a light rail touches both sides.
std::vector<uint32_t> RailScene(int w, int h, bool rail) {
    std::vector<uint32_t> px(static_cast<size_t>(w) * h, Rgb(60, 70, 110));
    if (rail) {
        for (int y = 232; y < 248; ++y) {
            for (int x = 0; x < w; ++x) px[static_cast<size_t>(y) * w + x] = Rgb(200, 200, 196);
        }
    }
    for (int y = 0; y < h; ++y) {
        const double left = 25 + 35.0 * y / h;
        const double right = 598 - 28.0 * y / h;
        for (int x = 0; x < w; ++x) {
            if (x >= left && x <= right) px[static_cast<size_t>(y) * w + x] = Rgb(232, 234, 230);
        }
    }
    for (int r = 0; r < 10; ++r) {
        const int y = 30 + r * 30;
        for (int x = 100; x < 500; ++x) {
            px[static_cast<size_t>(y) * w + x] = Rgb(30, 30, 30);
            px[static_cast<size_t>(y + 1) * w + x] = Rgb(30, 30, 30);
        }
    }
    return px;
}

void RailDoesNotStopCrop() {
    const int w = 640, h = 360;
    for (bool rail : {false, true}) {
        const std::vector<uint32_t> px = RailScene(w, h, rail);
        ds::PaperRegion region;
        Check(ds::FindPaperRegion(px.data(), w, h, &region), "region runs");
        Check(region.found, rail ? "found with rail" : "found without rail");
        if (!region.found) continue;
        const auto& c = region.corners;
        Check(std::fabs(c[0] - 25.0 / 640) < .025, "TL x");
        Check(std::fabs(c[2] - 598.0 / 640) < .025, "TR x");
        Check(std::fabs(c[4] - 570.0 / 640) < .025, "BR x");
        Check(std::fabs(c[6] - 60.0 / 640) < .025, "BL x");
        Check(c[1] < .02 && c[3] < .02 && c[5] > .98 && c[7] > .98, "top/bottom on frame");
    }
}

void AllPaperGivesNoCrop() {
    const int w = 300, h = 400;
    std::vector<uint32_t> px(static_cast<size_t>(w) * h, Rgb(240, 240, 236));
    for (int y = 40; y < 360; y += 20) {
        for (int x = 30; x < 270; ++x) px[static_cast<size_t>(y) * w + x] = Rgb(20, 20, 20);
    }
    ds::PaperRegion region;
    ds::FindPaperRegion(px.data(), w, h, &region);
    Check(!region.found, "all paper: no crop");
}

void RejectsBadInput() {
    ds::PaperRegion region;
    Check(!ds::FindPaperRegion(nullptr, 100, 100, &region), "null pixels");
    uint32_t one = 0;
    Check(!ds::MagicEnhance(&one, 1, 1), "tiny image");
}

}  // namespace

int main() {
    ShadowedPageBecomesWhiteWithDarkText();
    StampKeepsColour();
    GoldCardIsNotNeutral();
    RailDoesNotStopCrop();
    AllPaperGivesNoCrop();
    RejectsBadInput();
    if (failures == 0) std::printf("ds_scanner_core: all tests passed\n");
    return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
