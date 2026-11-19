## DocScanner v0.5.58

- 🟩 Scan camera: cards and documents that are partly dark (for example a bank ID card with a dark blue top and a white bottom, lying on a patterned cloth) are now boxed as a whole. Before, the green box only covered the bright part
- How: the on-device object model that already powers gallery auto-crop now also checks the live camera a few times per second; when the edge detector has only found the bright part of an object, the box grows to the whole object
- Bright white pages are boxed exactly as before
