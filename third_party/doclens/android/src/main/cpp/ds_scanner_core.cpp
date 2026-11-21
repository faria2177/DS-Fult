#include "ds_scanner_core.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <vector>

namespace ds {
namespace {

inline float Luma(int r, int g, int b) {
    return 0.299f * static_cast<float>(r) + 0.587f * static_cast<float>(g) +
           0.114f * static_cast<float>(b);
}

inline int Red(uint32_t p) { return static_cast<int>((p >> 16) & 255U); }
inline int Green(uint32_t p) { return static_cast<int>((p >> 8) & 255U); }
inline int Blue(uint32_t p) { return static_cast<int>(p & 255U); }

inline uint32_t Byte(float v) {
    return static_cast<uint32_t>(std::clamp(std::lround(v), 0L, 255L));
}

inline uint32_t Pack(uint32_t r, uint32_t g, uint32_t b) {
    return 0xff000000U | (r << 16) | (g << 8) | b;
}

bool ValidSize(int width, int height, int64_t max_pixels) {
    return width >= 8 && height >= 8 &&
           static_cast<int64_t>(width) * height <= max_pixels;
}

// ---------------------------------------------------------------- enhance

std::vector<float> MaxFilter(const std::vector<float>& g, int gw, int gh,
                             int radius) {
    std::vector<float> out(g.size());
    for (int y = 0; y < gh; ++y) {
        for (int x = 0; x < gw; ++x) {
            float m = 0.0f;
            for (int dy = -radius; dy <= radius; ++dy) {
                const int yy = std::clamp(y + dy, 0, gh - 1);
                for (int dx = -radius; dx <= radius; ++dx) {
                    const int xx = std::clamp(x + dx, 0, gw - 1);
                    m = std::max(m, g[static_cast<size_t>(yy) * gw + xx]);
                }
            }
            out[static_cast<size_t>(y) * gw + x] = m;
        }
    }
    return out;
}

std::vector<float> BoxBlur(const std::vector<float>& g, int gw, int gh,
                           int radius) {
    std::vector<float> out(g.size());
    for (int y = 0; y < gh; ++y) {
        for (int x = 0; x < gw; ++x) {
            float sum = 0.0f;
            int count = 0;
            for (int dy = -radius; dy <= radius; ++dy) {
                const int yy = y + dy;
                if (yy < 0 || yy >= gh) continue;
                for (int dx = -radius; dx <= radius; ++dx) {
                    const int xx = x + dx;
                    if (xx < 0 || xx >= gw) continue;
                    sum += g[static_cast<size_t>(yy) * gw + xx];
                    ++count;
                }
            }
            out[static_cast<size_t>(y) * gw + x] = sum / static_cast<float>(count);
        }
    }
    return out;
}

// ------------------------------------------------------------ paper region

struct Point {
    double x;
    double y;
};

double Cross(const Point& o, const Point& a, const Point& b) {
    return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
}

double Area(const std::vector<Point>& p) {
    double s = 0.0;
    for (size_t i = 0; i < p.size(); ++i) {
        const Point& a = p[i];
        const Point& b = p[(i + 1) % p.size()];
        s += a.x * b.y - b.x * a.y;
    }
    return std::abs(s) / 2.0;
}

std::vector<Point> ConvexHull(std::vector<Point> pts) {
    std::sort(pts.begin(), pts.end(), [](const Point& a, const Point& b) {
        return a.x != b.x ? a.x < b.x : a.y < b.y;
    });
    std::vector<Point> lower;
    for (const Point& p : pts) {
        while (lower.size() >= 2 &&
               Cross(lower[lower.size() - 2], lower.back(), p) <= 0) {
            lower.pop_back();
        }
        lower.push_back(p);
    }
    std::vector<Point> upper;
    for (auto it = pts.rbegin(); it != pts.rend(); ++it) {
        while (upper.size() >= 2 &&
               Cross(upper[upper.size() - 2], upper.back(), *it) <= 0) {
            upper.pop_back();
        }
        upper.push_back(*it);
    }
    if (lower.empty() || upper.empty()) return {};
    lower.pop_back();
    upper.pop_back();
    lower.insert(lower.end(), upper.begin(), upper.end());
    return lower;
}

// Visvalingam: drop the vertex whose removal loses the least area.
std::vector<Point> ReduceToFour(std::vector<Point> pts) {
    while (pts.size() > 4) {
        size_t best_index = 0;
        double best_loss = std::numeric_limits<double>::infinity();
        const size_t n = pts.size();
        for (size_t i = 0; i < n; ++i) {
            const Point& a = pts[(i + n - 1) % n];
            const Point& b = pts[i];
            const Point& c = pts[(i + 1) % n];
            const double loss =
                std::abs((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)) / 2;
            if (loss < best_loss) {
                best_loss = loss;
                best_index = i;
            }
        }
        pts.erase(pts.begin() + static_cast<std::ptrdiff_t>(best_index));
    }
    return pts;
}

int Otsu(const std::vector<float>& values) {
    std::array<int64_t, 256> hist{};
    for (float v : values) {
        ++hist[static_cast<size_t>(std::clamp(std::lround(v), 0L, 255L))];
    }
    const int64_t total = static_cast<int64_t>(values.size());
    double sum = 0.0;
    for (int i = 0; i < 256; ++i) sum += static_cast<double>(i) * static_cast<double>(hist[static_cast<size_t>(i)]);
    double sum_b = 0.0;
    int64_t w_b = 0;
    double best = 0.0;
    int threshold = 0;
    for (int t = 0; t < 256; ++t) {
        const int64_t count = hist[static_cast<size_t>(t)];
        w_b += count;
        if (w_b == 0) continue;
        const int64_t w_f = total - w_b;
        if (w_f == 0) break;
        sum_b += static_cast<double>(t) * static_cast<double>(count);
        const double m_b = sum_b / static_cast<double>(w_b);
        const double m_f = (sum - sum_b) / static_cast<double>(w_f);
        const double between = static_cast<double>(w_b) *
                                static_cast<double>(w_f) * (m_b - m_f) * (m_b - m_f);
        if (between > best) {
            best = between;
            threshold = t;
        }
    }
    return threshold;
}

// Every "off" pixel that cannot reach the border becomes "on" (text holes).
void FillHoles(std::vector<uint8_t>& m, int w, int h) {
    std::vector<uint8_t> outside(m.size());
    std::vector<int> stack;
    auto seed = [&](int i) {
        if (m[static_cast<size_t>(i)] == 0 && outside[static_cast<size_t>(i)] == 0) {
            outside[static_cast<size_t>(i)] = 1;
            stack.push_back(i);
        }
    };
    for (int x = 0; x < w; ++x) {
        seed(x);
        seed((h - 1) * w + x);
    }
    for (int y = 0; y < h; ++y) {
        seed(y * w);
        seed(y * w + w - 1);
    }
    while (!stack.empty()) {
        const int i = stack.back();
        stack.pop_back();
        const int x = i % w;
        if (x > 0) seed(i - 1);
        if (x < w - 1) seed(i + 1);
        if (i >= w) seed(i - w);
        if (i < (h - 1) * w) seed(i + w);
    }
    for (size_t i = 0; i < m.size(); ++i) {
        if (outside[i] == 0) m[i] = 1;
    }
}

// Square min (keep_if_all) or max filter, separable, window clipped at the
// border (so the border counts as "on" for the min filter).
std::vector<uint8_t> SquareFilter(const std::vector<uint8_t>& m, int w, int h,
                                  int r, bool keep_if_all) {
    auto pass = [&](const std::vector<uint8_t>& src, bool horizontal) {
        std::vector<uint8_t> out(src.size());
        const int lines = horizontal ? h : w;
        const int length = horizontal ? w : h;
        for (int line = 0; line < lines; ++line) {
            auto index = [&](int k) {
                return static_cast<size_t>(horizontal ? line * w + k : k * w + line);
            };
            int on = 0;
            for (int k = 0; k <= std::min(r, length - 1); ++k) on += src[index(k)];
            for (int k = 0; k < length; ++k) {
                const int lo = std::max(0, k - r);
                const int hi = std::min(length - 1, k + r);
                const int size = hi - lo + 1;
                out[index(k)] = keep_if_all ? (on == size ? 1 : 0) : (on > 0 ? 1 : 0);
                if (k + r + 1 < length) on += src[index(k + r + 1)];
                if (k - r >= 0) on -= src[index(k - r)];
            }
        }
        return out;
    };
    return pass(pass(m, true), false);
}

// Largest 4-connected component; returns its pixel count (0 when none).
int LargestComponent(const std::vector<uint8_t>& on, int w, int h,
                     std::vector<uint8_t>* mask) {
    std::vector<int> label(on.size());
    std::vector<int> stack;
    int next = 0;
    int best_label = 0;
    int best_count = 0;
    for (int start = 0; start < w * h; ++start) {
        if (on[static_cast<size_t>(start)] == 0 || label[static_cast<size_t>(start)] != 0) continue;
        ++next;
        int count = 0;
        stack.push_back(start);
        label[static_cast<size_t>(start)] = next;
        while (!stack.empty()) {
            const int i = stack.back();
            stack.pop_back();
            ++count;
            const int x = i % w;
            const int y = i / w;
            auto visit = [&](int j) {
                if (on[static_cast<size_t>(j)] == 1 && label[static_cast<size_t>(j)] == 0) {
                    label[static_cast<size_t>(j)] = next;
                    stack.push_back(j);
                }
            };
            if (x > 0) visit(i - 1);
            if (x < w - 1) visit(i + 1);
            if (y > 0) visit(i - w);
            if (y < h - 1) visit(i + w);
        }
        if (count > best_count) {
            best_count = count;
            best_label = next;
        }
    }
    mask->assign(on.size(), 0);
    if (best_count == 0) return 0;
    for (size_t i = 0; i < on.size(); ++i) {
        if (label[i] == best_label) (*mask)[i] = 1;
    }
    return best_count;
}

}  // namespace

bool IsNeutralDocument(const uint32_t* argb, int width, int height) {
    if (!argb || !ValidSize(width, height, 40000000)) return false;
    int64_t neutral = 0;
    int64_t bright = 0;
    int64_t total = 0;
    const int step = std::max(1, std::min(width, height) / 160);
    for (int y = 0; y < height; y += step) {
        for (int x = 0; x < width; x += step) {
            const uint32_t p = argb[static_cast<size_t>(y) * width + x];
            const int r = Red(p), g = Green(p), b = Blue(p);
            const int tint = std::max({r, g, b}) - std::min({r, g, b});
            if (tint < 42) ++neutral;
            if (Luma(r, g, b) > 120.0f) ++bright;
            ++total;
        }
    }
    return total > 0 &&
           static_cast<double>(neutral) / static_cast<double>(total) >= 0.88 &&
           static_cast<double>(bright) / static_cast<double>(total) >= 0.55;
}

bool MagicEnhance(uint32_t* argb, int width, int height) {
    if (!argb || !ValidSize(width, height, 40000000)) return false;
    const int w = width;
    const int h = height;
    const size_t n = static_cast<size_t>(w) * h;
    std::vector<float> lum(n);
    for (size_t i = 0; i < n; ++i) {
        lum[i] = Luma(Red(argb[i]), Green(argb[i]), Blue(argb[i]));
    }

    // 1. Paper map: per-block 95th percentile on a coarse grid.
    const int block = std::max(4, std::max(w, h) / 96);
    const int gw = (w + block - 1) / block;
    const int gh = (h + block - 1) / block;
    std::vector<float> grid(static_cast<size_t>(gw) * gh);
    for (int gy = 0; gy < gh; ++gy) {
        for (int gx = 0; gx < gw; ++gx) {
            std::array<int, 64> hist{};
            int count = 0;
            for (int y = gy * block; y < std::min(h, (gy + 1) * block); y += 2) {
                for (int x = gx * block; x < std::min(w, (gx + 1) * block); x += 2) {
                    const int bin = std::clamp(
                        static_cast<int>(std::floor(lum[static_cast<size_t>(y) * w + x] / 4.0f)), 0, 63);
                    ++hist[static_cast<size_t>(bin)];
                    ++count;
                }
            }
            int acc = 0;
            int value = 63;
            for (int i = 63; i >= 0; --i) {
                acc += hist[static_cast<size_t>(i)];
                if (static_cast<double>(acc) >= count * 0.05) {
                    value = i;
                    break;
                }
            }
            grid[static_cast<size_t>(gy) * gw + gx] = static_cast<float>(value * 4 + 2);
        }
    }
    // Large dark areas (thick tables, filled boxes) must not darken the map.
    grid = MaxFilter(grid, gw, gh, 2);
    grid = BoxBlur(BoxBlur(grid, gw, gh, 2), gw, gh, 2);

    auto paper_at = [&](int x, int y) {
        const float fx = std::clamp((static_cast<float>(x) + 0.5f) / static_cast<float>(block) - 0.5f,
                                    0.0f, static_cast<float>(gw - 1));
        const float fy = std::clamp((static_cast<float>(y) + 0.5f) / static_cast<float>(block) - 0.5f,
                                    0.0f, static_cast<float>(gh - 1));
        const int x0 = static_cast<int>(std::floor(fx));
        const int y0 = static_cast<int>(std::floor(fy));
        const int x1 = std::min(gw - 1, x0 + 1);
        const int y1 = std::min(gh - 1, y0 + 1);
        const float tx = fx - static_cast<float>(x0);
        const float ty = fy - static_cast<float>(y0);
        const float top = grid[static_cast<size_t>(y0) * gw + x0] * (1 - tx) +
                          grid[static_cast<size_t>(y0) * gw + x1] * tx;
        const float bottom = grid[static_cast<size_t>(y1) * gw + x0] * (1 - tx) +
                             grid[static_cast<size_t>(y1) * gw + x1] * tx;
        return std::max(60.0f, top * (1 - ty) + bottom * ty);
    };

    // 2 + 3. Normalise and tone-map.
    std::vector<float> toned(n);
    for (int y = 0; y < h; ++y) {
        for (int x = 0; x < w; ++x) {
            const size_t i = static_cast<size_t>(y) * w + x;
            const float v = std::clamp(lum[i] / paper_at(x, y), 0.0f, 1.2f);
            float out;
            if (v >= 0.90f) {
                out = 255.0f;
            } else if (v <= 0.45f) {
                out = 18.0f + v / 0.45f * 30.0f;
            } else {
                const float t = (v - 0.45f) / 0.45f;
                out = 48.0f + (255.0f - 48.0f) * (t * t * (3.0f - 2.0f * t));
            }
            toned[i] = out;
        }
    }

    // 4. 3×3 unsharp mask; coloured ink keeps its colour.
    for (int y = 0; y < h; ++y) {
        for (int x = 0; x < w; ++x) {
            const size_t i = static_cast<size_t>(y) * w + x;
            float v = toned[i];
            if (v < 250.0f && x > 0 && y > 0 && x < w - 1 && y < h - 1) {
                const float blur = (toned[i - 1] + toned[i + 1] + toned[i - static_cast<size_t>(w)] +
                                    toned[i + static_cast<size_t>(w)] + v * 4.0f) / 8.0f;
                v = v + (v - blur) * 0.6f;
            }
            const uint32_t p = argb[i];
            const int r = Red(p), g = Green(p), b = Blue(p);
            const int tint = std::max({r, g, b}) - std::min({r, g, b});
            if (tint > 45 && v < 250.0f) {
                const float k = v / std::max(1.0f, lum[i]);
                argb[i] = Pack(Byte(static_cast<float>(r) * k),
                               Byte(static_cast<float>(g) * k),
                               Byte(static_cast<float>(b) * k));
            } else {
                const uint32_t c = Byte(v);
                argb[i] = Pack(c, c, c);
            }
        }
    }
    return true;
}

bool FindPaperRegion(const uint32_t* argb, int width, int height,
                     PaperRegion* output) {
    if (!argb || !output || width < 32 || height < 32 || width > 2048 ||
        height > 2048) {
        return false;
    }
    *output = PaperRegion{};
    const int w = width;
    const int h = height;
    const size_t n = static_cast<size_t>(w) * h;
    std::vector<float> luma(n);
    std::vector<float> chroma(n);
    for (size_t i = 0; i < n; ++i) {
        const int r = Red(argb[i]), g = Green(argb[i]), b = Blue(argb[i]);
        luma[i] = Luma(r, g, b);
        chroma[i] = static_cast<float>(std::max({r, g, b}) - std::min({r, g, b}));
    }
    const int threshold = Otsu(luma);
    if (threshold < 70) return true;
    std::vector<uint8_t> paper(n);
    for (size_t i = 0; i < n; ++i) {
        paper[i] = luma[i] >= static_cast<float>(threshold) && chroma[i] < 58.0f ? 1 : 0;
    }
    // Text and table lines are holes; a light rail or cable touching the
    // sheet is cut off by an opening before choosing the largest part.
    // Close thin dark lines first: table rules that run off the frame are
    // not enclosed holes, and the opening would eat the strips between them.
    const std::vector<uint8_t> closed =
        SquareFilter(SquareFilter(paper, w, h, 2, false), w, h, 2, true);
    for (size_t i = 0; i < n; ++i) paper[i] = static_cast<uint8_t>(paper[i] | closed[i]);
    FillHoles(paper, w, h);
    const int radius = std::max(3, static_cast<int>(std::lround(std::max(w, h) * 0.016)));
    const std::vector<uint8_t> eroded = SquareFilter(paper, w, h, radius, true);
    std::vector<uint8_t> component;
    if (LargestComponent(eroded, w, h, &component) == 0) return true;
    const std::vector<uint8_t> grown = SquareFilter(component, w, h, radius, false);
    std::vector<uint8_t> mask(n);
    int64_t count = 0;
    for (size_t i = 0; i < n; ++i) {
        if (grown[i] == 1 && paper[i] == 1) {
            mask[i] = 1;
            ++count;
        }
    }
    const double fraction = static_cast<double>(count) / static_cast<double>(n);
    output->paper_fraction = static_cast<float>(fraction);
    if (fraction < 0.25) return true;

    double in_sum = 0.0;
    double out_sum = 0.0;
    for (size_t i = 0; i < n; ++i) {
        if (mask[i] == 1) {
            in_sum += luma[i];
        } else {
            out_sum += luma[i];
        }
    }
    const int64_t outside = static_cast<int64_t>(n) - count;
    if (static_cast<double>(outside) < static_cast<double>(n) * 0.04) return true;
    if (in_sum / static_cast<double>(count) -
            out_sum / static_cast<double>(outside) < 38.0) {
        return true;
    }

    std::vector<Point> points;
    points.reserve(static_cast<size_t>(h) * 4);
    for (int y = 0; y < h; ++y) {
        int min_x = -1;
        int max_x = -1;
        for (int x = 0; x < w; ++x) {
            if (mask[static_cast<size_t>(y) * w + x] == 1) {
                if (min_x < 0) min_x = x;
                max_x = x;
            }
        }
        if (min_x >= 0) {
            points.push_back({static_cast<double>(min_x), static_cast<double>(y)});
            points.push_back({max_x + 1.0, static_cast<double>(y)});
            points.push_back({static_cast<double>(min_x), y + 1.0});
            points.push_back({max_x + 1.0, y + 1.0});
        }
    }
    const std::vector<Point> hull = ConvexHull(points);
    if (hull.size() < 4) return true;
    std::vector<Point> corners = ReduceToFour(hull);
    const double quad_area = Area(corners);
    if (quad_area <= 0 || quad_area < Area(hull) * 0.93) return true;
    if (static_cast<double>(count) / quad_area < 0.82) return true;

    for (Point& c : corners) {
        c.x = std::clamp(c.x / w, 0.0, 1.0);
        c.y = std::clamp(c.y / h, 0.0, 1.0);
    }
    // Whole photo is paper: nothing to crop.
    constexpr double kTol = 0.025;
    int at_frame_corner = 0;
    for (const Point& c : corners) {
        if ((c.x < kTol || c.x > 1 - kTol) && (c.y < kTol || c.y > 1 - kTol)) {
            ++at_frame_corner;
        }
    }
    if (at_frame_corner == 4) return true;

    // Order TL, TR, BR, BL by x+y and x−y.
    int tl = 0, br = 0, tr = 0, bl = 0;
    for (int i = 1; i < 4; ++i) {
        const Point& c = corners[static_cast<size_t>(i)];
        auto at = [&](int k) { return corners[static_cast<size_t>(k)]; };
        if (c.x + c.y < at(tl).x + at(tl).y) tl = i;
        if (c.x + c.y > at(br).x + at(br).y) br = i;
        if (c.x - c.y > at(tr).x - at(tr).y) tr = i;
        if (c.x - c.y < at(bl).x - at(bl).y) bl = i;
    }
    if (tl == br || tl == tr || tl == bl || br == tr || br == bl || tr == bl) {
        return true;
    }
    const int order[4] = {tl, tr, br, bl};
    for (int k = 0; k < 4; ++k) {
        const Point& c = corners[static_cast<size_t>(order[k])];
        output->corners[static_cast<size_t>(k * 2)] = static_cast<float>(c.x);
        output->corners[static_cast<size_t>(k * 2 + 1)] = static_cast<float>(c.y);
    }
    output->found = true;
    return true;
}

}  // namespace ds
