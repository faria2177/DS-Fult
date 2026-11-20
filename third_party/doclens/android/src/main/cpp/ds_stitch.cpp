#include "ds_stitch.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace ds {
namespace {

constexpr int kCoarse = 4;         // coarse search at 1/4 size
constexpr int kFine = 2;           // refinement at 1/2 size
constexpr double kMinCoarse = 0.60;
constexpr double kMinScore = 0.82;
constexpr double kMinMargin = 0.05;
constexpr double kMinStd = 6.0;

struct Gray {
    int w = 0, h = 0;
    std::vector<float> px;
    float At(int x, int y) const { return px[static_cast<size_t>(y) * w + x]; }
};

// Box-averaged 1/scale copy, then a light blur (two 3×3 box passes) so a
// sub-pixel offset between the two photos does not break the correlation.
Gray Shrink(const uint8_t* src, int w, int h, int scale) {
    Gray g;
    g.w = w / scale;
    g.h = h / scale;
    g.px.assign(static_cast<size_t>(g.w) * g.h, 0.0f);
    for (int y = 0; y < g.h; ++y) {
        for (int x = 0; x < g.w; ++x) {
            int sum = 0;
            for (int dy = 0; dy < scale; ++dy) {
                const uint8_t* row = src + static_cast<size_t>(y * scale + dy) * w + x * scale;
                for (int dx = 0; dx < scale; ++dx) sum += row[dx];
            }
            g.px[static_cast<size_t>(y) * g.w + x] =
                static_cast<float>(sum) / static_cast<float>(scale * scale);
        }
    }
    for (int pass = 0; pass < 2; ++pass) {
        std::vector<float> out(g.px.size());
        for (int y = 0; y < g.h; ++y) {
            for (int x = 0; x < g.w; ++x) {
                float sum = 0;
                int n = 0;
                for (int dy = -1; dy <= 1; ++dy) {
                    const int yy = y + dy;
                    if (yy < 0 || yy >= g.h) continue;
                    for (int dx = -1; dx <= 1; ++dx) {
                        const int xx = x + dx;
                        if (xx < 0 || xx >= g.w) continue;
                        sum += g.px[static_cast<size_t>(yy) * g.w + xx];
                        ++n;
                    }
                }
                out[static_cast<size_t>(y) * g.w + x] = sum / static_cast<float>(n);
            }
        }
        g.px.swap(out);
    }
    return g;
}

// Zero-mean normalised cross-correlation of A rows [a0, a0+rows) and B rows
// [0, rows), B shifted right by 'shift'. Columns are trimmed by the margin.
// std_out receives the smaller of the two standard deviations.
double Zncc(const float* a, int a_stride, const float* b, int b_stride,
            int width, int a0, int rows, int shift, int margin, int step,
            double* std_out) {
    double sa = 0, sb = 0, saa = 0, sbb = 0, sab = 0;
    long n = 0;
    const int x0 = margin + std::max(0, -shift);
    const int x1 = width - margin - std::max(0, shift);
    if (x1 - x0 < 8 || rows < 2) return -1.0;
    for (int r = 0; r < rows; r += step) {
        const float* ra = a + static_cast<size_t>(a0 + r) * a_stride;
        const float* rb = b + static_cast<size_t>(r) * b_stride;
        for (int x = x0; x < x1; x += step) {
            const double va = ra[x];
            const double vb = rb[x + shift];
            sa += va;
            sb += vb;
            saa += va * va;
            sbb += vb * vb;
            sab += va * vb;
            ++n;
        }
    }
    if (n < 16) return -1.0;
    const double dn = static_cast<double>(n);
    const double va = saa / dn - (sa / dn) * (sa / dn);
    const double vb = sbb / dn - (sb / dn) * (sb / dn);
    if (std_out) *std_out = std::sqrt(std::max(0.0, std::min(va, vb)));
    if (va <= 1e-6 || vb <= 1e-6) return -1.0;
    return (sab / dn - (sa / dn) * (sb / dn)) / std::sqrt(va * vb);
}

}  // namespace

