#include "ds_dewarp.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace ds {
namespace {

constexpr double kMargin = 0.08;    // analysed band outside the quad
constexpr double kSearch = 0.075;   // how far a side may bow
constexpr int kSamples = 40;        // points traced along each side
constexpr int kAnalysisLong = 640;  // analysis resolution of the page

// Unit square → quad (TL, TR, BR, BL), projective.
struct Homography {
    double a, b, c, d, e, f, g, h;

    static Homography FromQuad(const std::array<double, 8>& q) {
        const double x0 = q[0], y0 = q[1], x1 = q[2], y1 = q[3];
        const double x2 = q[4], y2 = q[5], x3 = q[6], y3 = q[7];
        const double dx1 = x1 - x2, dx2 = x3 - x2, dx3 = x0 - x1 + x2 - x3;
        const double dy1 = y1 - y2, dy2 = y3 - y2, dy3 = y0 - y1 + y2 - y3;
        Homography m{};
        if (std::abs(dx3) < 1e-9 && std::abs(dy3) < 1e-9) {
            m = {x1 - x0, x3 - x0, x0, y1 - y0, y3 - y0, y0, 0, 0};
        } else {
            const double den = dx1 * dy2 - dx2 * dy1;
            const double g = (dx3 * dy2 - dx2 * dy3) / den;
            const double h = (dx1 * dy3 - dx3 * dy1) / den;
            m = {x1 - x0 + g * x1, x3 - x0 + h * x3, x0,
                 y1 - y0 + g * y1, y3 - y0 + h * y3, y0, g, h};
        }
        return m;
    }

    void Map(double u, double v, double* x, double* y) const {
        const double w = g * u + h * v + 1.0;
        *x = (a * u + b * v + c) / w;
        *y = (d * u + e * v + f) / w;
    }
};

inline float LumaOf(uint32_t p) {
    return 0.299f * static_cast<float>((p >> 16) & 255U) +
           0.587f * static_cast<float>((p >> 8) & 255U) +
           0.114f * static_cast<float>(p & 255U);
}

// Bilinear luma; negative when outside the image.
float SampleLuma(const uint32_t* src, int w, int h, double x, double y) {
    if (x < 0 || y < 0 || x > w - 1 || y > h - 1) return -1.0f;
    const int x0 = static_cast<int>(x), y0 = static_cast<int>(y);
    const int x1 = std::min(w - 1, x0 + 1), y1 = std::min(h - 1, y0 + 1);
    const float tx = static_cast<float>(x - x0), ty = static_cast<float>(y - y0);
    const float a = LumaOf(src[static_cast<size_t>(y0) * w + x0]);
    const float b = LumaOf(src[static_cast<size_t>(y0) * w + x1]);
    const float c = LumaOf(src[static_cast<size_t>(y1) * w + x0]);
    const float d = LumaOf(src[static_cast<size_t>(y1) * w + x1]);
    return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty;
}

uint32_t SampleArgb(const uint32_t* src, int w, int h, double x, double y) {
    if (x < -0.5 || y < -0.5 || x > w - 0.5 || y > h - 0.5) return 0xffffffffU;
    x = std::clamp(x, 0.0, static_cast<double>(w - 1));
    y = std::clamp(y, 0.0, static_cast<double>(h - 1));
    const int x0 = static_cast<int>(x), y0 = static_cast<int>(y);
    const int x1 = std::min(w - 1, x0 + 1), y1 = std::min(h - 1, y0 + 1);
    const double tx = x - x0, ty = y - y0;
    const uint32_t p00 = src[static_cast<size_t>(y0) * w + x0];
    const uint32_t p10 = src[static_cast<size_t>(y0) * w + x1];
    const uint32_t p01 = src[static_cast<size_t>(y1) * w + x0];
    const uint32_t p11 = src[static_cast<size_t>(y1) * w + x1];
    uint32_t out = 0xff000000U;
    for (int shift = 0; shift <= 16; shift += 8) {
        const double c00 = (p00 >> shift) & 255U, c10 = (p10 >> shift) & 255U;
        const double c01 = (p01 >> shift) & 255U, c11 = (p11 >> shift) & 255U;
        const double v = (c00 * (1 - tx) + c10 * tx) * (1 - ty) +
                         (c01 * (1 - tx) + c11 * tx) * ty;
        out |= static_cast<uint32_t>(std::clamp(std::lround(v), 0L, 255L)) << shift;
    }
    return out;
}

// Rectified luma of the page plus margin. Index (i, j) ↔ unit coords
// u = (i + .5) / pw − m, v = (j + .5) / ph − m.
struct Analysis {
    int pw = 0, ph = 0, aw = 0, ah = 0;
    std::vector<float> luma;

