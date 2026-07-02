// grpc_naoqi demo — orchestration only. Includes the ABI-neutral bridge, never
// gRPC or NAOqi headers directly. The flow: fetch a phrase over gRPC, then speak
// it on the robot via NAOqi.
//
// Usage: grpc_naoqi_demo [grpc_server host:port] [robot_ip] [robot_port] [name]
//   defaults: 127.0.0.1:50051  127.0.0.1  9559  NAO
#include <iostream>
#include <string>
#include <cstdlib>

#include "bridge.h"

int main(int argc, char** argv) {
    const std::string grpc_server = (argc > 1) ? argv[1] : "127.0.0.1:50051";
    const std::string robot_ip    = (argc > 2) ? argv[2] : "127.0.0.1";
    const int         robot_port  = (argc > 3) ? std::atoi(argv[3]) : 9559;
    const std::string name        = (argc > 4) ? argv[4] : "NAO";

    std::cout << "[main] fetching phrase from gRPC server " << grpc_server << " ...\n";
    const std::string phrase = bridge::fetch_phrase(grpc_server, name);

    std::cout << "[main] got phrase: \"" << phrase << "\"\n";
    std::cout << "[main] speaking it on robot " << robot_ip << ":" << robot_port << " ...\n";
    bridge::speak(phrase, robot_ip, robot_port);

    return 0;
}
