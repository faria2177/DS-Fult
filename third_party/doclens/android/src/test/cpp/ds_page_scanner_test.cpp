#include <algorithm>
#include <cassert>
#include <cstdlib>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <vector>

#include "../../main/cpp/ds_page_scanner.h"

namespace {
uint32_t Color(int r, int g, int b) {
    return 0xFF000000u | (uint32_t(r) << 16) | (uint32_t(g) << 8) | uint32_t(b);
}
void Rect(std::vector<uint32_t>* image, int w, int h,
          int left, int top, int right, int bottom, uint32_t color) {
    for (int y = top; y < bottom && y < h; ++y)
        for (int x = left; x < right && x < w; ++x)
            (*image)[y * w + x] = color;
}
void Close(float value, float expected, float tolerance = .055f) {
    if (std::fabs(value - expected) > tolerance) {
        std::fprintf(stderr, "corner %.4f expected %.4f\n", value, expected);
        std::abort();
    }
}
}

int main() {
    const int w = 640, h = 480;
    ds::Boundary result;

    // Empty, uniform photos must never produce destructive guessed crops.
    std::vector<uint32_t> image(w * h, Color(240, 240, 240));
    assert(!ds::DetectDocument(image.data(), w, h, false, &result));

    // Pale gold ID card on a ruled white notebook. The notebook's blue
    // 1-pixel strokes must not join the genuine card foreground component.
    for (int y = 12; y < h; y += 24)
        Rect(&image, w, h, 0, y, w, y + 1, Color(110, 165, 210));
    Rect(&image, w, h, 148, 132, 500, 342, Color(204, 179, 113));
    ds::Boundary gold;
    assert(ds::DetectDocument(image.data(), w, h, true, &gold));
    assert(gold.confidence >= .70f);
    Close(gold.corners[0], 148.0f / w);
    Close(gold.corners[1], 132.0f / h);
    Close(gold.corners[4], 500.0f / w);
    Close(gold.corners[5], 342.0f / h);

    // A pale A4-like sheet on a dark table; bright surface detection must
    // produce the full outer sheet instead of inventing an inner text box.
    std::fill(image.begin(), image.end(), Color(43, 48, 51));
    Rect(&image, w, h, 142, 39, 506, 436, Color(248, 248, 242));
    Rect(&image, w, h, 188, 134, 455, 137, Color(25, 25, 25));
    Rect(&image, w, h, 188, 155, 455, 158, Color(25, 25, 25));
    ds::Boundary page;
    assert(ds::DetectDocument(image.data(), w, h, false, &page));
    Close(page.corners[0], 142.0f / w);
    Close(page.corners[1], 39.0f / h);
    Close(page.corners[4], 506.0f / w);
    Close(page.corners[5], 436.0f / h);

    // Regression 382147.mp4: a white NID has a silver/grey reflective
    // holder, lying on a black tabletop. The ordinary loose bright mask
    // touches the photo frame, and a dark printed header divider splits
    // the actual white document into two regions.
    const int cardW = 640, cardH = 800;
    std::vector<uint32_t> darkImage(cardW * cardH, Color(30, 32, 35));
    Rect(&darkImage, cardW, cardH, 0, 175, cardW, 580,
         Color(148, 149, 147));  // Holder touches image frame.
    Rect(&darkImage, cardW, cardH, 30, 215, 610, 550,
         Color(241, 239, 233));
    Rect(&darkImage, cardW, cardH, 32, 333, 608, 340,
         Color(28, 31, 34));  // Thick printed horizontal divider.
    Rect(&darkImage, cardW, cardH, 175, 407, 484, 413,
         Color(64, 65, 66));
    ds::Boundary whiteNid;
    assert(ds::DetectDocument(darkImage.data(), cardW, cardH,
                              false, &whiteNid));
    Close(whiteNid.corners[0], 30.0f / cardW);
    Close(whiteNid.corners[1], 215.0f / cardH);
    Close(whiteNid.corners[4], 609.0f / cardW);
    Close(whiteNid.corners[5], 549.0f / cardH);
    assert(whiteNid.mode == 5);

    // A page with only narrow dark ruling is not a freestanding document.
    std::fill(image.begin(), image.end(), Color(246, 246, 246));
    for (int y = 15; y < h; y += 25)
        Rect(&image, w, h, 0, y, w, y + 1, Color(110, 165, 210));
    assert(!ds::DetectDocument(image.data(), w, h, false, &result));

    // Invalid dimensions are rejected before any array access.
    assert(!ds::DetectDocument(image.data(), 0, h, false, &result));
    assert(!ds::DetectDocument(nullptr, w, h, false, &result));
    std::puts("Native DS document boundary tests passed");
    return 0;
}
