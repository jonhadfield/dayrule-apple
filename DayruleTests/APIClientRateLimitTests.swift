import Foundation
import Testing
@testable import Dayrule

@Suite("APIClient rate limit")
struct APIClientRateLimitTests {
    @Test func vercelMitigatedHeaderMapsToPlainEnglish() async {
        RateLimitURLProtocol.handler = { req in
            let response = HTTPURLResponse(
                url: req.url!,
                statusCode: 429,
                httpVersion: nil,
                headerFields: [
                    "x-vercel-mitigated": "deny",
                    "Content-Type": "application/json",
                ]
            )!
            return (Data(#"{"error":"blocked","code":"firewall"}"#.utf8), response)
        }
        defer { RateLimitURLProtocol.handler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RateLimitURLProtocol.self]
        let client = APIClient(
            baseURL: URL(string: "https://example.invalid")!,
            build: "1",
            session: URLSession(configuration: config)
        )

        do {
            _ = try await client.raw("GET", path: "api/v1/account")
            Issue.record("expected rate_limited error")
        } catch let err as APIError {
            #expect(
                err == .http(
                    status: 429,
                    code: "rate_limited",
                    message: "Too many attempts from this network. Please wait a while and try again."
                )
            )
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }
}

private final class RateLimitURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Data, HTTPURLResponse))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let (data, response) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
