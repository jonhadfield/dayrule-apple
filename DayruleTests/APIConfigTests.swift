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

    @Test("DAYRULE_API is ignored outside Debug")
    func launchOverrideMatchesConfiguration() {
        #if DEBUG
        if APIConfig.hasLaunchOverride {
            #expect(!APIConfig.defaultBaseURLString.isEmpty)
        } else {
            #expect(APIConfig.defaultBaseURLString == APIConfig.production)
        }
        #else
        let prev = ProcessInfo.processInfo.environment["DAYRULE_API"]
        setenv("DAYRULE_API", "http://127.0.0.1:8080", 1)
        defer {
            if let prev {
                setenv("DAYRULE_API", prev, 1)
            } else {
                unsetenv("DAYRULE_API")
            }
        }
        #expect(!APIConfig.hasLaunchOverride)
        #expect(APIConfig.defaultBaseURLString == APIConfig.production)
        #expect(APIConfig.resolvedBaseURLString("") == APIConfig.production)
        #endif
    }

    @Test("a typed override is kept")
    func typedOverride() {
        #expect(APIConfig.resolvedBaseURLString("https://dayrule.app") == "https://dayrule.app")
        #expect(
            APIConfig.resolvedBaseURLString("  http://127.0.0.1:8080  ") == "http://127.0.0.1:8080"
        )
    }
}
