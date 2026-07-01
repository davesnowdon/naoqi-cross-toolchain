#
# NAO modern cross-toolchain — Atom entry point.
# DO NOT CHANGE LOCATION. DO NOT RENAME.
#
get_filename_component(_ROOT_DIR ${CMAKE_CURRENT_LIST_FILE} PATH)
include("${_ROOT_DIR}/toolchain.cmake")