    float At(int i, int j) const {
        if (i < 0 || j < 0 || i >= aw || j >= ah) return -1.0f;
        return luma[static_cast<size_t>(j) * aw + i];
    }
};

Analysis Rectify(const uint32_t* src, int w, int h, const Homography& hm,
                 int out_w, int out_h) {
    Analysis a;
    const double aspect = static_cast<double>(out_w) / out_h;
    a.pw = aspect >= 1 ? kAnalysisLong : std::max(32, static_cast<int>(kAnalysisLong * aspect));
    a.ph = aspect >= 1 ? std::max(32, static_cast<int>(kAnalysisLong / aspect)) : kAnalysisLong;
    a.aw = static_cast<int>(a.pw * (1 + 2 * kMargin));
    a.ah = static_cast<int>(a.ph * (1 + 2 * kMargin));
    std::vector<float> raw(static_cast<size_t>(a.aw) * a.ah);
    for (int j = 0; j < a.ah; ++j) {
        const double v = (j + 0.5) / a.ph - kMargin;
        for (int i = 0; i < a.aw; ++i) {
            const double u = (i + 0.5) / a.pw - kMargin;
            double x, y;
            hm.Map(u, v, &x, &y);
            raw[static_cast<size_t>(j) * a.aw + i] = SampleLuma(src, w, h, x, y);
        }
    }
    // 3×3 mean (invalid stays invalid) to calm paper texture and noise.
    a.luma.assign(raw.size(), -1.0f);
    for (int j = 1; j < a.ah - 1; ++j) {
        for (int i = 1; i < a.aw - 1; ++i) {
            float sum = 0;
            bool ok = true;
            for (int dj = -1; dj <= 1 && ok; ++dj) {
                for (int di = -1; di <= 1; ++di) {
                    const float v = raw[static_cast<size_t>(j + dj) * a.aw + i + di];
                    if (v < 0) { ok = false; break; }
                    sum += v;
                }
            }
            if (ok) a.luma[static_cast<size_t>(j) * a.aw + i] = sum / 9.0f;
        }
    }
    return a;
}

// Mean luma of a band; negative if any pixel is missing.
float Band(const Analysis& a, int i0, int i1, int j0, int j1) {
    float sum = 0;
    int n = 0;
    for (int j = j0; j <= j1; ++j) {
        for (int i = i0; i <= i1; ++i) {
            const float v = a.At(i, j);
            if (v < 0) return -1.0f;
            sum += v;
            ++n;
        }
    }
    return n ? sum / static_cast<float>(n) : -1.0f;
}

// One side. side: 0 top, 1 right, 2 bottom, 3 left. Returns the offset of
// the paper edge from its nominal position (unit coords) at each sample, or
// NaN where no clear background→paper step exists.
std::vector<double> TraceSide(const Analysis& a, int side) {
    std::vector<double> out(kSamples, std::nan(""));
    const bool horizontal = side == 0 || side == 2;
    const int along = horizontal ? a.pw : a.ph;   // pixels along the side
    const int across = horizontal ? a.ph : a.pw;  // pixels across it
    const int band = std::max(3, across / 110);
    const int half = std::max(3, along / 150);
    const int reach = static_cast<int>(kSearch * across);
    const int nominal = static_cast<int>(kMargin * across) +
                        (side == 1 || side == 2 ? across : 0);
    // +1: moving the index increases towards the inside of the page.
    const int inward = side == 0 || side == 3 ? 1 : -1;
    for (int k = 0; k < kSamples; ++k) {
        const double s = 0.06 + 0.88 * k / (kSamples - 1);
        const int c = static_cast<int>(kMargin * along + s * along);
        std::vector<float> score(static_cast<size_t>(2 * reach + 1), -1e9f);
        float best = -1e9f;
        for (int r = -reach; r <= reach; ++r) {
            const int p = nominal + r;
            int in0 = p, in1 = p + inward * (band - 1);
            int out0 = p - inward, out1 = p - inward * band;
            if (in0 > in1) std::swap(in0, in1);
            if (out0 > out1) std::swap(out0, out1);
            float inside, outside;
            if (horizontal) {
                inside = Band(a, c - half, c + half, in0, in1);
                outside = Band(a, c - half, c + half, out0, out1);
            } else {
                inside = Band(a, in0, in1, c - half, c + half);
                outside = Band(a, out0, out1, c - half, c + half);
            }
            if (inside < 0 || outside < 0) continue;
            const float sc = inside - outside;
            score[static_cast<size_t>(r + reach)] = sc;
            best = std::max(best, sc);
        }
        if (best < 24.0f) continue;
        // The paper edge is the outermost strong step; text lines are inside.
        for (int idx = 0; idx <= 2 * reach; ++idx) {
            const int r = inward > 0 ? idx - reach : reach - idx;
            const float sc = score[static_cast<size_t>(r + reach)];
            if (sc >= std::max(24.0f, 0.6f * best)) {
                // Edge between p−inward and p: half a pixel outwards.
                out[static_cast<size_t>(k)] = (r - 0.5 * inward) / across;
                break;
            }
        }
    }
    return out;
}

// Least-squares polynomial (degree 3) through (x, y). Returns false when
// the system is singular.
bool FitCubic(const std::vector<double>& x, const std::vector<double>& y,
              std::array<double, 4>* coef) {
    double m[4][5] = {};
    for (size_t n = 0; n < x.size(); ++n) {
        double p[4] = {1, x[n], x[n] * x[n], x[n] * x[n] * x[n]};
        for (int r = 0; r < 4; ++r) {
            for (int c = 0; c < 4; ++c) m[r][c] += p[r] * p[c];
            m[r][4] += p[r] * y[n];
        }
    }
    for (int col = 0; col < 4; ++col) {
        int pivot = col;
        for (int r = col + 1; r < 4; ++r) {
            if (std::abs(m[r][col]) > std::abs(m[pivot][col])) pivot = r;
        }
        if (std::abs(m[pivot][col]) < 1e-12) return false;
        for (int c = 0; c < 5; ++c) std::swap(m[col][c], m[pivot][c]);
        for (int r = 0; r < 4; ++r) {
            if (r == col) continue;
            const double factor = m[r][col] / m[col][col];
            for (int c = col; c < 5; ++c) m[r][c] -= factor * m[col][c];
        }
    }
    for (int r = 0; r < 4; ++r) (*coef)[static_cast<size_t>(r)] = m[r][4] / m[r][r];
    return true;
}

double Eval(const std::array<double, 4>& c, double x) {
    return c[0] + x * (c[1] + x * (c[2] + x * c[3]));
}

// A traced side as a curve pinned to the corners: f(0) = f(1) = 0.
struct SideCurve {
    bool valid = false;
    std::array<double, 4> coef{};
    double start = 0, end = 0;

