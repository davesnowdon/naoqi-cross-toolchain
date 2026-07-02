// grpc_side_stub.cpp — the gRPC side WITHOUT the gRPC stack, so the C++17 <-> gnu++11
// coexistence can be proven in CI (which has no gRPC). It is compiled -std=c++17
// exactly like the real grpc_side.cpp, and deliberately uses genuine C++17 features
// so it would FAIL under gnu++11 — that is the whole point of splitting the module.
//
// The real gRPC client lives in grpc_side.cpp (linked instead when GRPC_ROOT is set).
#include "bridge.h"

#include <string>
#include <string_view>   // C++17
#include <utility>

static_assert(__cplusplus >= 201703L, "compile the gRPC side with -std=c++17");

namespace bridge {

std::string fetch_phrase(const std::string& server_address, const std::string& name) {
    // Genuine C++17 so this TU cannot be built as gnu++11:
    constexpr std::string_view kPrefix = "Hello ";
    auto [head, tail] = std::pair{std::string(kPrefix), std::string(", this string crossed the C++17/gnu++11 boundary.")};
    if constexpr (sizeof(void*) >= 4) {
        return head + name + tail + " (stub; real build fetches it from " + server_address + " via gRPC)";
    } else {
        return head + name + tail;
    }
}

}  // namespace bridge
