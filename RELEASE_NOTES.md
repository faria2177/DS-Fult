## DocScanner v0.5.68

- 🧵 Long image: new **Smart stitch** (native library **libds_stitch.so**, DocScanner's own code). When you scan a long receipt or list in parts and the parts overlap, the repeated band is joined once instead of appearing twice — the long image reads as one continuous page
- The screen shows how many overlapping parts were joined; turn Smart stitch off to place pages one below the other as before
- Pages that don't overlap, blank edges and repeating tables are never merged by mistake
