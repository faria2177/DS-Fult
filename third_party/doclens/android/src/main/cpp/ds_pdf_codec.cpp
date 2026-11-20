#include "ds_pdf_codec.h"

#include <cstdint>
#include <cstdlib>
#include <vector>

namespace ds {
namespace {

struct Code {
    uint16_t bits;
    uint8_t length;
};

// ITU-T T.4 tables 2 and 3: terminating codes for runs 0..63.
constexpr Code kWhiteTerm[64] = {
    {0x35, 8}, {0x7, 6},  {0x7, 4},  {0x8, 4},  {0xB, 4},  {0xC, 4},  {0xE, 4},
    {0xF, 4},  {0x13, 5}, {0x14, 5}, {0x7, 5},  {0x8, 5},  {0x8, 6},  {0x3, 6},
    {0x34, 6}, {0x35, 6}, {0x2A, 6}, {0x2B, 6}, {0x27, 7}, {0xC, 7},  {0x8, 7},
    {0x17, 7}, {0x3, 7},  {0x4, 7},  {0x28, 7}, {0x2B, 7}, {0x13, 7}, {0x24, 7},
    {0x18, 7}, {0x2, 8},  {0x3, 8},  {0x1A, 8}, {0x1B, 8}, {0x12, 8}, {0x13, 8},
    {0x14, 8}, {0x15, 8}, {0x16, 8}, {0x17, 8}, {0x28, 8}, {0x29, 8}, {0x2A, 8},
    {0x2B, 8}, {0x2C, 8}, {0x2D, 8}, {0x4, 8},  {0x5, 8},  {0xA, 8},  {0xB, 8},
    {0x52, 8}, {0x53, 8}, {0x54, 8}, {0x55, 8}, {0x24, 8}, {0x25, 8}, {0x58, 8},
    {0x59, 8}, {0x5A, 8}, {0x5B, 8}, {0x4A, 8}, {0x4B, 8}, {0x32, 8}, {0x33, 8},
    {0x34, 8},
};

constexpr Code kBlackTerm[64] = {
    {0x37, 10}, {0x2, 3},   {0x3, 2},   {0x2, 2},   {0x3, 3},   {0x3, 4},
    {0x2, 4},   {0x3, 5},   {0x5, 6},   {0x4, 6},   {0x4, 7},   {0x5, 7},
    {0x7, 7},   {0x4, 8},   {0x7, 8},   {0x18, 9},  {0x17, 10}, {0x18, 10},
    {0x8, 10},  {0x67, 11}, {0x68, 11}, {0x6C, 11}, {0x37, 11}, {0x28, 11},
    {0x17, 11}, {0x18, 11}, {0xCA, 12}, {0xCB, 12}, {0xCC, 12}, {0xCD, 12},
    {0x68, 12}, {0x69, 12}, {0x6A, 12}, {0x6B, 12}, {0xD2, 12}, {0xD3, 12},
    {0xD4, 12}, {0xD5, 12}, {0xD6, 12}, {0xD7, 12}, {0x6C, 12}, {0x6D, 12},
    {0xDA, 12}, {0xDB, 12}, {0x54, 12}, {0x55, 12}, {0x56, 12}, {0x57, 12},
    {0x64, 12}, {0x65, 12}, {0x52, 12}, {0x53, 12}, {0x24, 12}, {0x37, 12},
    {0x38, 12}, {0x27, 12}, {0x28, 12}, {0x58, 12}, {0x59, 12}, {0x2B, 12},
    {0x2C, 12}, {0x5A, 12}, {0x66, 12}, {0x67, 12},
};

// Make-up codes for 64, 128, ..., 1728.
constexpr Code kWhiteMakeup[27] = {
    {0x1B, 5}, {0x12, 5}, {0x17, 6}, {0x37, 7}, {0x36, 8}, {0x37, 8}, {0x64, 8},
    {0x65, 8}, {0x68, 8}, {0x67, 8}, {0xCC, 9}, {0xCD, 9}, {0xD2, 9}, {0xD3, 9},
    {0xD4, 9}, {0xD5, 9}, {0xD6, 9}, {0xD7, 9}, {0xD8, 9}, {0xD9, 9}, {0xDA, 9},
    {0xDB, 9}, {0x98, 9}, {0x99, 9}, {0x9A, 9}, {0x18, 6}, {0x9B, 9},
};

constexpr Code kBlackMakeup[27] = {
    {0xF, 10},  {0xC8, 12}, {0xC9, 12}, {0x5B, 12}, {0x33, 12}, {0x34, 12},
    {0x35, 12}, {0x6C, 13}, {0x6D, 13}, {0x4A, 13}, {0x4B, 13}, {0x4C, 13},
    {0x4D, 13}, {0x72, 13}, {0x73, 13}, {0x74, 13}, {0x75, 13}, {0x76, 13},
    {0x77, 13}, {0x52, 13}, {0x53, 13}, {0x54, 13}, {0x55, 13}, {0x5A, 13},
    {0x5B, 13}, {0x64, 13}, {0x65, 13},
};

// Extended make-up codes 1792..2560, shared by both colours.
constexpr Code kExtendedMakeup[13] = {
    {0x8, 11},  {0xC, 11},  {0xD, 11},  {0x12, 12}, {0x13, 12}, {0x14, 12},
    {0x15, 12}, {0x16, 12}, {0x17, 12}, {0x1C, 12}, {0x1D, 12}, {0x1E, 12},
    {0x1F, 12},
};

constexpr Code kPass = {0x1, 4};        // 0001
constexpr Code kHorizontal = {0x1, 3};  // 001
// Vertical modes indexed by b1 - a1 + 3: VR3, VR2, VR1, V0, VL1, VL2, VL3.
constexpr Code kVertical[7] = {
    {0x3, 7}, {0x3, 6}, {0x3, 3}, {0x1, 1}, {0x2, 3}, {0x2, 6}, {0x2, 7},
};

class BitWriter {
public:
    explicit BitWriter(std::vector<uint8_t>* out) : out_(out) {}

