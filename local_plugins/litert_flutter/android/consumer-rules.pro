# Consumer Proguard / R8 rules shipped with the litert_flutter plugin.
#
# These are merged into any app that depends on this plugin, the same way
# flutter_litert_lm's consumer-rules.pro is.
#
# LiteRT is a JNI library. Its C++ side calls back into Kotlin through JNI to
# construct and read the options objects — `CompiledModel$Options`,
# `GpuOptions`, `CpuOptions`, `TensorType`, `TensorBufferRequirements` — and R8
# cannot see those calls. In a release build it strips or renames the
# constructors and getters, and the failure is not a clean exception: the
# native side raises a JNI error deep inside a model load, with nothing in the
# message pointing at shrinking.
#
# The app has `isMinifyEnabled = false`, so these rules do nothing there. They
# are here because the AAR is consumable by other apps, and because the day
# someone turns R8 on, this is the note that says why it cannot just work.

-keep class com.google.ai.edge.litert.** { *; }
-keep class org.tensorflow.lite.** { *; }
-keepclassmembers class com.google.ai.edge.litert.** {
    native <methods>;
}
