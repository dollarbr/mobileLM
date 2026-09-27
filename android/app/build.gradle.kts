import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}
val isReleaseBuild = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}
val isCI = System.getenv().containsKey("GITHUB_ACTIONS") || System.getenv().containsKey("CI")

// A release build must be signed with the release key, or not produced at all.
//
// There used to be a `MOBILELM_ALLOW_DEBUG_RELEASE_SIGNING` escape that fell
// back to the debug signing config when no keystore was present -- and
// release.yml set it to "true" unconditionally, so every published APK carried
// `CN=Android Debug`. The debug key is public: anyone could produce an APK that
// updates over a user's, and nothing in the build said so. The three
// RELEASE_* secrets were configured on the repository and never read.
//
// The fallback is gone rather than left off by default. An opt-in that exists
// is an opt-in someone will set, and the failure it causes is invisible until
// someone checks a certificate. Fail here instead, where the log is read.
if (isReleaseBuild) {
    if (!isCI) {
        throw GradleException(
            "Release builds are ONLY allowed in CI environments. " +
                    "For local testing, use a debug build."
        )
    }
    if (!hasReleaseKeystore) {
        throw GradleException(
            "Release signing is not configured: android/key.properties is missing. " +
                    "A release build is never debug-signed by design. To produce a local " +
                    "artifact to look at, build debug instead."
        )
    }
    val alias = keystoreProperties.getProperty("keyAlias")
    val storeFile = keystoreProperties.getProperty("storeFile")
    if (alias.isNullOrBlank() || storeFile.isNullOrBlank()) {
        throw GradleException(
            "android/key.properties must define both keyAlias and storeFile."
        )
    }
    // `file()` below resolves relative paths against this module's directory
    // (android/app), not against android/ where key.properties lives. Catching
    // it here names the mistake; otherwise the failure is "keystore password was
    // incorrect", which is what a wrong password also says.
    if (!file(storeFile).exists()) {
        throw GradleException(
            "key.properties points at a storeFile that does not exist: $storeFile " +
                    "(resolved to ${file(storeFile).absolutePath})"
        )
    }
}

if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
    apply(plugin = "com.google.firebase.crashlytics")
}

android {
    namespace = "com.dollarbr.mobilelm"
    compileSdk = flutter.compileSdkVersion

    // The privileged shell talks to Shizuku's UserService over AIDL.
    buildFeatures {
        aidl = true
    }
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }

    defaultConfig {
        applicationId = "com.dollarbr.mobilelm"
        minSdk = 28
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }


    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // The guard at the top of this file has already thrown if this is a
            // release build and the keystore is missing, so there is no path
            // that reaches here with a release APK signed by anything else.
            //
            // `null` rather than an unconditional getByName("release"): the
            // signingConfig is only created when key.properties exists, and this
            // block is evaluated during configuration for *every* build type.
            // Asking for it unconditionally breaks a plain debug build on a
            // machine with no keystore -- which is most machines.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                null
            }
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // Privileged shell. The app never invokes su and never requires root;
    // Shizuku is the only privileged path.
    implementation("dev.rikka.shizuku:api:13.1.5")
    implementation("dev.rikka.shizuku:provider:13.1.5")
    implementation("androidx.work:work-runtime-ktx:2.9.1")

    // Local plugins
    implementation(project(":llama_flutter_android"))
    implementation(project(":sd_flutter_android"))
    implementation(project(":flutter_litert_lm"))
}

flutter {
    source = "../.."
}