    double At(double s) const {
        if (!valid) return 0.0;
        return Eval(coef, s) - ((1 - s) * start + s * end);
    }
};

SideCurve FitSide(const std::vector<double>& offsets) {
    SideCurve curve;
    std::vector<double> xs, ys;
    for (int k = 0; k < kSamples; ++k) {
        const double v = offsets[static_cast<size_t>(k)];
        if (std::isnan(v)) continue;
        xs.push_back(0.06 + 0.88 * k / (kSamples - 1));
        ys.push_back(v);
    }
    if (static_cast<int>(xs.size()) * 10 < kSamples * 7) return curve;
    std::array<double, 4> coef{};
    for (int iter = 0; iter < 3; ++iter) {
        if (!FitCubic(xs, ys, &coef)) return curve;
        std::vector<double> res(xs.size());
        for (size_t n = 0; n < xs.size(); ++n) res[n] = std::abs(ys[n] - Eval(coef, xs[n]));
        std::vector<double> sorted = res;
        std::nth_element(sorted.begin(), sorted.begin() + static_cast<std::ptrdiff_t>(sorted.size() / 2), sorted.end());
        const double limit = std::max(0.004, 3.0 * 1.4826 * sorted[sorted.size() / 2]);
        std::vector<double> nx, ny;
        for (size_t n = 0; n < xs.size(); ++n) {
            if (res[n] <= limit) {
                nx.push_back(xs[n]);
                ny.push_back(ys[n]);
            }
        }
        if (nx.size() == xs.size()) break;
        xs.swap(nx);
        ys.swap(ny);
        if (static_cast<int>(xs.size()) * 10 < kSamples * 6) return curve;
    }
    if (!FitCubic(xs, ys, &coef)) return curve;
    double sq = 0;
    for (size_t n = 0; n < xs.size(); ++n) {
        const double r = ys[n] - Eval(coef, xs[n]);
        sq += r * r;
    }
    if (std::sqrt(sq / static_cast<double>(xs.size())) > 0.005) return curve;
    curve.coef = coef;
    curve.start = Eval(coef, 0.0);
    curve.end = Eval(coef, 1.0);
    // The detected corners must sit on the traced side.
    if (std::abs(curve.start) > 0.03 || std::abs(curve.end) > 0.03) return curve;
    curve.valid = true;
    return curve;
}

}  // namespace

