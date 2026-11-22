## DocScanner v0.5.72

- 🟩 Live camera: when a page fills the screen and runs off the edge, the green box now follows the visible paper (its corners may sit on the screen edge) instead of jumping onto the printed table or a slanted box through the text; the shutter crops that visible page

## DocScanner v0.5.71

- 🎨 Filters: every option (B&W, Eco, Grayscale, Magic Pro, No Shadow, Lighten, No Watermark, No Handwriting) is now built from the original photo with a local paper-brightness map, so shadowed pages come out clean; each filter tile shows a real preview, and rotating no longer loses the chosen filter
- 🪪 ID Cards (General, ID Card, Driver License, Bank Card): new camera screen with a rounded white corner frame, dimmed outside, Front/Back pill, HD and menu icons
- ✨ Front/Back capture shows the teal scan animation (outline + sweep, then morph to the cropped card)
- ✂️ Card camera now finds all four corners on patterned cloth, printed sheets and for small or tilted business cards

## DocScanner v0.5.70

- 🟩 Live camera: the green box now also uses **DocNet** (DocScanner's own document model, libds_docnet.so) instead of only the general U²-Net model — it runs more than twice as often, so the box finds the whole page more reliably
- 📐 Dewarp: after straightening the page edges, wavy **text lines inside a strongly curled page** are now straightened too
- 🧵 Smart stitch: parts photographed from a slightly different distance (up to about ±9 %) are now joined too
- ✂️ Auto crop: a page that fills the photo with tables running off the edge keeps its real corner (it used to be cut diagonally)
