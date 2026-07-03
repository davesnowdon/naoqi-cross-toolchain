// robot_info.cpp — read-only NAOqi example (safe: no movement, no state change).
//
// Exercises two proxies and several return types (std::string, float,
// std::vector<std::string>) across the ABI boundary into the NAOqi SDK libs:
//   ALSystemProxy::robotName(), systemVersion()
//   ALTextToSpeechProxy::getVolume(), getAvailableVoices()
//
// Usage: robot_info [robot-ip] [port]      defaults: 127.0.0.1 9559
#include <iostream>
#include <string>
#include <vector>
#include <cstdlib>

#include <alproxies/alsystemproxy.h>
#include <alproxies/altexttospeechproxy.h>
#include <alerror/alerror.h>

int main(int argc, char* argv[]) {
    const std::string ip   = (argc > 1) ? argv[1] : "127.0.0.1";
    const int         port = (argc > 2) ? std::atoi(argv[2]) : 9559;

    try {
        AL::ALSystemProxy system(ip, port);
        std::cout << "Robot name    : " << system.robotName()     << "\n";
        std::cout << "System version: " << system.systemVersion() << "\n";

        AL::ALTextToSpeechProxy tts(ip, port);
        std::cout << "TTS volume    : " << tts.getVolume()         << "\n";

        std::vector<std::string> voices = tts.getAvailableVoices();
        std::cout << "Voices (" << voices.size() << "):";
        for (std::size_t i = 0; i < voices.size(); ++i)
            std::cout << " " << voices[i];
        std::cout << std::endl;
    } catch (const AL::ALError& e) {
        std::cerr << "NAOqi error: " << e.what() << std::endl;
        return 1;
    }
    return 0;
}
