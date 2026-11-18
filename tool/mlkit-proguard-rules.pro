# ML Kit Flutter TextRecognizer includes optional script branches, but this
# app initializes only TextRecognitionScript.latin. Missing optional classes
# must not make release R8 builds fail.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# ML Kit finds its internal components through reflection (component
# registrars declared in the manifest). R8 full mode removed their
# constructors in release builds, so the text recognizer client came back
# null and every OCR call failed with
# "Attempt to invoke virtual method 'java.lang.Class
#  java.lang.Object.getClass()' on a null object reference".
-keepattributes Signature,*Annotation*,InnerClasses,EnclosingMethod
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_bundled_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }
-keep class com.google.android.gms.internal.mlkit_common.** { *; }
-keep class com.google.android.libraries.barhopper.** { *; }
-keep class com.google.photos.** { *; }
-keep class com.google_mlkit_commons.** { *; }
-keep class com.google_mlkit_text_recognition.** { *; }
-keep class com.google_mlkit_barcode_scanning.** { *; }
-keep class com.google.firebase.components.** { *; }
-keep class * implements com.google.firebase.components.ComponentRegistrar { *; }

# The independent scanner uses name-based JNI exports. Release shrinking must
# preserve these native Kotlin class/method names for Java_* symbol lookup.
-keep class dev.doclens.doclens.NativePageScanner { *; }
-keep class dev.doclens.doclens.NativeImageEnhancer { *; }
