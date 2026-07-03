# CMake toolchain file for the NAO6 modern toolchain (GCC 14, i686-nao6-linux-gnu,
# glibc 2.28, NEW C++11 ABI, silvermont). Relocatable: paths are derived from this
# file's location at the root of the packaged toolchain directory.
#
#   cmake -DCMAKE_TOOLCHAIN_FILE=/path/to/ctc-linux64-nao6-2.8-modern/cross-config.cmake ..
#
# For NAOqi application builds, point NAO6_APP_SYSROOT at a robot sysroot made by
# sysroot-tools/make-robot-sysroot.sh (adds /opt/aldebaran + boost to the search
# path). Without it you build against the plain glibc-2.28 build sysroot.
get_filename_component(NAO6_CTC_ROOT "${CMAKE_CURRENT_LIST_DIR}" ABSOLUTE)
set(NAO6_TUPLE   "i686-nao6-linux-gnu")
set(NAO6_CROSS   "${NAO6_CTC_ROOT}/cross")
set(NAO6_SYSROOT "${NAO6_CROSS}/${NAO6_TUPLE}/sysroot")

set(CMAKE_SYSTEM_NAME      "Linux")
set(CMAKE_SYSTEM_PROCESSOR "i686")
set(CMAKE_CROSSCOMPILING   ON)

set(CMAKE_C_COMPILER   "${NAO6_CROSS}/bin/${NAO6_TUPLE}-gcc")
set(CMAKE_CXX_COMPILER "${NAO6_CROSS}/bin/${NAO6_TUPLE}-g++")

if(DEFINED ENV{NAO6_APP_SYSROOT})
  set(CMAKE_SYSROOT "$ENV{NAO6_APP_SYSROOT}")
  list(INSERT CMAKE_FIND_ROOT_PATH 0 "$ENV{NAO6_APP_SYSROOT}/opt/aldebaran")
else()
  set(CMAKE_SYSROOT "${NAO6_SYSROOT}")
endif()

list(INSERT CMAKE_FIND_ROOT_PATH 0 "${NAO6_CTC_ROOT}" "${CMAKE_SYSROOT}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH)

# march/mtune=silvermont are the compiler's configured defaults; nothing to add.
