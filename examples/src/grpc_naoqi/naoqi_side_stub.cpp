// naoqi_side_stub.cpp — the NAOqi side WITHOUT the NAOqi SDK, so the coexistence
// can be proven in CI (which has no SDK). Compiled -std=gnu++11 exactly like the
// real naoqi_side.cpp. The static_assert documents/enforces that this TU is built
// with a pre-C++17 standard (as the real NAOqi/boost-1.55 headers require).
//
// The real ALTextToSpeechProxy call lives in naoqi_side.cpp (linked instead when CTC is set).
#include "bridge.h"

#include <iostream>
#include <string>

static_assert(__cplusplus < 201703L, "compile the NAOqi side with -std=gnu++11 (NAOqi/boost 1.55 headers do not build under C++17)");

namespace bridge {

void speak(const std::string& text, const std::string& robot_ip, int robot_port) {
    std::cout << "[naoqi-stub] would speak on " << robot_ip << ":" << robot_port
              << " -> \"" << text << "\"" << std::endl;
}

}  // namespace bridge
