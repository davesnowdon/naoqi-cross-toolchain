// naoqi_side_stub.cpp — the NAOqi side WITHOUT the robot sysroot, so the demo can
// be built and run in CI (which has no NAOqi 2.8 stack). Unlike the naoqi-2.1
// variant there is no <C++17 static_assert: on v6 the whole binary is gnu++17
// (NAOqi 2.8 headers are modern-compiler-friendly; the TU split is kept only for
// header hygiene between gRPC and qi).
//
// The real qi-framework call lives in naoqi_side_v6.cpp (linked when
// ROBOT_SYSROOT is set).
#include "bridge.h"

#include <iostream>
#include <string>

namespace bridge {

void speak(const std::string& text, const std::string& robot_ip, int robot_port) {
    std::cout << "[naoqi-stub] would speak on " << robot_ip << ":" << robot_port
              << " -> \"" << text << "\"" << std::endl;
}

}  // namespace bridge
