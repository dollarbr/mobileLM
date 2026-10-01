import org.jetbrains.kotlin.gradle.dsl.JvmTarget

group = "com.dollarbr.litert_flutter"
version = "0.1.0"

buildscript {
    val kotlinVersion = "2.4.20"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:8.11.1")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
    id("kotlin-android")
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

android {
    namespace = "com.dollarbr.litert_flutter"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
    }

    defaultConfig {
        minSdk = 24
        // arm64 only, like every other native plugin in this app. Without it the
        // AAR carries four ABIs of LiteRT and the APK grows by ~18 MB of
        // libraries this app has never shipped a 32-bit build for — the same
        // reason llama_flutter_android and sd_flutter_android pin it.
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
        consumerProguardFiles("consumer-rules.pro")
    }

    packaging {
        jniLibs {
            // The LiteRT AAR ships the same natives for every ABI it supports.
            // `abiFilters` already keeps the 32-bit and x86 ones out of the APK;
            // this is the second gate, for the case where a consumer app
            // unpacks the AAR itself.
            useLegacyPackaging = false
        }
    }
}

dependencies {
    implementation("org.jetbrains.kotlin:kotlin-stdlib:2.4.20")

    // LiteRT 2.2.0, and 2.2.0 specifically.
    //
    // Not 1.4.2, which is 4.3 MB instead of 8.7 MB and would have been the
    // smaller choice. Two things decide it:
    //
    // 1. `litert` alone exposes only the old `org.tensorflow.lite.Interpreter`
    //    API. `CompiledModel` and `GpuOptions` — the accelerator-aware API this
    //    plugin needs to choose CPU vs OpenCL per model — are in `litert-api`,
    //    which at 2.2.0 is an AAR (the `.jar` Maven serves for it is 1449 bytes
    //    and empty) and carries only 0.5 MB of native code.
    // 2. It is the version the Laya model card names: "both graphs use LiteRT
    //    2.2.0 CompiledModel with GpuOptions(precision = FP32)". Binding to a
    //    different version than the one a published model was validated against
    //    is a way to find out the hard way that the numbers moved.
    implementation("com.google.ai.edge.litert:litert:2.2.0")
    implementation("com.google.ai.edge.litert:litert-api:2.2.0")

    implementation("androidx.core:core-ktx:1.12.0")
}
