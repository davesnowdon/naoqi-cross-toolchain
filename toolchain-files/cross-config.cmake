## NAO modern cross-toolchain — CMake toolchain file
## GCC 14 / binutils 2.44, reusing the NAO glibc-2.13 sysroot, Atom (bonnell)
## tuned, defaulting to the old (gcc4-compatible) libstdc++ ABI so output links
## against the bundled NAOqi / boost / Qt / OpenCV libraries.
##
## Regenerated from Aldebaran Robotics' original cross-config.cmake
## (Copyright (C) 2011, 2012 Aldebaran Robotics), modernized for current CMake.

cmake_minimum_required(VERSION 3.5)

set(TARGET_ARCH  "i686")
set(TARGET_TUPLE "${TARGET_ARCH}-aldebaran-linux-gnu")

set(ALDE_CTC_ROOT    "${CMAKE_CURRENT_LIST_DIR}")
set(ALDE_CTC_CROSS   "${ALDE_CTC_ROOT}/cross")
set(ALDE_CTC_SYSROOT "${ALDE_CTC_CROSS}/${TARGET_TUPLE}/sysroot")

# --- Target system -----------------------------------------------------------
set(CMAKE_SYSTEM_NAME       "Linux")
set(CMAKE_SYSTEM_PROCESSOR  "${TARGET_ARCH}")
set(CMAKE_EXECUTABLE_FORMAT "ELF")
set(CMAKE_CROSSCOMPILING    ON)

# Robot marker used by NAOqi CMake modules.
set(I_AM_A_ROBOT ON CACHE BOOL "defined when targeting a robot (ATOM)" FORCE)

# --- Compilers & binutils (modern GCC 14 toolchain) --------------------------
set(_EXT "")
if(WIN32 AND NOT MSVC)
  set(_EXT ".exe")
endif()

set(CMAKE_C_COMPILER   "${ALDE_CTC_CROSS}/bin/${TARGET_TUPLE}-gcc${_EXT}")
set(CMAKE_CXX_COMPILER "${ALDE_CTC_CROSS}/bin/${TARGET_TUPLE}-g++${_EXT}")
set(CMAKE_ASM_COMPILER "${ALDE_CTC_CROSS}/bin/${TARGET_TUPLE}-gcc${_EXT}")
set(CMAKE_AR      "${ALDE_CTC_CROSS}/bin/${TARGET_TUPLE}-ar${_EXT}"      CACHE FILEPATH "" FORCE)
set(CMAKE_RANLIB  "${ALDE_CTC_CROSS}/bin/${TARGET_TUPLE}-ranlib${_EXT}"  CACHE FILEPATH "" FORCE)
set(CMAKE_NM      "${ALDE_CTC_CROSS}/bin/${TARGET_TUPLE}-nm${_EXT}"      CACHE FILEPATH "" FORCE)
set(CMAKE_OBJCOPY "${ALDE_CTC_CROSS}/bin/${TARGET_TUPLE}-objcopy${_EXT}" CACHE FILEPATH "" FORCE)
set(CMAKE_OBJDUMP "${ALDE_CTC_CROSS}/bin/${TARGET_TUPLE}-objdump${_EXT}" CACHE FILEPATH "" FORCE)
set(CMAKE_STRIP   "${ALDE_CTC_CROSS}/bin/${TARGET_TUPLE}-strip${_EXT}"   CACHE FILEPATH "" FORCE)

# NOTE: do NOT set CMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY here. This
# toolchain can fully LINK executables against glibc 2.13 (it just can't RUN
# them on the host), and link-based feature tests such as FindThreads' pthread
# probe must be allowed to link — otherwise -lpthread is silently dropped.

# --- Sysroot & find rules ----------------------------------------------------
set(CMAKE_SYSROOT "${ALDE_CTC_SYSROOT}")
list(INSERT CMAKE_FIND_ROOT_PATH 0 "${ALDE_CTC_ROOT}" "${ALDE_CTC_SYSROOT}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
# BOTH so find_package() also honors CMAKE_PREFIX_PATH for dependencies you
# cross-build into a staging prefix (abseil, protobuf, gRPC, ...).
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH)

# --- Target flags ------------------------------------------------------------
# Atom tuning (-march=bonnell -mtune=bonnell -mfpmath=sse) is already baked into
# the compiler defaults; set explicitly so builds that override CMAKE_*_FLAGS
# keep it. Change OPTIMIZE_FOR_TARGET=GENERIC for portable (non-Atom) i686 code.
if(NOT DEFINED OPTIMIZE_FOR_TARGET)
  set(OPTIMIZE_FOR_TARGET "ATOM")
endif()
if("${OPTIMIZE_FOR_TARGET}" STREQUAL "ATOM")
  set(_ARCH_FLAGS "-m32 -march=bonnell -mtune=bonnell -mfpmath=sse")
else()
  set(_ARCH_FLAGS "-m32 -mtune=generic")
endif()

set(_COMMON_FLAGS "-DI_AM_A_ROBOT ${_ARCH_FLAGS} -pipe -fomit-frame-pointer")

set(CMAKE_C_FLAGS_INIT   "${_COMMON_FLAGS}")
# Old (gcc4-compatible) libstdc++ ABI is the compiler default; assert it here so
# third-party code (gRPC/protobuf/abseil) links against the bundled NAOqi libs.
set(CMAKE_CXX_FLAGS_INIT "${_COMMON_FLAGS} -D_GLIBCXX_USE_CXX11_ABI=0")

set(CMAKE_EXE_LINKER_FLAGS_INIT    "-Wl,--as-needed")
set(CMAKE_MODULE_LINKER_FLAGS_INIT "-Wl,--as-needed")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "-Wl,--as-needed")

# Avoid relinking on install when cross-compiling.
set(CMAKE_BUILD_WITH_INSTALL_RPATH ON)

# pkg-config from the cross toolchain (searches the sysroot).
set(ENV{PKG_CONFIG_SYSROOT_DIR} "${ALDE_CTC_SYSROOT}")
find_program(PKG_CONFIG_EXECUTABLE NAMES "${TARGET_TUPLE}-pkg-config" pkg-config
             PATHS "${ALDE_CTC_CROSS}/bin" NO_DEFAULT_PATH)
