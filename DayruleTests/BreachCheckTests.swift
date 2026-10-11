import Foundation
import Testing
@testable import Dayrule

@Suite("BreachCheck")
struct BreachCheckTests {
    private static let samplePassword = "password"
    private static let hash = BreachCheck.sha1Hex(samplePassword)
    private static var prefix: String { String(hash.prefix(5)) }
    private static var suffix: String { String(hash.dropFirst(5)) }

    @Test func sendsOnlyPrefixWithPadding() async throws {
        let capture = RequestCapture()
        let session = MockURLProtocol.session(handler: { req in
            capture.req = req
            return (Data(), 200)
        })
        _ = await BreachCheck.isBreached(Self.samplePassword, session: session)
        let req = try #require(capture.req)
        #expect(req.url?.absoluteString == BreachCheck.rangeURL + Self.prefix)
        #expect(req.value(forHTTPHeaderField: "Add-Padding") == "true")
        #expect(req.url?.absoluteString.contains(Self.suffix) == false)
    }

    @Test func findsBreachedPasswordInRange() async {
        let session = MockURLProtocol.session(handler: { _ in
            let body = "0018A45C4D1DEF81644B54AB7F969B88D65:1\r\n\(Self.suffix):52256179\r\n"
            return (Data(body.utf8), 200)
        })
        #expect(await BreachCheck.isBreached(Self.samplePassword, session: session))
    }

    @Test func ignoresPaddingLinesWithZeroCount() async {
        let session = MockURLProtocol.session(handler: { _ in
            (Data("\(Self.suffix):0\r\n".utf8), 200)
        })
        #expect(await BreachCheck.isBreached(Self.samplePassword, session: session) == false)
    }

    @Test func passesPasswordNotInRange() async {
        let session = MockURLProtocol.session(handler: { _ in
            (Data("0018A45C4D1DEF81644B54AB7F969B88D65:1\r\n".utf8), 200)
        })
        #expect(await BreachCheck.isBreached(Self.samplePassword, session: session) == false)
    }

    @Test func failsOpenOnErrorResponse() async {
        let session = MockURLProtocol.session(handler: { _ in
            (Data("\(Self.suffix):5".utf8), 503)
        })
        #expect(await BreachCheck.isBreached(Self.samplePassword, session: session) == false)
    }

    @Test func failsOpenWhenNetworkFails() async {
        let session = MockURLProtocol.session(handler: { _ in
            throw URLError(.notConnectedToInternet)
        })
        #expect(await BreachCheck.isBreached(Self.samplePassword, session: session) == false)
    }

    @Test func passwordProblemAndBreachedMessage() async {
        #expect(
            PasswordValidation.passwordProblem(password: "short", confirm: "short")
                == "Use at least 10 characters."
        )
        #expect(
            PasswordValidation.passwordProblem(password: "longenough1", confirm: "longenough2")
                == "The passwords don’t match."
        )
        // Long enough to pass the length rule; response stubbed to the suffix.
        let pw = "password12"
        let suffix = String(BreachCheck.sha1Hex(pw).dropFirst(5))
        let session = MockURLProtocol.session(handler: { _ in
            (Data("\(suffix):1\r\n".utf8), 200)
        })
        let msg = await PasswordValidation.newPasswordProblem(
            password: pw,
            confirm: pw,
            session: session
        )
        #expect(msg == PasswordValidation.breachedMessage)
    }
}

private final class RequestCapture: @unchecked Sendable {
    var req: URLRequest?
}

private enum MockURLProtocol {
    static func session(handler: @escaping @Sendable (URLRequest) throws -> (Data, Int)) -> URLSession {
        MockHandler.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockHandler.self]
        return URLSession(configuration: config)
    }

    private final class MockHandler: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Data, Int))?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let handler = Self.handler else {
                client?.urlProtocol(self, didFailWithError: URLError(.unknown))
                return
            }
            do {
                let (data, status) = try handler(request)
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: status,
                    httpVersion: nil,
                    headerFields: nil
                )!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}
    }
}
