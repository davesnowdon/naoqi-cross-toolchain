// plain_hello_v6 — no NAOqi; proves a GCC-14 binary runs on the stock NAO6 OS.
#include <iostream>
#include <string>
int main() {
    std::string msg = "Hello from the modern NAO6 toolchain "
                      "(GCC 14, i686/glibc-2.28, new C++ ABI, Silvermont-tuned).";
    std::cout << msg << std::endl;
    return 0;
}
