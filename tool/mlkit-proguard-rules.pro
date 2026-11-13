# ML Kit Flutter TextRecognizer includes optional script branches, but this
# app initializes only TextRecognitionScript.latin. Missing optional classes
# must not make release R8 builds fail.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# The independent scanner uses name-based JNI exports. Release shrinking must
# preserve these native Kotlin class/method names for Java_* symbol lookup.
-keep class dev.doclens.doclens.NativePageScanner { *; }
-keep class dev.doclens.doclens.NativeImageEnhancer { *; }
