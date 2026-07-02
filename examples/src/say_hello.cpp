// say_hello.cpp — the canonical NAOqi C++ example: make the robot speak.
//
// Uses the specialized ALTextToSpeechProxy (compile-time type-checked) from the
// NAOqi 2.1 C++ SDK. Connects to a running naoqi over TCP. Run it ON the robot
// (IP 127.0.0.1) or from a PC pointed at the robot's IP.
//
// Usage: say_hello [robot-ip] [port] [text]
//   defaults: 127.0.0.1  9559  "Hello world..."
#include <iostream>
#include <string>
#include <cstdlib>

#include <alproxies/altexttospeechproxy.h>
#include <alerror/alerror.h>

int main(int argc, char* argv[]) {
    const std::string ip   = (argc > 1) ? argv[1] : "127.0.0.1";
    const int         port = (argc > 2) ? std::atoi(argv[2]) : 9559;
    const std::string text = (argc > 3) ? argv[3]
        : "Hello world. I was built with the modern cross toolchain.";

    try {
        AL::ALTextToSpeechProxy tts(ip, port);
        tts.say(text);
    } catch (const AL::ALError& e) {
        std::cerr << "NAOqi error: " << e.what() << std::endl;
        return 1;
    }
    return 0;
}
