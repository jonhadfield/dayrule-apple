import Foundation
import Testing
@testable import Dayrule

struct ClientPlatformTests {
    @Test("client header uses platform kind and build")
    func clientHeader() {
        let header = ClientPlatform.clientHeader(build: "42")
        #expect(header == "\(ClientPlatform.kind)/42")
        #expect(header.hasSuffix("/42"))
        #if os(macOS)
        #expect(ClientPlatform.kind == "macos")
        #expect(ClientPlatform.deviceLabel == "macOS")
        #else
        #expect(ClientPlatform.kind == "ios")
        #expect(ClientPlatform.deviceLabel == "iOS")
        #endif
    }
}
