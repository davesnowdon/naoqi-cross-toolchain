#!/bin/sh
# Run a NAO example on the robot.
#
# The examples were built with the modern GCC-14 cross toolchain. Two runtime
# facts drive this launcher:
#   * they need the NEWER libstdc++.so.6 / libgcc_s.so.1 shipped here in ./lib
#     (the robot's stock GCC-4.5-era libstdc++ is too old);
#   * the NAOqi example (say/info) links the NAOqi 2.1 client libs (libqi,
#     libalproxies, boost_*) which are ALREADY on the robot as part of NAOqi.
#
# So we prepend ./lib (new C++ runtime) and then the robot's NAOqi lib dir.
#
# Set NAOQI_LIB to the directory on YOUR robot that contains libqi.so. Find it:
#     find / -name 'libqi.so' 2>/dev/null
# On NAOqi 2.1 robots it is usually /opt/aldebaran/lib .
NAOQI_LIB="${NAOQI_LIB:-/opt/aldebaran/lib}"

HERE="$(cd "$(dirname "$0")" && pwd)"
export LD_LIBRARY_PATH="$HERE/lib:$NAOQI_LIB:$LD_LIBRARY_PATH"

prog="${1:-}"; [ $# -gt 0 ] && shift
case "$prog" in
  plain|plain_hello) exec "$HERE/bin/plain_hello" "$@" ;;
  say|say_hello)     exec "$HERE/bin/say_hello"   "$@" ;;   # [ip] [port] [text]
  info|robot_info)   exec "$HERE/bin/robot_info"  "$@" ;;   # [ip] [port]
  *) echo "usage: $0 {plain|say|info} [args]"
     echo "  plain             - no NAOqi; prints a line (test the toolchain runtime)"
     echo "  say  [ip port txt]- ALTextToSpeechProxy.say  (default 127.0.0.1 9559)"
     echo "  info [ip port]    - ALSystemProxy + TTS getters (read-only)"
     exit 2 ;;
esac
