cmake_minimum_required(VERSION 3.22.1)

project(sd_jni)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Android 15 16KB page size compliance
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -Wl,-z,max-page-size=16384")
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -Wl,-z,max-page-size=16384")

# Vulkan is disabled on Android because Adreno drivers crash with ggml compute shaders.
# CPU (ARM64 NEON) is slower but stable.
set(SD_VULKAN OFF CACHE BOOL "Enable Vulkan backend" FORCE)
set(GGML_VULKAN OFF CACHE BOOL "Enable GGML Vulkan" FORCE)

# Use custom FindVulkan that works with Android NDK cross-compilation
list(INSERT CMAKE_MODULE_PATH 0 "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

# Add stable-diffusion.cpp
set(SD_BUILD_EXAMPLES OFF CACHE BOOL "Disable SD examples")
set(SD_BUILD_SHARED_LIBS OFF CACHE BOOL "Build SD as static")
add_subdirectory(src/main/cpp/stable-diffusion.cpp)

# ggml-base is linked as a standalone shared object and contains C++ sources.
# On Android/NDK it must explicitly link libc++ or symbols such as operator new
# and std::runtime_error stay unresolved during the native build.
if(ANDROID)
    foreach(target ggml-base ggml stable-diffusion)
        if(TARGET ${target})
            target_link_libraries(${target} PRIVATE c++_shared)
        endif()
    endforeach()
endif()

# JNI wrapper library
add_library(sd_jni SHARED
    src/main/cpp/sd_jni_wrapper.cpp
)

target_link_libraries(sd_jni
    stable-diffusion
    c++_shared
    android
    log
)

target_include_directories(sd_jni PRIVATE
    src/main/cpp/stable-diffusion.cpp/include
    src/main/cpp/stable-diffusion.cpp/src
)
