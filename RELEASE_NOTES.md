## DocScanner v0.5.65

- 📄 New native library **libds_pdfcodec.so** — DocScanner's own CCITT Group 4 encoder: black-and-white pages are saved in the PDF as sharp 1-bit images, typically 10–20× smaller than before (a full A4 text page ≈ 20 KB instead of ≈ 400 KB)
- 🎨 Pages with colour (stamps, photos, coloured print) stay full colour automatically
- ⚡ Compressed PDF export now shrinks pages with Android's built-in JPEG codec — much faster on big documents