    void Put(Code code) {
        for (int i = code.length - 1; i >= 0; --i) {
            acc_ = static_cast<uint8_t>((acc_ << 1) | ((code.bits >> i) & 1));
            if (++count_ == 8) {
                out_->push_back(acc_);
                acc_ = 0;
                count_ = 0;
            }
        }
    }

    void Flush() {
        if (count_ > 0) {
            out_->push_back(static_cast<uint8_t>(acc_ << (8 - count_)));
            acc_ = 0;
            count_ = 0;
        }
    }

private:
    std::vector<uint8_t>* out_;
    uint8_t acc_ = 0;
    int count_ = 0;
};

void PutRun(BitWriter& w, int run, bool black) {
    const Code* term = black ? kBlackTerm : kWhiteTerm;
    const Code* makeup = black ? kBlackMakeup : kWhiteMakeup;
    while (run >= 2624) {
        w.Put(kExtendedMakeup[12]);  // 2560
        run -= 2560;
    }
    if (run >= 64) {
        const int m = run / 64;  // 1..40
        if (m <= 27) {
            w.Put(makeup[m - 1]);
        } else {
            w.Put(kExtendedMakeup[m - 28]);
        }
        run -= m * 64;
    }
    w.Put(term[run]);
}

// First position >= start whose pixel differs from colour (width if none).
int FindDiff(const uint8_t* line, int start, int width, uint8_t colour) {
    int i = start;
    while (i < width && line[i] == colour) ++i;
    return i;
}

int FindDiff2(const uint8_t* line, int start, int width, uint8_t colour) {
    return start < width ? FindDiff(line, start, width, colour) : width;
}

}  // namespace

double BilevelShare(const uint8_t* gray, int width, int height) {
    if (!gray || width <= 0 || height <= 0) return 0.0;
    int64_t clear = 0;
    int64_t total = 0;
    const int step = width * static_cast<int64_t>(height) > 4000000 ? 2 : 1;
    for (int y = 0; y < height; y += step) {
        const uint8_t* row = gray + static_cast<size_t>(y) * width;
        for (int x = 0; x < width; x += step) {
            if (row[x] < 64 || row[x] > 191) ++clear;
            ++total;
        }
    }
    return total ? static_cast<double>(clear) / static_cast<double>(total) : 0.0;
}

double ColourShare(const uint32_t* argb, int width, int height) {
    if (!argb || width <= 0 || height <= 0) return 1.0;
    int64_t coloured = 0;
    int64_t total = 0;
    for (int y = 0; y < height; y += 2) {
        const uint32_t* row = argb + static_cast<size_t>(y) * width;
        for (int x = 0; x < width; x += 2) {
            const int r = static_cast<int>((row[x] >> 16) & 255U);
            const int g = static_cast<int>((row[x] >> 8) & 255U);
            const int b = static_cast<int>(row[x] & 255U);
            const int hi = r > g ? (r > b ? r : b) : (g > b ? g : b);
            const int lo = r < g ? (r < b ? r : b) : (g < b ? g : b);
            if (hi - lo > 48) ++coloured;
            ++total;
        }
    }
    return total ? static_cast<double>(coloured) / static_cast<double>(total) : 1.0;
}

void ArgbToGray(const uint32_t* argb, int width, int height, uint8_t* gray) {
    const size_t n = static_cast<size_t>(width) * static_cast<size_t>(height);
    for (size_t i = 0; i < n; ++i) {
        const uint32_t p = argb[i];
        const uint32_t r = (p >> 16) & 255U, g = (p >> 8) & 255U, b = p & 255U;
        gray[i] = static_cast<uint8_t>((77U * r + 150U * g + 29U * b) >> 8);
    }
}

bool EncodeG4(const uint8_t* gray, int width, int height, int threshold,
              std::vector<uint8_t>* out) {
    if (!gray || !out || width <= 0 || height <= 0 || width > 20000 ||
        height > 20000) {
        return false;
    }
    out->clear();
    out->reserve(static_cast<size_t>(width) * height / 40 + 64);
    BitWriter w(out);
    // 1 = black. The reference line above the first row is all white.
    std::vector<uint8_t> ref(static_cast<size_t>(width), 0);
    std::vector<uint8_t> cur(static_cast<size_t>(width), 0);
    for (int y = 0; y < height; ++y) {
        const uint8_t* src = gray + static_cast<size_t>(y) * width;
        for (int x = 0; x < width; ++x) cur[static_cast<size_t>(x)] = src[x] < threshold ? 1 : 0;
        const uint8_t* bp = cur.data();
        const uint8_t* rp = ref.data();

        int a0 = 0;
        int a1 = bp[0] != 0 ? 0 : FindDiff(bp, 0, width, 0);
        int b1 = rp[0] != 0 ? 0 : FindDiff(rp, 0, width, 0);
        bool first = true;
        for (;;) {
            const int b2 = FindDiff2(rp, b1, width, b1 < width ? rp[b1] : 0);
            if (b2 >= a1) {
                const int d = b1 - a1;
                if (d < -3 || d > 3) {
                    // Horizontal mode: runs a0a1 and a1a2.
                    const int a2 = FindDiff2(bp, a1, width, a1 < width ? bp[a1] : 0);
                    w.Put(kHorizontal);
                    const bool a0_white = first || bp[a0] == 0;
                    PutRun(w, a1 - a0, !a0_white);
                    PutRun(w, a2 - a1, a0_white);
                    a0 = a2;
                } else {
                    w.Put(kVertical[d + 3]);
                    a0 = a1;
                }
            } else {
                w.Put(kPass);
                a0 = b2;
            }
            first = false;
            if (a0 >= width) break;
            const uint8_t colour = bp[a0];
            a1 = FindDiff(bp, a0, width, colour);
            b1 = FindDiff(rp, a0, width, static_cast<uint8_t>(colour ^ 1));
            b1 = FindDiff(rp, b1, width, colour);
        }
        ref.swap(cur);
    }
    // EOFB: two EOL codes.
    w.Put({0x1, 12});
    w.Put({0x1, 12});
    w.Flush();
    return true;
}

}  // namespace ds
