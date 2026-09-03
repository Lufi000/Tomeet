import Foundation
import Testing
@testable import Tomeet

// MockURLProtocol.handler 是全局可变状态,Swift Testing 默认并行,需串行化。
@Suite(.serialized)
struct QuotaServiceTests {
    @MainActor
    private func makeService(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> QuotaService {
        let baseURL = URL(string: "https://example.com/v1/quota")!
        MockURLProtocol.setHandler(handler, for: baseURL)
        return QuotaService(
            baseURL: baseURL,
            appToken: "test-token",
            deviceID: "test-device",
            session: MockURLProtocol.makeSession()
        )
    }

    @MainActor
    @Test func refreshParsesRemainingAndResetAt() async {
        let service = makeService { request in
            #expect(request.value(forHTTPHeaderField: "X-App-Token") == "test-token")
            #expect(request.value(forHTTPHeaderField: "X-Device-ID") == "test-device")
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            let body = #"{"remaining":7,"resetAt":"2026-09-03T00:00:00+08:00"}"#
            return (response, Data(body.utf8))
        }
        await service.refresh()
        #expect(service.remaining == 7)
        #expect(service.resetAt != nil)
        #expect(!service.isExhausted)
    }

    @MainActor
    @Test func refreshFailureKeepsUnknownState() async {
        let service = makeService { _ in throw URLError(.notConnectedToInternet) }
        await service.refresh()
        #expect(service.remaining == nil)
        #expect(!service.isExhausted)
    }

    @MainActor
    @Test func noteRemainingUpdatesValue() {
        let service = makeService { _ in throw URLError(.unknown) }
        service.noteRemaining(3)
        #expect(service.remaining == 3)
        #expect(!service.isExhausted)
        service.noteRemaining(0)
        #expect(service.isExhausted)
    }

    @MainActor
    @Test func noteExhaustedMarksExhaustedAndKeepsResetAt() {
        let service = makeService { _ in throw URLError(.unknown) }
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        service.noteExhausted(resetAt: date)
        #expect(service.isExhausted)
        #expect(service.resetAt == date)
    }
}
