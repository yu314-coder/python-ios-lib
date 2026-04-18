# torch_ios/cmake/iOS.toolchain.cmake — CMake toolchain file for cross-
# compiling PyTorch libtorch_lite to iOS.
#
# Derived from the one PyTorch shipped in v2.1.2 (cmake/iOS.cmake, removed
# in 2024 with the rest of mobile support), with Xcode 16 / iOS 17 tweaks:
#   - Updated min target to iOS 17 (to match OfflinAi's deployment target)
#   - Added -fvisibility=hidden (smaller static libs)
#   - Use libc++ not libstdc++
#   - Feed -DBLAS=Accelerate down to pytorch's CMake cache
#
# Usage:  cmake ... -DCMAKE_TOOLCHAIN_FILE=/path/to/iOS.toolchain.cmake \
#              -DIOS_PLATFORM=OS -DIOS_ARCH=arm64 -DIOS_DEPLOYMENT_TARGET=17.0

cmake_minimum_required(VERSION 3.27)

# --- Inputs ---------------------------------------------------------------
if(NOT DEFINED IOS_PLATFORM)
    set(IOS_PLATFORM OS)    # OS | SIMULATOR
endif()
if(NOT DEFINED IOS_ARCH)
    set(IOS_ARCH arm64)
endif()
if(NOT DEFINED IOS_DEPLOYMENT_TARGET)
    set(IOS_DEPLOYMENT_TARGET 17.0)
endif()

# --- System -------------------------------------------------------------
# v2.1.2 and its third-party deps (QNNPACK, XNNPACK, onnx) only accept
# CMAKE_SYSTEM_NAME values "Darwin", "Linux", "Android" — they were written
# before CMake's native iOS support landed. We keep "Darwin" and force iOS
# targeting via -target flags in CMAKE_C_FLAGS_INIT below.
set(CMAKE_SYSTEM_NAME   Darwin)
set(CMAKE_SYSTEM_PROCESSOR ${IOS_ARCH})
set(UNIX 1)
set(APPLE 1)
set(IOS 1)

# --- SDK path -----------------------------------------------------------
if(IOS_PLATFORM STREQUAL "OS")
    execute_process(COMMAND xcrun --sdk iphoneos --show-sdk-path
                    OUTPUT_VARIABLE CMAKE_OSX_SYSROOT OUTPUT_STRIP_TRAILING_WHITESPACE)
    set(CMAKE_OSX_ARCHITECTURES ${IOS_ARCH})
    set(TARGET_TRIPLE ${IOS_ARCH}-apple-ios${IOS_DEPLOYMENT_TARGET})
elseif(IOS_PLATFORM STREQUAL "SIMULATOR")
    execute_process(COMMAND xcrun --sdk iphonesimulator --show-sdk-path
                    OUTPUT_VARIABLE CMAKE_OSX_SYSROOT OUTPUT_STRIP_TRAILING_WHITESPACE)
    set(CMAKE_OSX_ARCHITECTURES ${IOS_ARCH})
    set(TARGET_TRIPLE ${IOS_ARCH}-apple-ios${IOS_DEPLOYMENT_TARGET}-simulator)
else()
    message(FATAL_ERROR "IOS_PLATFORM must be OS or SIMULATOR (got '${IOS_PLATFORM}')")
endif()

set(CMAKE_OSX_DEPLOYMENT_TARGET ${IOS_DEPLOYMENT_TARGET})

# --- Compilers ----------------------------------------------------------
execute_process(COMMAND xcrun --sdk iphoneos -f clang
                OUTPUT_VARIABLE CMAKE_C_COMPILER OUTPUT_STRIP_TRAILING_WHITESPACE)
execute_process(COMMAND xcrun --sdk iphoneos -f clang++
                OUTPUT_VARIABLE CMAKE_CXX_COMPILER OUTPUT_STRIP_TRAILING_WHITESPACE)

set(CMAKE_C_COMPILER_WORKS   1)
set(CMAKE_CXX_COMPILER_WORKS 1)

# --- Flags --------------------------------------------------------------
set(CMAKE_C_FLAGS_INIT   "-target ${TARGET_TRIPLE} -fvisibility=hidden")
set(CMAKE_CXX_FLAGS_INIT "-target ${TARGET_TRIPLE} -fvisibility=hidden -fvisibility-inlines-hidden -stdlib=libc++")
set(CMAKE_EXE_LINKER_FLAGS_INIT    "-target ${TARGET_TRIPLE}")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "-target ${TARGET_TRIPLE}")
set(CMAKE_MODULE_LINKER_FLAGS_INIT "-target ${TARGET_TRIPLE}")

# --- Search strategy ----------------------------------------------------
# Don't pick up macOS-arch libs from /usr/local or /opt/homebrew.
set(CMAKE_FIND_ROOT_PATH ${CMAKE_OSX_SYSROOT})
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# --- Hints for PyTorch's own CMake --------------------------------------
# The pytorch tree hard-codes Apple/macOS/iOS detection in many places;
# these vars are what build_ios.sh used in v2.1.2.
set(BLAS "vecLib" CACHE STRING "BLAS backend (Apple name for Accelerate)")
set(USE_BLAS ON CACHE BOOL "")
set(USE_ACCELERATE ON CACHE BOOL "")

# Tell pytorch's Dependencies.cmake we're cross-compiling.
set(CMAKE_CROSSCOMPILING TRUE)

message(STATUS "iOS toolchain: ${TARGET_TRIPLE} @ ${CMAKE_OSX_SYSROOT}")
