import BookLensCodex
import BookLensSupport
import XCTest

final class JSONRPCClientTests: XCTestCase {
    func testRoutesResponseByRequestID() async throws {
        let transport = FixtureCodexTransport(
            responsesByMethod: ["probe": [["ok": true]]]
        )
        let client = JSONRPCClient(transport: transport, defaultTimeout: .seconds(1))
        try await client.start()
        let response = try await client.request(method: "probe", params: [:])
        XCTAssertEqual(response["ok"]?.boolValue, true)
        await client.stop()
    }

    func testRequestTimeoutIsTyped() async throws {
        let transport = FixtureCodexTransport(responsesByMethod: [:])
        let client = JSONRPCClient(transport: transport, defaultTimeout: .milliseconds(50))
        try await client.start()
        do {
            _ = try await client.request(method: "never")
            XCTFail("Expected timeout")
        } catch let error as BookLensError {
            XCTAssertEqual(error.diagnosticCode, "BLX-TIMEOUT-001")
        }
        await client.stop()
    }

    func testNotificationStreamFinishesWhenTransportDisconnects() async throws {
        let transport = FixtureCodexTransport(responsesByMethod: [:])
        let client = JSONRPCClient(transport: transport, defaultTimeout: .seconds(1))
        try await client.start()
        let streamFinished = expectation(description: "Notification stream finished")
        let observer = Task {
            for await _ in client.notifications() {}
            streamFinished.fulfill()
        }

        await transport.disconnect(with: CodexProcessError.exited(status: 1, stderrByteCount: 0))

        await fulfillment(of: [streamFinished], timeout: 1)
        observer.cancel()
        await client.stop()
    }
}
