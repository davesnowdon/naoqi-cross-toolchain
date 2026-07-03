// say_hello_v6 — NAOqi 2.8 (qi framework) TTS demo for NAO V6.
// The 2.8 C++ API has no ALTextToSpeechProxy on-robot; services are reached via
// qi::Session + AnyObject (dynamic call).  Usage: say_hello_v6 [--qi-url=tcp://IP:9559] [text]
#include <iostream>
#include <string>
#include <qi/applicationsession.hpp>
#include <qi/anyobject.hpp>

int main(int argc, char** argv) {
    qi::ApplicationSession app(argc, argv);         // parses --qi-url
    const std::string text = (argc > 1 && argv[1][0] != '-')
        ? argv[1] : "Hello from the modern NAO 6 toolchain.";
    try {
        app.startSession();
        qi::AnyObject tts = app.session()->service("ALTextToSpeech").value();
        tts.call<void>("say", text);
        std::cout << "[ok] spoke: \"" << text << "\"" << std::endl;
    } catch (const std::exception& e) {
        std::cerr << "[fail] " << e.what() << std::endl;
        return 1;
    }
    return 0;
}
