#ifndef GRPC_NAOQI_BRIDGE_H
#define GRPC_NAOQI_BRIDGE_H
//
// ABI-neutral boundary between the two module-sets that cannot share a
// translation unit:
//   * the gRPC side is compiled -std=c++17 (modern gRPC/abseil require it);
//   * the NAOqi side is compiled -std=gnu++11 (NAOqi 2.1 / boost 1.55 headers
//     do NOT compile under C++17).
//
// This header must compile under BOTH standards, so it uses only plain types.
// std::string is safe to pass across the boundary because the WHOLE binary is
// built with the old libstdc++ ABI (_GLIBCXX_USE_CXX11_ABI=0, the toolchain
// default) — so std::string has one identical layout in every TU.
//
#include <string>

namespace bridge {

// Implemented by the gRPC side (grpc_side.cpp / grpc_side_stub.cpp, -std=c++17):
// fetch a phrase from a gRPC server. server_address is "host:port".
// THROWS std::runtime_error if the RPC fails (so a failed fetch is a failed test,
// not a success that speaks an error string). std::exception crosses the boundary
// safely: the whole binary shares one old-ABI libstdc++.
std::string fetch_phrase(const std::string& server_address, const std::string& name);

// Implemented by the NAOqi side (naoqi_side.cpp / naoqi_side_stub.cpp, -std=gnu++11):
// speak text on the robot via ALTextToSpeechProxy.
// THROWS std::runtime_error if TTS fails (e.g. NAOqi unreachable).
void speak(const std::string& text, const std::string& robot_ip, int robot_port);

}  // namespace bridge

#endif  // GRPC_NAOQI_BRIDGE_H
