cmake_minimum_required(VERSION 3.5.0)
project(mnnllm)

set(NATIVE_ROOT ${CMAKE_CURRENT_SOURCE_DIR})
set(PREBUILT_DIR ${NATIVE_ROOT}/../../../../prebuilt/harmony)

add_library(mnnllm SHARED
    mnn_llm.cpp
)

target_include_directories(mnnllm PRIVATE
    ${PREBUILT_DIR}/include
)

# 链接 libMNN（LLM 已链入）+ NAPI 运行时（完整路径，避免搜索路径问题）
set(NAPI_LIB /Users/mike/Library/OpenHarmony/Sdk/HarmonyOS-6.1.1/openharmony/native/sysroot/usr/lib/aarch64-linux-ohos/libace_napi.z.so)
set(HILOG_LIB /Users/mike/Library/OpenHarmony/Sdk/HarmonyOS-6.1.1/openharmony/native/sysroot/usr/lib/aarch64-linux-ohos/libhilog_ndk.z.so)
target_link_libraries(mnnllm
    ${PREBUILT_DIR}/libs/libMNN.so
    ${PREBUILT_DIR}/libs/libc++_shared.so
    ${NAPI_LIB}
    ${HILOG_LIB}
)

target_compile_options(mnnllm PRIVATE -fexceptions -frtti -fvisibility=hidden)

# 去除 RUNPATH（避免指向本地构建路径，设备上无法解析；依赖库随 HAP 打包到标准 libs 目录）
set_target_properties(mnnllm PROPERTIES
    BUILD_RPATH ""
    INSTALL_RPATH ""
    SKIP_BUILD_RPATH TRUE
)
