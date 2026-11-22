# PresenterSync Remote Android ProGuard / R8 rules
# Keep transparent non-obfuscated symbol names alongside dead-code shrinking (Play Protect friendly)
-dontobfuscate

# Keep Kotlin & Compose metadata, annotations, and stack trace line numbers
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod,SourceFile,LineNumberTable
-keep class kotlin.Metadata { *; }

# Keep all app classes, enums (values/valueOf/ordinal/name), data models & UI entry points
-keep class com.saabithjiffry.presentersync.remote.** { *; }
-keepclassmembers class com.saabithjiffry.presentersync.remote.** { *; }
-keepclassmembers enum com.saabithjiffry.presentersync.remote.** {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# AndroidManifest entry points (Application, Activity, Services, Receivers, Widgets, Custom Views)
-keep public class * extends android.app.Application
-keep public class * extends android.app.Activity
-keep public class * extends android.app.Service
-keep public class * extends android.content.BroadcastReceiver
-keep public class * extends android.appwidget.AppWidgetProvider
-keep public class * extends android.service.quicksettings.TileService
-keep public class com.saabithjiffry.presentersync.remote.** extends android.view.View {
    public <init>(android.content.Context);
    public <init>(android.content.Context, android.util.AttributeSet);
    public <init>(android.content.Context, android.util.AttributeSet, int);
}
-keep class org.json.** { *; }

# Native JNI methods (AudioTrack / CameraX image processing / Compose graphics)
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}

# Kotlin Coroutines (ServiceLoader + atomic updaters)
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-keepclassmembers class kotlinx.coroutines.** {
    volatile <fields>;
}
-keepclassmembernames class kotlinx.** {
    volatile <fields>;
}
-dontwarn kotlinx.coroutines.**

# CameraX + ZXing (zero-GMS Camera2 / ImageAnalysis / ServiceLoader providers)
-keep class androidx.camera.** { *; }
-keep interface androidx.camera.** { *; }
-keep class * implements androidx.camera.core.CameraXConfig$Provider { *; }
-keep class com.google.zxing.** { *; }
-dontwarn androidx.camera.**

# OkHttp4 / Okio / TLS optional platform providers
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn org.bouncycastle.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**
-dontwarn org.codehaus.mojo.animal_sniffer.**
-dontwarn javax.annotation.**
