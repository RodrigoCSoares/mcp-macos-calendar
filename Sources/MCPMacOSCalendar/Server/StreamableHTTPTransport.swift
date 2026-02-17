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
            inboundCont.yield(Data(buffer: body))

            let responseData = await respStore.waitForResponse()
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
        await responseStore.setResponse(data)
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

private actor ResponseStore {
    private var responseContinuation: CheckedContinuation<Data, Never>?

    func waitForResponse() async -> Data {
        await withCheckedContinuation { continuation in
            self.responseContinuation = continuation
        }
    }

    func setResponse(_ data: Data) {
        responseContinuation?.resume(returning: data)
        responseContinuation = nil
    }
}
