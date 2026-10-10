import Testing
@testable import Dayrule

@Suite("UuidV5")
struct UuidV5Tests {
    @Test func matchesPythonUuid5ForInstanceNamespace() {
        #expect(UuidV5.generate(name: "tpl/2026-10-04") == "3b67d204-bea7-590f-9c15-dd5cf881e088")
        #expect(
            UuidV5.generate(name: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/2026-10-04")
                == "97f3afa8-2a8b-5168-ac34-5597ca97b2d5"
        )
        #expect(Repeats.instanceId(templateId: "tpl", date: "2026-10-04") == "3b67d204-bea7-590f-9c15-dd5cf881e088")
    }
}
