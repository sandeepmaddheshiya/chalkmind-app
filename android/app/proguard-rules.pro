# shared_preferences_android 2.5.x calls its Kotlin API from Dart through JNI
# (package:jni) by exact class/method name and signature, but ships no keep
# rules. Without these, R8 renames them in release builds and every
# preference read/write fails (NoSuchMethodError / ClassNotFoundException):
# settings, onboarding flags and AI settings were silently not persisted.
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep interface io.flutter.plugins.sharedpreferences.** { *; }

# Kotlin runtime classes the generated JNI bindings look up by name
# (from shared_preferences_android/lib and jni/lib).
-keep class kotlin.coroutines.Continuation { *; }
-keep interface kotlin.coroutines.Continuation { *; }
-keep class kotlin.coroutines.intrinsics.CoroutineSingletons { *; }
-keep class kotlin.coroutines.intrinsics.IntrinsicsKt { *; }
-keep class kotlin.enums.EnumEntries { *; }
-keep interface kotlin.enums.EnumEntries { *; }
-keep class kotlin.jvm.internal.DefaultConstructorMarker { *; }
-keep class kotlin.Result { *; }
-keep class kotlin.Result$Failure { *; }
-keep class kotlin.Unit { *; }

# Google sign-in (google_sign_in 7 uses Android Credential Manager). The
# Play Services provider is loaded by reflection.
-if class androidx.credentials.CredentialManager
-keep class androidx.credentials.playservices.** { *; }
-keep class com.google.android.libraries.identity.googleid.** { *; }

# ML Kit Digital Ink (on-device handwriting) downloads its model through
# WorkManager, whose Room database is created by reflection from the
# generated *_Impl class. Without these, release builds crash at startup
# ("Failed to create an instance of androidx.work.impl.WorkDatabase").
-keep class androidx.work.** { *; }
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.room.** { *; }
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_digital_ink.** { *; }
