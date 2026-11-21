## DocScanner v0.5.70

- 🟩 Live camera: the green box now also uses **DocNet** (DocScanner's own document model, libds_docnet.so) instead of only the general U²-Net model — it runs more than twice as often, so the box finds the whole page more reliably
- 📐 Dewarp: after straightening the page edges, wavy **text lines inside a strongly curled page** are now straightened too
- 🧵 Smart stitch: parts photographed from a slightly different distance (up to about ±9 %) are now joined too
- ✂️ Auto crop: a page that fills the photo with tables running off the edge keeps its real corner (it used to be cut diagonally)
