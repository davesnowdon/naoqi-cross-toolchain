// naoqi_side_v6.cpp — the NAOqi side of the bridge for NAO6 / NAOqi 2.8.
// Implements bridge::speak() via the qi framework (the 2.8 C++ API) instead of
// ALTextToSpeechProxy (whose headers are not shipped on the 2.8 robot).
//
// On v6 this can share a -std=gnu++17 build with the gRPC side — NAOqi 2.8's
// headers are modern-compiler-friendly, unlike 2.1's boost-1.55 headers. The
// bridge split is kept for header hygiene (gRPC and qi never meet in one TU).
#include "bridge.h"

#include <sstream>
#include <stdexcept>
#include <string>

#include <qi/application.hpp>
#include <qi/session.hpp>
#include <qi/anyobject.hpp>

namespace {
// qi needs a qi::Application for its event loop; construct one lazily with
// synthetic argv (main.cpp is ABI/framework-neutral and cannot provide it).
void ensure_qi_app() {
    static int argc = 1;
    static char arg0[] = "grpc_naoqi_v6";
    static char* argv_arr[] = { arg0, nullptr };
    static char** argv = argv_arr;
    static qi::Application app(argc, argv);
    (void)app;
}
}  // namespace

namespace bridge {

void speak(const std::string& text, const std::string& robot_ip, int robot_port) {
    ensure_qi_app();
    std::ostringstream url;
    url << "tcp://" << robot_ip << ":" << robot_port;
    try {
        qi::Session session;
        session.connect(url.str()).value();          // throws on failure
        qi::AnyObject tts = session.service("ALTextToSpeech").value();
        tts.call<void>("say", text);
        session.close();
    } catch (const std::exception& e) {
        throw std::runtime_error(std::string("NAOqi 2.8 TTS failed: ") + e.what());
    }
}

}  // namespace bridge
