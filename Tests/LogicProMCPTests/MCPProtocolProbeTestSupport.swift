import Foundation
import Logging
import MCP
import Testing
@testable import LogicProMCP

actor MCPProtocolProbeTransport: Transport {
    nonisolated let logger = Logger(label: "logic-pro-mcp.test-probe") { _ in SwiftLogNoOpLogHandler() }

    private var continuation: AsyncThrowingStream<Data, Swift.Error>.Continuation?
    private var queuedFrames: [Data] = []
    private var sentFrames: [String] = []

    func connect() async throws {}

    func disconnect() async {
        continuation?.finish()
        continuation = nil
    }

    func send(_ data: Data) async throws {
        sentFrames.append(String(decoding: data, as: UTF8.self))
    }

    func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        AsyncThrowingStream(bufferingPolicy: .unbounded) { continuation in
            self.continuation = continuation
            for frame in queuedFrames {
                continuation.yield(frame)
            }
            queuedFrames.removeAll()
        }
    }

    func queueJSON(_ frame: String) {
        let data = Data(frame.utf8)
        if let continuation {
            continuation.yield(data)
        } else {
            queuedFrames.append(data)
        }
    }

    func frames() -> [String] {
        sentFrames
    }
}

func probeInitializeFrame(id: Int = 1) -> String {
    """
    {"jsonrpc":"2.0","id":\(id),"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"logic-pro-mcp-tests","version":"1.0"}}}
    """
}

func probeRequestFrame(id: Int, method: String, params: String) -> String {
    #"{"jsonrpc":"2.0","id":\#(id),"method":"\#(method)","params":\#(params)}"#
}

func probeToolCallFrame(id: Int, name: String, command: String, params: String = "{}") -> String {
    probeRequestFrame(
        id: id,
        method: "tools/call",
        params: #"{"name":"\#(name)","arguments":{"command":"\#(command)","params":\#(params)}}"#
    )
}

func waitForProbeFrame(
    _ transport: MCPProtocolProbeTransport,
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    matching: ([String: Any]) -> Bool
) async throws -> [String: Any] {
    let intervalNanoseconds: UInt64 = 5_000_000
    var waitedNanoseconds: UInt64 = 0

    while waitedNanoseconds < timeoutNanoseconds {
        for frame in await transport.frames() {
            guard let object = try? JSONSerialization.jsonObject(with: Data(frame.utf8)) as? [String: Any] else {
                continue
            }
            if matching(object) {
                return object
            }
        }
        try await Task.sleep(nanoseconds: intervalNanoseconds)
        waitedNanoseconds += intervalNanoseconds
    }

    Issue.record("Timed out waiting for matching MCP frame")
    return [:]
}

func waitForProbeResponse(
    _ transport: MCPProtocolProbeTransport,
    id: Int,
    timeoutNanoseconds: UInt64 = 1_000_000_000
) async throws -> [String: Any] {
    try await waitForProbeFrame(transport, timeoutNanoseconds: timeoutNanoseconds) { frame in
        frame["id"] as? Int == id
    }
}

func waitForProbeNotification(
    _ transport: MCPProtocolProbeTransport,
    method: String,
    timeoutNanoseconds: UInt64 = 1_000_000_000
) async throws -> [String: Any] {
    try await waitForProbeFrame(transport, timeoutNanoseconds: timeoutNanoseconds) { frame in
        frame["method"] as? String == method
    }
}

func canonicalJSONObjectData(_ object: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}
