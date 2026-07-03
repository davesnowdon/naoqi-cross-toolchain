## NAO modern cross-toolchain — top-level toolchain file for use WITHOUT qibuild
## (or with). Include this as CMAKE_TOOLCHAIN_FILE. It pulls in cross-config.cmake
## and, if qibuild is installed, its CMake integration.
##
## Based on Aldebaran Robotics' original toolchain.cmake (C) 2011-2012.
## DO NOT change location relative to cross-config.cmake.

get_filename_component(_ROOT_DIR ${CMAKE_CURRENT_LIST_FILE} PATH)
include(${_ROOT_DIR}/cross-config.cmake)

# Legacy OpenEmbedded marker kept for compatibility with old NAO CMake modules.
set(OE_CROSS_BUILD ON)

# qibuild is optional: only wire it in if present, so the toolchain also works
# as a plain CMAKE_TOOLCHAIN_FILE for modern software (gRPC, protobuf, ...).
find_package(qibuild QUIET)
