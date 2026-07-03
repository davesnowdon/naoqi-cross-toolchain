// robot_info_v6 — read-only NAOqi 2.8 example (safe: no movement, no state change).
// The qi-framework port of the v4/v5 robot_info.cpp: same service methods, reached
// dynamically via qi::AnyObject instead of the specialized proxy classes.
//   ALSystem: robotName(), systemVersion()
//   ALTextToSpeech: getVolume(), getAvailableVoices()
//
// Usage: robot_info_v6 [--qi-url=tcp://IP:9559]
#include <iostream>
#include <string>
#include <vector>

#include <qi/applicationsession.hpp>
#include <qi/anyobject.hpp>

int main(int argc, char** argv) {
    qi::ApplicationSession app(argc, argv);       // parses --qi-url
    try {
        app.startSession();

        qi::AnyObject sys = app.session()->service("ALSystem").value();
        std::cout << "Robot name    : " << sys.call<std::string>("robotName")     << "\n";
        std::cout << "System version: " << sys.call<std::string>("systemVersion") << "\n";

        qi::AnyObject tts = app.session()->service("ALTextToSpeech").value();
        std::cout << "TTS volume    : " << tts.call<float>("getVolume")           << "\n";

        std::vector<std::string> voices =
            tts.call<std::vector<std::string> >("getAvailableVoices");
        std::cout << "Voices (" << voices.size() << "):";
        for (std::size_t i = 0; i < voices.size(); ++i) std::cout << " " << voices[i];
        std::cout << std::endl;
    } catch (const std::exception& e) {
        std::cerr << "NAOqi error: " << e.what() << std::endl;
        return 1;
    }
    return 0;
}
