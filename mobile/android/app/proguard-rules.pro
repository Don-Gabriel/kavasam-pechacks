# Kavasam release keep rules.
# mobile_scanner loads CameraX and ML Kit barcode classes by reflection, which
# R8 strips without these keeps (crash: "invoke virtual method on a null object
# reference"). Only consulted when minification is enabled.

-keep class dev.steenbakker.mobile_scanner.** { *; }

# CameraX
-keep class androidx.camera.** { *; }
-keep interface androidx.camera.** { *; }
-dontwarn androidx.camera.**

# ML Kit barcode scanning
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }
-dontwarn com.google.mlkit.**

# ML Kit registers detector components via reflection.
-keep class * extends com.google.mlkit.common.sdkinternal.OptionalModuleApi { *; }
-keepclassmembers class * {
    @com.google.android.gms.common.annotation.KeepName *;
}
