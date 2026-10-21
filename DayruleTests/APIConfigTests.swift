import Foundation
import Testing
@testable import Dayrule

struct APIConfigTests {
    @Test("blank Gate API uses the launch default")
    func emptyFallsBackToDefault() {
        #expect(APIConfig.resolvedBaseURLString("") == APIConfig.defaultBaseURLString)
        #expect(APIConfig.resolvedBaseURLString("   ") == APIConfig.defaultBaseURLString)
        #expect(APIConfig.resolvedBaseURL("")?.absoluteString == APIConfig.defaultBaseURLString)
    }

    @Test("Gate default is production unless DAYRULE_API is set")
    func defaultIsProduction() {
        guard !APIConfig.hasLaunchOverride else { return }
        #expect(APIConfig.defaultBaseURLString == APIConfig.production)
    }

    @Test("a typed override is kept")
    func typedOverride() {
        #expect(APIConfig.resolvedBaseURLString("https://dayrule.app") == "https://dayrule.app")
        #expect(
            APIConfig.resolvedBaseURLString("  http://127.0.0.1:8080  ") == "http://127.0.0.1:8080"
        )
    }
}