bool FindOverlap(const uint8_t* gray_a, int height_a, const uint8_t* gray_b,
                 int height_b, int width, Overlap* out) {
    if (!gray_a || !gray_b || !out || width < 64 || height_a < 64 ||
        height_b < 64 || width > 8000) {
        return false;
    }
    *out = Overlap{};
    const Gray a = Shrink(gray_a, width, height_a, kCoarse);
    const Gray b = Shrink(gray_b, width, height_b, kCoarse);
    const int w = a.w;
    const int shorter = std::min(a.h, b.h);
    const int min_rows = std::max(10, shorter / 25);
    const int max_rows = shorter * 6 / 10;
    const int max_shift = std::max(2, w / 50);
    const int margin = w / 40;
    if (max_rows <= min_rows) return false;

    // Coarse search over overlap height and horizontal shift.
    std::vector<double> best_by_rows(static_cast<size_t>(max_rows + 1), -2.0);
    std::vector<int> shift_by_rows(static_cast<size_t>(max_rows + 1), 0);
    for (int rows = min_rows; rows <= max_rows; ++rows) {
        for (int shift = -max_shift; shift <= max_shift; ++shift) {
            double sd = 0;
            const double z = Zncc(a.px.data(), w, b.px.data(), w, w, a.h - rows,
                                  rows, shift, margin, 1, &sd);
            if (sd < kMinStd) continue;
            if (z > best_by_rows[static_cast<size_t>(rows)]) {
                best_by_rows[static_cast<size_t>(rows)] = z;
                shift_by_rows[static_cast<size_t>(rows)] = shift;
            }
        }
    }
    int best_rows = -1;
    double best = -2.0;
    for (int rows = min_rows; rows <= max_rows; ++rows) {
        if (best_by_rows[static_cast<size_t>(rows)] > best) {
            best = best_by_rows[static_cast<size_t>(rows)];
            best_rows = rows;
        }
    }
    if (best_rows < 0 || best < kMinCoarse) return false;
    // Repeating content (table rows, ruled lines) can match at another
    // height almost as well: then the join is ambiguous, keep the pages.
    double rival = -2.0;
    for (int rows = min_rows; rows <= max_rows; ++rows) {
        if (std::abs(rows - best_rows) < 4) continue;
        rival = std::max(rival, best_by_rows[static_cast<size_t>(rows)]);
    }
    if (best - rival < kMinMargin) return false;

    // Refine at half resolution around the coarse answer.
    const Gray fa = Shrink(gray_a, width, height_a, kFine);
    const Gray fb = Shrink(gray_b, width, height_b, kFine);
    const int ratio = kCoarse / kFine;
    const int coarse_rows = best_rows * ratio;
    const int coarse_shift = shift_by_rows[static_cast<size_t>(best_rows)] * ratio;
    double fine_best = -2.0;
    int fine_rows = 0;
    int fine_shift = 0;
    for (int rows = coarse_rows - ratio * 2; rows <= coarse_rows + ratio * 2; ++rows) {
        if (rows < 8 || rows >= std::min(fa.h, fb.h)) continue;
        for (int shift = coarse_shift - ratio * 2; shift <= coarse_shift + ratio * 2; ++shift) {
            double sd = 0;
            const double z = Zncc(fa.px.data(), fa.w, fb.px.data(), fb.w, fa.w,
                                  fa.h - rows, rows, shift, margin * ratio, 1, &sd);
            if (z > fine_best) {
                fine_best = z;
                fine_rows = rows;
                fine_shift = shift;
            }
        }
    }
    out->rows = fine_rows * kFine + (height_a - fa.h * kFine);
    out->shift = fine_shift * kFine;
    if (fine_best < kMinScore) {
        *out = Overlap{};
        return false;
    }
    out->score = static_cast<float>(fine_best);
    return true;
}

}  // namespace ds
