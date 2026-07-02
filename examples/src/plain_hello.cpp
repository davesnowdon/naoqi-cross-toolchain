// plain_hello.cpp — baseline (no NAOqi).
//
// This proves the modern toolchain's output runs on the robot's Linux userland
// (glibc 2.13, i686 Atom) even when NAOqi is not involved. It uses std::string
// so it also exercises the deployed libstdc++.so.6. Run it on the robot FIRST:
// if this works, the toolchain + runtime libs are good; then try the NAOqi ones.
#include <cstdio>
#include <string>

int main() {
    std::string msg =
        "Hello from the modern NAO cross-toolchain (GCC 14, glibc-2.13 ABI, Atom-tuned).";
    std::printf("%s\n", msg.c_str());
    return 0;
}
