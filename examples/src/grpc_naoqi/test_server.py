#!/usr/bin/env python3
"""Tiny gRPC test server for the grpc_naoqi demo — run this on your PC.

The target-built `grpc_naoqi_demo` (running on the robot, or here under the
toolchain loader) connects to it and fetches a phrase, which it then speaks.

Requires:  pip install grpcio grpcio-tools
Run:       python3 test_server.py [host:port]     (default 0.0.0.0:50051)

It self-generates the Python stubs from speaker.proto on first run.
"""
import os
import sys
import subprocess
from concurrent import futures

HERE = os.path.dirname(os.path.abspath(__file__))

# Generate speaker_pb2{,_grpc}.py from speaker.proto if missing.
if not os.path.exists(os.path.join(HERE, "speaker_pb2_grpc.py")):
    subprocess.check_call([
        sys.executable, "-m", "grpc_tools.protoc",
        "-I", HERE, "--python_out", HERE, "--grpc_python_out", HERE,
        os.path.join(HERE, "speaker.proto"),
    ])

sys.path.insert(0, HERE)
import grpc                     # noqa: E402
import speaker_pb2              # noqa: E402
import speaker_pb2_grpc         # noqa: E402


class Speaker(speaker_pb2_grpc.SpeakerServicer):
    def GetPhrase(self, request, context):
        phrase = "Hello {}. This sentence was fetched over gRPC and spoken by NAOqi.".format(
            request.name or "NAO")
        print("[server] GetPhrase(name=%r) -> %r" % (request.name, phrase))
        return speaker_pb2.PhraseReply(phrase=phrase)


def main():
    addr = sys.argv[1] if len(sys.argv) > 1 else "0.0.0.0:50051"
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=4))
    speaker_pb2_grpc.add_SpeakerServicer_to_server(Speaker(), server)
    server.add_insecure_port(addr)
    server.start()
    print("[server] Speaker listening on %s (Ctrl-C to stop)" % addr)
    server.wait_for_termination()


if __name__ == "__main__":
    main()
