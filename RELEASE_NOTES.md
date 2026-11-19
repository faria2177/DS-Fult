## DocScanner v0.5.57

- 🚑 Fixed: v0.5.55 and v0.5.56 installed but did not open. A library update published on 18 November (jni 1.2.0) broke file-folder access in release builds, so the app could not load your documents at start-up. The app now uses the last working version of that library
- 🔧 Edit Text OCR: the ML Kit fix from v0.5.54 is confirmed working on start-up
- ✅ Every new version is now opened on an Android emulator before it is published; if it does not start cleanly, no update is released
- Your documents are safe: install this APK over the old one (no need to uninstall)
