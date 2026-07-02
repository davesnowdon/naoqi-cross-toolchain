// grpc_side.cpp — the REAL gRPC client. Compiled -std=c++17 (modern gRPC/abseil
// require it). MUST NOT include any NAOqi/boost header. Linked in place of
// grpc_side_stub.cpp when a target gRPC install (GRPC_ROOT) is available.
//
// Needs the generated stubs from speaker.proto (speaker.pb.h / speaker.grpc.pb.h),
// produced by protoc + grpc_cpp_plugin — build-grpc-naoqi.sh does that codegen.
#include "bridge.h"

#include <memory>
#include <stdexcept>
#include <string>

#include <grpcpp/grpcpp.h>
#include <grpcpp/support/channel_arguments.h>
#include <grpc/impl/channel_arg_names.h>
#include "speaker.pb.h"
#include "speaker.grpc.pb.h"

static_assert(__cplusplus >= 201703L, "compile the gRPC side with -std=c++17");

namespace bridge {

std::string fetch_phrase(const std::string& server_address, const std::string& name) {
    // The NAO V4/V5 kernel (2.6.33) predates SO_REUSEPORT (Linux 3.9); on it the
    // setsockopt returns ENOPROTOOPT. Disable it so gRPC doesn't try — harmless on
    // a modern kernel, required on the robot. See ../../docs/usage.md.
    grpc::ChannelArguments args;
    args.SetInt(GRPC_ARG_ALLOW_REUSEPORT, 0);
    auto channel = grpc::CreateCustomChannel(
        server_address, grpc::InsecureChannelCredentials(), args);
    std::unique_ptr<naodemo::Speaker::Stub> stub = naodemo::Speaker::NewStub(channel);

    naodemo::PhraseRequest request;
    request.set_name(name);
    naodemo::PhraseReply reply;
    grpc::ClientContext context;

    const grpc::Status status = stub->GetPhrase(&context, request, &reply);
    if (!status.ok()) {
        throw std::runtime_error("gRPC GetPhrase failed [code "
            + std::to_string(status.error_code()) + "] " + status.error_message());
    }
    return reply.phrase();
}

}  // namespace bridge
