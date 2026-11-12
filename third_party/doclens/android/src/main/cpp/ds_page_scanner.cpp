#include "ds_page_scanner.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <vector>

namespace ds {
namespace {

struct Color {
    int r = 0;
    int g = 0;
    int b = 0;
    int light() const { return (r * 77 + g * 150 + b * 29) >> 8; }
    int chroma() const { return std::max({r, g, b}) - std::min({r, g, b}); }
};
struct Pt {
    float x = 0;
    float y = 0;
};
Color Unpack(uint32_t p) {
    return {static_cast<int>((p >> 16) & 255),
            static_cast<int>((p >> 8) & 255),
            static_cast<int>(p & 255)};
}
bool Colored(Color c) {
    const int peak = std::max({c.r, c.g, c.b});
    const int gap = c.chroma();
    return (peak >= 95 && gap * 100 >= peak * 32) ||
           (c.r >= 130 && c.g >= 105 && c.r - c.b >= 34 && c.g - c.b >= 14);
}
float Clamp01(float x) { return std::clamp(x, 0.0f, 1.0f); }
float Distance(Pt a, Pt b) { return std::hypot(a.x - b.x, a.y - b.y); }

float Area(const std::array<Pt, 4>& q) {
    float twice = 0.0f;
    for (int i = 0; i < 4; ++i) {
        const Pt a = q[i], b = q[(i + 1) % 4];
        twice += a.x * b.y - a.y * b.x;
    }
    return std::fabs(twice) * 0.5f;
}

float FourEdgeContrast(const uint32_t* data, int w, int h,
                       const std::array<Pt, 4>& q) {
    const Pt center{(q[0].x + q[1].x + q[2].x + q[3].x) * .25f,
                    (q[0].y + q[1].y + q[2].y + q[3].y) * .25f};
    float sum = 0;
    int strong = 0;
    for (int side = 0; side < 4; ++side) {
        const Pt a = q[side], b = q[(side + 1) % 4];
        const float dx = b.x - a.x, dy = b.y - a.y;
        const float length = std::hypot(dx, dy);
        if (length < 12) return 0;
        float nx = dy / length, ny = -dx / length;
        const Pt mid{(a.x + b.x) * .5f, (a.y + b.y) * .5f};
        if (nx * (mid.x - center.x) + ny * (mid.y - center.y) < 0) {
            nx = -nx;
            ny = -ny;
        }
        float bestOffset = 0;
        for (const int reach : {5, 10, 18}) {
            float contrast = 0;
            int sampled = 0;
            for (int sample = 1; sample <= 9; ++sample) {
                const float t = sample / 10.0f;
                const float px = a.x + dx * t, py = a.y + dy * t;
                const int ix = static_cast<int>(std::lround(px - nx * reach));
                const int iy = static_cast<int>(std::lround(py - ny * reach));
                const int ox = static_cast<int>(std::lround(px + nx * reach));
                const int oy = static_cast<int>(std::lround(py + ny * reach));
                if (ix < 0 || ix >= w || iy < 0 || iy >= h ||
                    ox < 0 || ox >= w || oy < 0 || oy >= h) continue;
                const Color in = Unpack(data[iy * w + ix]);
                const Color out = Unpack(data[oy * w + ox]);
                const int delta = (std::abs(in.r - out.r) +
                                   std::abs(in.g - out.g) +
                                   std::abs(in.b - out.b)) / 3;
                contrast += Clamp01((delta - 9.0f) / 37.0f);
                ++sampled;
            }
            if (sampled >= 5) {
                bestOffset = std::max(bestOffset, contrast / sampled);
            }
        }
        if (bestOffset >= .40f) ++strong;
        sum += bestOffset;
    }
    return Clamp01(sum / 4.0f * .65f + (strong / 4.0f) * .35f);
}

void OpenThinRules(std::vector<uint8_t>* mask, int w, int h) {
    // 3x3 7/9 erosion, followed by dilation, removes 1-2px coloured
    // notebook ruling while retaining a wide connected coloured ID surface.
    std::vector<uint8_t> core(mask->size(), 0);
    for (int y = 1; y < h - 1; ++y) {
        for (int x = 1; x < w - 1; ++x) {
            const int idx = y * w + x;
            if ((*mask)[idx] == 0) continue;
            int neighbors = 0;
            for (int dy = -1; dy <= 1; ++dy)
                for (int dx = -1; dx <= 1; ++dx)
                    neighbors += ((*mask)[idx + dy * w + dx] != 0);
            if (neighbors >= 7) core[idx] = 1;
        }
    }
    std::fill(mask->begin(), mask->end(), 0);
    for (int y = 1; y < h - 1; ++y) {
        for (int x = 1; x < w - 1; ++x) {
            const int idx = y * w + x;
            if (!core[idx]) continue;
            for (int dy = -1; dy <= 1; ++dy)
                for (int dx = -1; dx <= 1; ++dx)
                    (*mask)[idx + dy * w + dx] = 1;
        }
    }
}

bool AnalyzeMode(const uint32_t* pixels, int w, int h, int mode,
                 const Color background, int background_light,
                 int difference_threshold, bool prefer_card,
                 Boundary* best) {
    const int n = w * h;
    std::vector<uint8_t> mask(n, 0);
    int on = 0;
    for (int i = 0; i < n; ++i) {
        const Color c = Unpack(pixels[i]);
        const int light = c.light();
        bool selected = false;
        switch (mode) {
            case 0: selected = Colored(c); break;
            case 1: selected = light >= std::max(117, background_light + 34); break;
            case 2: selected = light <= std::min(152, background_light - 43); break;
            case 3:
                selected = (std::abs(c.r - background.r) +
                            std::abs(c.g - background.g) +
                            std::abs(c.b - background.b)) / 3 >= difference_threshold;
                break;
            case 4:
                selected = light >= 130 && c.chroma() <= 34;
                break;
        }
        mask[i] = static_cast<uint8_t>(selected);
        on += selected;
    }
    if (on < n * .10f || on > n * .88f) return false;
    if (mode == 0) OpenThinRules(&mask, w, h);

    std::vector<uint8_t> seen(n, 0);
    std::vector<int> stack;
    stack.reserve(n / 8);
    bool found = false;

    for (int start = 0; start < n; ++start) {
        if (!mask[start] || seen[start]) continue;
        stack.clear();
        stack.push_back(start);
        seen[start] = 1;
        int count = 0, frame = 0;
        float low_sum = std::numeric_limits<float>::infinity();
        float high_sum = -low_sum;
        float low_diff = low_sum, high_diff = -low_sum;
        std::array<Pt, 4> q{};
        while (!stack.empty()) {
            const int idx = stack.back();
            stack.pop_back();
            const int x = idx % w, y = idx / w;
            ++count;
            if (x < 2 || x >= w - 2 || y < 2 || y >= h - 2) ++frame;
            const float s = static_cast<float>(x + y);
            const float d = static_cast<float>(x - y);
            if (s < low_sum) { low_sum = s; q[0] = Pt{float(x), float(y)}; }
            if (d > high_diff) { high_diff = d; q[1] = Pt{float(x), float(y)}; }
            if (s > high_sum) { high_sum = s; q[2] = Pt{float(x), float(y)}; }
            if (d < low_diff) { low_diff = d; q[3] = Pt{float(x), float(y)}; }
            const auto push = [&](int next) {
                if (!mask[next] || seen[next]) return;
                seen[next] = 1;
                stack.push_back(next);
            };
            if (x > 0) push(idx - 1);
            if (x + 1 < w) push(idx + 1);
            if (y > 0) push(idx - w);
            if (y + 1 < h) push(idx + w);
        }
        if (count < n * .08f) continue;
        const float coverage = Area(q) / n;
        if (coverage < (prefer_card ? .13f : .17f) || coverage > .90f) continue;
        const float solidity = count / std::max(1.0f, coverage * n);
        if (solidity < .47f || solidity > 1.30f) continue;
        const float horizontal = (Distance(q[0], q[1]) + Distance(q[2], q[3])) * .5f;
        const float vertical = (Distance(q[0], q[3]) + Distance(q[1], q[2])) * .5f;
        if (horizontal < 15 || vertical < 15) continue;
        const float ratio = std::max(horizontal, vertical) / std::min(horizontal, vertical);
        if (ratio < 1.08f || ratio > 2.40f) continue;
        const bool card = ratio >= 1.44f && ratio <= 2.12f;
        if (prefer_card && !card) continue;
        const float cx = (q[0].x + q[1].x + q[2].x + q[3].x) / (4.0f * w);
        const float cy = (q[0].y + q[1].y + q[2].y + q[3].y) / (4.0f * h);
        if (std::abs(cx - .5f) > .30f || std::abs(cy - .5f) > .30f) continue;
        if (frame > count * (card ? .12f : .04f)) continue;
        const float margin = card ? .004f : .012f;
        bool near_frame = false;
        for (const Pt pt : q) {
            if (pt.x < w * margin || pt.x > w * (1.0f - margin) ||
                pt.y < h * margin || pt.y > h * (1.0f - margin)) {
                near_frame = true;
            }
        }
        if (near_frame) continue;
        const float edge = FourEdgeContrast(pixels, w, h, q);
        if (edge < .42f) continue;
        if (card && mode == 0 && coverage < .13f) continue;
        float score = std::min(1.0f, solidity) * .33f +
                      std::min(1.0f, coverage / .50f) * .21f +
                      edge * .27f +
                      (1.0f - std::abs(cx - .5f) - std::abs(cy - .5f)) * .17f +
                      ((card && mode == 0) ? .08f : 0.0f) -
                      ((mode == 3) ? .07f : 0.0f);
        if (score < .66f || score <= best->confidence) continue;
        best->confidence = score;
        best->mode = mode;
        for (int i = 0; i < 4; ++i) {
            best->corners[2 * i] = q[i].x / w;
            best->corners[2 * i + 1] = q[i].y / h;
        }
        found = true;
    }
    return found;
}

}  // namespace

bool DetectDocument(const uint32_t* argb, int width, int height,
                    bool prefer_card, Boundary* output) {
    if (!argb || !output || width < 64 || height < 64 ||
        width > 2048 || height > 2048 ||
        static_cast<int64_t>(width) * height > 1200000) return false;
    std::array<Color, 4> patches{};
    std::array<int, 4> colored{};
    const int pw = std::max(4, width * 8 / 100);
    const int ph = std::max(4, height * 8 / 100);
    const int total = std::max(1, pw * ph);
    for (int c = 0; c < 4; ++c) {
        const int sx = c % 2 ? width - pw : 0;
        const int sy = c / 2 ? height - ph : 0;
        for (int y = sy; y < sy + ph; ++y) {
            for (int x = sx; x < sx + pw; ++x) {
                const Color p = Unpack(argb[y * width + x]);
                patches[c].r += p.r;
                patches[c].g += p.g;
                patches[c].b += p.b;
                colored[c] += Colored(p);
            }
        }
        patches[c].r /= total; patches[c].g /= total; patches[c].b /= total;
    }
    auto median_four = [](std::array<int, 4> values) -> int {
        std::sort(values.begin(), values.end());
        return (values[1] + values[2]) / 2;
    };
    std::array<int, 4> red{}, green{}, blue{}, lights{};
    int neutral_corners = 0;
    for (int i = 0; i < 4; ++i) {
        red[i] = patches[i].r; green[i] = patches[i].g;
        blue[i] = patches[i].b; lights[i] = patches[i].light();
        if (colored[i] * 4 < total) ++neutral_corners;
    }
    const Color background{median_four(red), median_four(green),
                           median_four(blue)};
    const int background_light = median_four(lights);
    std::array<int, 4> variation{};
    for (int i = 0; i < 4; ++i) {
        variation[i] = (std::abs(patches[i].r - background.r) +
                        std::abs(patches[i].g - background.g) +
                        std::abs(patches[i].b - background.b)) / 3;
    }
    std::sort(variation.begin(), variation.end());
    const bool consistent_background = variation[2] <= 40;
    const int difference_threshold = std::max(22, 16 + variation[2] * 2);
    Boundary best;
    if (neutral_corners >= 3)
        AnalyzeMode(argb, width, height, 0, background, background_light,
                    difference_threshold, prefer_card, &best);
    if (background_light < 181)
        AnalyzeMode(argb, width, height, 1, background, background_light,
                    difference_threshold, prefer_card, &best);
    if (background_light > 155)
        AnalyzeMode(argb, width, height, 2, background, background_light,
                    difference_threshold, prefer_card, &best);
    if (consistent_background)
        AnalyzeMode(argb, width, height, 3, background, background_light,
                    difference_threshold, prefer_card, &best);
    if (background.chroma() > 40)
        AnalyzeMode(argb, width, height, 4, background, background_light,
                    difference_threshold, prefer_card, &best);
    if (best.mode < 0) return false;
    *output = best;
    return true;
}

}  // namespace ds
