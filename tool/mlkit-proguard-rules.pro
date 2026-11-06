# ML Kit Flutter TextRecognizer includes optional script branches, but this
# app initializes only TextRecognitionScript.latin. Missing optional classes
# must not make release R8 builds fail.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