bool Dewarp(const uint32_t* src, int width, int height,
            const std::array<double, 8>& quad, int out_width, int out_height,
            std::vector<uint32_t>* out, DewarpInfo* info) {
    if (!src || !out || width < 32 || height < 32 || out_width < 32 ||
        out_height < 32 || out_width > 8000 || out_height > 8000) {
        return false;
    }
    for (double v : quad) {
        if (!std::isfinite(v)) return false;
    }
    const Homography hm = Homography::FromQuad(quad);
    const Analysis a = Rectify(src, width, height, hm, out_width, out_height);

    SideCurve sides[4];
    double bow = 0.0;
    for (int side = 0; side < 4; ++side) {
        sides[side] = FitSide(TraceSide(a, side));
        if (info) info->traced[static_cast<size_t>(side)] = sides[side].valid;
        if (!sides[side].valid) continue;
        for (int k = 0; k <= 50; ++k) bow = std::max(bow, std::abs(sides[side].At(k / 50.0)));
    }
    if (info) info->max_bow = static_cast<float>(bow);
    // Straight sides: the perspective crop is already right. A bow larger
    // than the search band means something else was traced.
    if (bow < 0.008 || bow > 0.07) return false;

    std::vector<double> top(static_cast<size_t>(out_width)), bottom(static_cast<size_t>(out_width));
    std::vector<double> left(static_cast<size_t>(out_height)), right(static_cast<size_t>(out_height));
    for (int x = 0; x < out_width; ++x) {
        const double u = (x + 0.5) / out_width;
        top[static_cast<size_t>(x)] = sides[0].At(u);
        bottom[static_cast<size_t>(x)] = sides[2].At(u);
    }
    for (int y = 0; y < out_height; ++y) {
        const double v = (y + 0.5) / out_height;
        right[static_cast<size_t>(y)] = sides[1].At(v);
        left[static_cast<size_t>(y)] = sides[3].At(v);
    }
    out->assign(static_cast<size_t>(out_width) * out_height, 0xffffffffU);
    for (int y = 0; y < out_height; ++y) {
        const double v = (y + 0.5) / out_height;
        for (int x = 0; x < out_width; ++x) {
            const double u = (x + 0.5) / out_width;
            // Coons patch bounded by the four traced sides.
            const double pu = u + (1 - u) * left[static_cast<size_t>(y)] + u * right[static_cast<size_t>(y)];
            const double pv = v + (1 - v) * top[static_cast<size_t>(x)] + v * bottom[static_cast<size_t>(x)];
            double sx, sy;
            hm.Map(pu, pv, &sx, &sy);
            (*out)[static_cast<size_t>(y) * out_width + x] = SampleArgb(src, width, height, sx, sy);
        }
    }
    return true;
}

}  // namespace ds
