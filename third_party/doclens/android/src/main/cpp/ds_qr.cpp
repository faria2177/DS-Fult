#include "ds_qr.h"

#include "ReadBarcode.h"

namespace ds {

bool ReadCodes(const uint8_t* luma, int width, int height, bool try_harder,
               std::vector<Code>* out) {
    if (!luma || !out || width < 16 || height < 16 || width > 8192 ||
        height > 8192) {
        return false;
    }
    out->clear();
    ZXing::ImageView image(luma, width, height, ZXing::ImageFormat::Lum);
    ZXing::ReaderOptions options;
    options.setFormats(ZXing::BarcodeFormat::Any);
    options.setTryHarder(try_harder);
    options.setTryRotate(try_harder);
    options.setTryInvert(try_harder);
    options.setTryDownscale(true);
    options.setMaxNumberOfSymbols(8);
    for (const auto& barcode : ZXing::ReadBarcodes(image, options)) {
        if (!barcode.isValid() || barcode.text().empty()) continue;
        Code code;
        code.format = ZXing::ToString(barcode.format());
        code.text = barcode.text();
        const auto& p = barcode.position();
        const ZXing::PointI pts[4] = {p.topLeft(), p.topRight(), p.bottomRight(),
                                      p.bottomLeft()};
        for (int i = 0; i < 4; ++i) {
            code.corners[static_cast<size_t>(i * 2)] = pts[i].x;
            code.corners[static_cast<size_t>(i * 2 + 1)] = pts[i].y;
        }
        out->push_back(std::move(code));
    }
    return true;
}

}  // namespace ds
