#!/bin/sh
# Runner for the NAO6 (Romulus) examples built with the GCC-14 nao6 toolchain.
# Usage:
#   ./run.sh plain                     # no NAOqi needed
#   ./run.sh say  [text]               # robot speaks (NAOqi running, localhost)
#   ./run.sh info                      # read-only robot info
#   ./run.sh grpc <PC_IP:50051> [name] # fetch phrase over gRPC, speak it
#
# The bundled lib/ (newer libstdc++ from GCC 14) must be FIRST on the path;
# everything else (libqi, boost, glibc) is the robot's own.
HERE=$(cd "$(dirname "$0")" && pwd)
export LD_LIBRARY_PATH="$HERE/lib:/opt/aldebaran/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

case "$1" in
  plain) exec "$HERE/bin/plain_hello" ;;
  say)   shift; exec "$HERE/bin/say_hello_v6" "$@" ;;
  info)  shift; exec "$HERE/bin/robot_info_v6" "$@" ;;
  grpc)  shift
         SERVER="${1:?usage: ./run.sh grpc <PC_IP:50051> [name]}"; shift || true
         NAME="${1:-Romulus}"
         exec "$HERE/bin/grpc_naoqi_demo_v6" "$SERVER" 127.0.0.1 9559 "$NAME" ;;
  *)     echo "usage: $0 {plain|say [text]|info|grpc <PC_IP:50051> [name]}" >&2; exit 2 ;;
esac
