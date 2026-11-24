#if os(macOS)
import Testing
@testable import Dayrule

@Suite("Mac AutoFill password reconcile")
struct MacAutofillPasswordReconcileTests {
    @Test("empty binding clears only when field still matches last binding")
    func explicitClearWhenFieldMatchesLast() {
        let d = MacAutofillPasswordReconcile.decide(
            binding: "",
            field: "old-secret",
            lastBinding: "old-secret",
            editing: false
        )
        #expect(d == .clearField)
    }

    @Test("empty binding harvests AutoFill that replaced the last binding")
    func harvestWhenAutofillInterleaves() {
        let d = MacAutofillPasswordReconcile.decide(
            binding: "",
            field: "autofill-new",
            lastBinding: "old-secret",
            editing: false
        )
        #expect(d == .harvest("autofill-new"))
    }

    @Test("empty binding harvests when there was no prior last binding")
    func harvestWhenNoLastBinding() {
        let d = MacAutofillPasswordReconcile.decide(
            binding: "",
            field: "autofill-only",
            lastBinding: "",
            editing: false
        )
        #expect(d == .harvest("autofill-only"))
    }

    @Test("matching field and binding is synced")
    func syncedWhenEqual() {
        let d = MacAutofillPasswordReconcile.decide(
            binding: "same",
            field: "same",
            lastBinding: "same",
            editing: false
        )
        #expect(d == .synced)
    }

    @Test("non-empty binding pushes into an idle field")
    func pushWhenIdle() {
        let d = MacAutofillPasswordReconcile.decide(
            binding: "from-passwords",
            field: "",
            lastBinding: "",
            editing: false
        )
        #expect(d == .pushToField("from-passwords"))
    }
}
#endif
