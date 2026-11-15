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
