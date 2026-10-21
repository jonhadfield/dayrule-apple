import Foundation
import Testing

struct ATSLocalNetworkingTests {
    @Test("Info.plist allows local HTTP only in Debug")
    func localNetworkingMatchesConfiguration() {
        let ats = Bundle.main.object(forInfoDictionaryKey: "NSAppTransportSecurity") as? [String: Any]
        let allowsLocal = ats?["NSAllowsLocalNetworking"] as? Bool ?? false
        #if DEBUG
        #expect(allowsLocal)
        #else
        #expect(!allowsLocal)
        #endif
    }
}
