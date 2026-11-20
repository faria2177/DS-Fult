## DocScanner v0.5.64

- 🧠 New native library **libds_docnet.so** with **DocNet** — DocScanner's own AI model that finds the document in a photo (trained by us on generated images), running on the open-source ncnn engine
- ✂️ Import / auto crop: DocNet now finds the page first; when the photo's edges confirm its outline it is used, otherwise the previous model and detectors take over as before
