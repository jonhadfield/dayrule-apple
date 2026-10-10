import Foundation
import Testing
@testable import Dayrule

struct LoginResponseTests {
    @Test("decodes secondStep without crashing")
    func secondStep() throws {
        let json = """
        {"secondStep":{"token":"abc","methods":["passkey","totp"]}}
        """.data(using: .utf8)!
        let login = try JSONDecoder().decode(LoginResponse.self, from: json)
        #expect(login.token == nil)
        #expect(login.secondStep?.token == "abc")
        #expect(login.secondStep?.methods.contains("passkey") == true)
        #expect(login.secondStep?.methods.contains("totp") == true)
    }

    @Test("decodes native login with token")
    func nativeToken() throws {
        let json = """
        {"userId":"6f1d2c3b-4a59-4e6f-8a7b-9c0d1e2f3a4b","token":"sess","salt":"AA==","kdf":{"v":1,"ops":3,"mem":67108864},"wrappedPassword":{"nonce":"n","ciphertext":"c"}}
        """.data(using: .utf8)!
        let login = try JSONDecoder().decode(LoginResponse.self, from: json)
        #expect(login.token == "sess")
        #expect(login.secondStep == nil)
        #expect(login.userId == "6f1d2c3b-4a59-4e6f-8a7b-9c0d1e2f3a4b")
    }
}
