// grpc_side.cpp — the REAL gRPC client. Compiled -std=c++17 (modern gRPC/abseil
// require it). MUST NOT include any NAOqi/boost header. Linked in place of
// grpc_side_stub.cpp when a target gRPC install (GRPC_ROOT) is available.
//
// Needs the generated stubs from speaker.proto (speaker.pb.h / speaker.grpc.pb.h),
// produced by protoc + grpc_cpp_plugin — build-grpc-naoqi.sh does that codegen.
#include "bridge.h"

#include <memory>
#include <string>

#include <grpcpp/grpcpp.h>
#include "speaker.pb.h"
#include "speaker.grpc.pb.h"

static_assert(__cplusplus >= 201703L, "compile the gRPC side with -std=c++17");

namespace bridge {

std::string fetch_phrase(const std::string& server_address, const std::string& name) {
    auto channel = grpc::CreateChannel(server_address, grpc::InsecureChannelCredentials());
    std::unique_ptr<naodemo::Speaker::Stub> stub = naodemo::Speaker::NewStub(channel);

    naodemo::PhraseRequest request;
    request.set_name(name);
    naodemo::PhraseReply reply;
    grpc::ClientContext context;

    const grpc::Status status = stub->GetPhrase(&context, request, &reply);
    if (!status.ok()) {
        return std::string("[gRPC error ") + std::to_string(status.error_code()) + "] "
               + status.error_message();
    }
    return reply.phrase();
}

}  // namespace bridge
