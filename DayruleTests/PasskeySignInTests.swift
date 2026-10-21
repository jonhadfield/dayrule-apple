import Foundation
import Testing
@testable import Dayrule

struct PasskeySignInTests {
    @Test("omitted rpId is dayrule.app")
    func omittedRpId() throws {
        #expect(try PasskeySignIn.relyingPartyId(in: [:]) == PasskeyPRF.relyingPartyId)
    }

    @Test("dayrule.app rpId is accepted")
    func matchingRpId() throws {
        #expect(try PasskeySignIn.relyingPartyId(in: ["rpId": "dayrule.app"]) == "dayrule.app")
    }

    @Test("foreign rpId is refused")
    func foreignRpId() {
        #expect(throws: PasskeySignIn.Error.badOptions) {
            try PasskeySignIn.relyingPartyId(in: ["rpId": "evil.example"])
        }
    }

    @Test("omitted allowCredentials is discoverable")
    func omittedAllowList() throws {
        #expect(try PasskeySignIn.allowedCredentialIDs(in: [:]) == nil)
    }

    @Test("a usable allowCredentials id is kept")
    func decodedAllowList() throws {
        let ids = try PasskeySignIn.allowedCredentialIDs(in: [
            "allowCredentials": [["id": "AQID", "type": "public-key"]],
        ])
        #expect(ids == [Data([1, 2, 3])])
    }

    @Test("empty or undecodable allowCredentials is refused")
    func emptyAllowList() {
        #expect(throws: PasskeySignIn.Error.badOptions) {
            try PasskeySignIn.allowedCredentialIDs(in: ["allowCredentials": [] as [[String: Any]]])
        }
        #expect(throws: PasskeySignIn.Error.badOptions) {
            try PasskeySignIn.allowedCredentialIDs(in: [
                "allowCredentials": [["id": ""]],
            ])
        }
        #expect(throws: PasskeySignIn.Error.badOptions) {
            try PasskeySignIn.allowedCredentialIDs(in: ["allowCredentials": "nope"])
        }
    }
}
