// naoqi_side.cpp — the REAL NAOqi side. Compiled -std=gnu++11 (NAOqi 2.1 / boost
// 1.55 headers do not build under C++17). MUST NOT include any gRPC/abseil header.
// Linked in place of naoqi_side_stub.cpp when the NAOqi SDK (CTC) is available.
#include "bridge.h"

#include <stdexcept>
#include <string>

#include <alproxies/altexttospeechproxy.h>
#include <alerror/alerror.h>

static_assert(__cplusplus < 201703L, "compile the NAOqi side with -std=gnu++11");

namespace bridge {

void speak(const std::string& text, const std::string& robot_ip, int robot_port) {
    // Rethrow ALError as std::runtime_error: main.cpp (and bridge.h) are
    // ABI-neutral and must not see any NAOqi type. The std::exception ABI is
    // shared across the whole old-ABI binary, so main's catch matches.
    try {
        AL::ALTextToSpeechProxy tts(robot_ip, robot_port);
        tts.say(text);
    } catch (const AL::ALError& e) {
        throw std::runtime_error(std::string("NAOqi TTS failed: ") + e.what());
    }
}

}  // namespace bridge
