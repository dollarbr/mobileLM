group = "com.write4me.llama_flutter_android"
version = "1.0.0"

// Define extra properties BEFORE buildscript
extra["kotlinVersion"] = "2.4.20"

buildscript {
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:8.11.1")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:2.4.20")
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

android {
    namespace = "com.write4me.llama_flutter_android"
    
    // Target Android 15 with 16KB page size support
    compileSdk = 35
    
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
        }
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
        getByName("test") {
            java.srcDirs("src/test/kotlin")
        }
    }

    defaultConfig {
        // **28, e o motivo é o Vulkan — não SharedMemory.**
        //
        // O `minSdk` aqui manda em `ANDROID_PLATFORM`, que é contra qual
        // sysroot o NDK resolve a `libvulkan.so` do link. O `ggml-vulkan`
        // re-sincronizado usa `vkGetPhysicalDeviceFeatures2`, e a stub do NDK
        // só exporta esse símbolo a partir da **API 28** — na 26 ele dá
        // `undefined symbol: vkGetPhysicalDeviceFeatures2` e o link inteiro
        // morre, com todo o resto compilando.
        //
        // O comentário antigo dizia *"Android 8.0 (for SharedMemory support)"*
        // e essa razão **não existe no plugin**: `SharedMemory`, `ashmem` e
        // `memfd_create` não aparecem em nenhum arquivo do JNI, e a única
        // ocorrência de "SharedMemory" está em headers CUDA que este projeto
        // não compila. Mesmo que existisse, `memfd_create` é API 30.
        //
        // **28 é o que `android/app/build.gradle.kts` já declara**, então isto
        // alinha o plugin ao app em vez de baixar o teto do app. O A72 é API 35.
        minSdk = 28  // Android 9 — o que o app já exige, e onde a libvulkan do NDK tem o símbolo
        
        ndk {
            abiFilters.addAll(listOf("arm64-v8a"))  // Only ARM64
        }
        
        externalNativeBuild {
            cmake {
                // Android 15 16KB page size compliance
                cppFlags += listOf(
                    "-std=c++17",
                    "-O3",
                    "-fvisibility=hidden"
                )
                
                // ARM64 optimization flags
                arguments += listOf(
                    "-DANDROID_STL=c++_shared",
                    "-DANDROID_ARM_NEON=ON",
                    "-DGGML_CPU_AARCH64=ON",
                    "-DGGML_DOTPROD=ON",
                    "-DGGML_OPENMP=OFF"
                )
            }
        }
    }
    
    externalNativeBuild {
        cmake {
            path = file("CMakeLists.txt")
            version = "3.22.1"
        }
    }

    dependencies {
        implementation("org.jetbrains.kotlin:kotlin-stdlib:2.4.20")
        implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.9.0")
        implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
        implementation("androidx.core:core-ktx:1.12.0")
        
        testImplementation("org.jetbrains.kotlin:kotlin-test")
        testImplementation("org.mockito:mockito-core:5.0.0")
    }

    testOptions {
        unitTests.all {
            it.useJUnitPlatform()
        }
    }
}
