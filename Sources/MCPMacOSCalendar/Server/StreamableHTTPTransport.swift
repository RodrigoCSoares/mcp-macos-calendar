import Foundation
import Hummingbird
import Logging
import MCP

actor StreamableHTTPTransport: Transport {
    let logger: Logger

    private let host: String
    private let port: Int
    private var app: (any ApplicationProtocol)?
    private let inboundContinuation: AsyncStream<Data>.Continuation
    private let inboundStream: AsyncStream<Data>
    private let sessionId: String
    private let responseStore = ResponseStore()

    init(host: String = "127.0.0.1", port: Int = 8080, logger: Logger = Logger(label: "mcp-macos-calendar.transport")) {
        self.host = host
        self.port = port
        self.logger = logger
        self.sessionId = UUID().uuidString

        var continuation: AsyncStream<Data>.Continuation!
        self.inboundStream = AsyncStream { continuation = $0 }
        self.inboundContinuation = continuation
    }

    func connect() async throws {
        let router = Router()
        let inboundCont = self.inboundContinuation
        let respStore = self.responseStore
        let sessId = self.sessionId

        router.get("/health") { _, _ in
            Response(status: .ok, body: .init(byteBuffer: .init(string: "OK")))
        }

        router.post("/mcp") { request, _ -> Response in
            let body = try await request.body.collect(upTo: 1_048_576)
            let data = Data(buffer: body)

            // Parse just enough to detect notification vs request
            let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let requestId = parsed?["id"]

            if requestId == nil {
                // JSON-RPC notification (no id) — no response expected from server
                inboundCont.yield(data)
                return Response(status: .accepted)
            }

            // JSON-RPC request — register a pending response before yielding
            let responseId = ResponseStore.ResponseId()
            await respStore.register(responseId)
            inboundCont.yield(data)

            let responseData = await respStore.waitForResponse(responseId)
            return Response(
                status: .ok,
                headers: [
                    .contentType: "application/json",
                    .init("Mcp-Session-Id")!: sessId,
                ],
                body: .init(byteBuffer: .init(data: responseData))
            )
        }

        router.delete("/mcp") { _, _ -> Response in
            inboundCont.finish()
            return Response(status: .ok)
        }

        let application = Application(
            router: router,
            configuration: .init(address: .hostname(host, port: port), serverName: "mcp-macos-calendar"),
            logger: logger
        )
        self.app = application

        logger.info("Streamable HTTP transport starting on http://\(host):\(port)/mcp")
        Task.detached { [application] in try await application.run() }
        try await Task.sleep(for: .milliseconds(200))
    }

    func disconnect() async {
        inboundContinuation.finish()
        logger.info("Streamable HTTP transport disconnected")
    }

    func send(_ data: Data) async throws {
        await responseStore.deliverNext(data)
    }

    func receive() -> AsyncThrowingStream<Data, any Error> {
        let stream = self.inboundStream
        return AsyncThrowingStream { continuation in
            Task {
                for await data in stream { continuation.yield(data) }
                continuation.finish()
            }
        }
    }
}

// MARK: - Response Store

// Manages pending HTTP responses for concurrent JSON-RPC requests.
// Each incoming request registers a response slot, and `send()` delivers
// responses in FIFO order (matching the MCP server's sequential processing).
private actor ResponseStore {
    struct ResponseId: Hashable { private let id = UUID() }

    private var pending: [(id: ResponseId, continuation: CheckedContinuation<Data, Never>)] = []
    private var registered: [ResponseId] = []

    func register(_ id: ResponseId) {
        registered.append(id)
    }

    func waitForResponse(_ id: ResponseId) async -> Data {
        await withCheckedContinuation { continuation in
            pending.append((id: id, continuation: continuation))
        }
    }

    func deliverNext(_ data: Data) {
        guard !pending.isEmpty else { return }
        let entry = pending.removeFirst()
        registered.removeAll { $0 == entry.id }
        entry.continuation.resume(returning: data)
    }
}
