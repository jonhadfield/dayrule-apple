#if os(macOS)
import AppKit
import SwiftUI

/// Which AppKit credential field should become first responder.
enum MacAutofillFocusTarget: Equatable {
    case email
    case password
}

/// AppKit username + password so macOS Passwords AutoFill can write both values.
/// SwiftUI `SecureField` often never receives the password; a lone
/// `NSSecureTextField` representable also loses it when email’s binding update
/// re-enters `updateNSView` and pushes the still-empty password binding back
/// into the field (wiping AutoFill). One representable owns both fields and
/// never clobbers a non-empty field with an empty binding — except intentional
/// clears after a failed unlock.
struct MacAutofillCredentialFields: NSViewRepresentable {
    @Binding var email: String
    @Binding var password: String
    var colors: DayruleColors
    var isEnabled: Bool = true
    /// Bumped when Fill from Passwords (or similar) writes both bindings so
    /// reconcile treats that pair as authoritative even with an active editor.
    var credentialsApplyNonce: Int = 0
    var focusTarget: MacAutofillFocusTarget? = nil
    var onSubmitPassword: (() -> Void)?

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: MacAutofillCredentialFields
        weak var emailField: NSTextField?
        weak var passwordField: NSSecureTextField?
        private var harvestTask: Task<Void, Never>?
        /// Last password binding we pushed to / accepted from the field.
        var lastPasswordBinding: String = ""
        var appliedCredentialsNonce: Int = 0
        var lastFocusTarget: MacAutofillFocusTarget?

        init(_ parent: MacAutofillCredentialFields) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            if field === emailField {
                if parent.email != field.stringValue {
                    parent.email = field.stringValue
                }
                schedulePasswordHarvest()
            } else if field === passwordField {
                if parent.password != field.stringValue {
                    parent.password = field.stringValue
                    lastPasswordBinding = field.stringValue
                }
            }
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            harvestPasswordFromField()
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if control === emailField {
                    passwordField?.window?.makeFirstResponder(passwordField)
                    return true
                }
                if control === passwordField {
                    parent.onSubmitPassword?()
                    return true
                }
            }
            return false
        }

        func schedulePasswordHarvest() {
            harvestTask?.cancel()
            harvestTask = Task { [weak self] in
                self?.harvestPasswordFromField()
                try? await Task.sleep(for: .milliseconds(50))
                self?.harvestPasswordFromField()
                try? await Task.sleep(for: .milliseconds(150))
                self?.harvestPasswordFromField()
            }
        }

        func harvestPasswordFromField() {
            guard let field = passwordField else { return }
            let value = field.stringValue
            if !value.isEmpty, parent.password != value {
                parent.password = value
                lastPasswordBinding = value
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSStackView {
        let emailField = makeWrappedField(
            placeholder: "Email",
            contentType: .username,
            secure: false,
            colors: colors
        )
        let passwordField = makeWrappedField(
            placeholder: "Password",
            contentType: .password,
            secure: true,
            colors: colors
        )

        let emailTF = emailField.textField
        let passwordTF = passwordField.textField as! NSSecureTextField
        emailTF.delegate = context.coordinator
        passwordTF.delegate = context.coordinator
        emailTF.stringValue = email
        passwordTF.stringValue = password
        emailTF.setAccessibilityIdentifier("gate.email")
        passwordTF.setAccessibilityIdentifier("gate.password")
        applyEnabled(emailTF, passwordTF)

        context.coordinator.emailField = emailTF
        context.coordinator.passwordField = passwordTF
        context.coordinator.parent = self
        context.coordinator.lastPasswordBinding = password

        let stack = NSStackView(views: [emailField.container, passwordField.container])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 16
        stack.distribution = .fill
        return stack
    }

    func updateNSView(_ stack: NSStackView, context: Context) {
        context.coordinator.parent = self
        guard let emailField = context.coordinator.emailField,
              let passwordField = context.coordinator.passwordField
        else { return }

        if credentialsApplyNonce != context.coordinator.appliedCredentialsNonce {
            emailField.stringValue = email
            passwordField.stringValue = password
            context.coordinator.lastPasswordBinding = password
            context.coordinator.appliedCredentialsNonce = credentialsApplyNonce
            // Setting stringValue aborts editing; allow a fresh .password focus.
            context.coordinator.lastFocusTarget = nil
            if emailField.currentEditor() != nil || passwordField.currentEditor() != nil {
                stack.window?.makeFirstResponder(nil)
            }
        } else {
            reconcileEmail(emailField, coordinator: context.coordinator)
            reconcilePassword(passwordField, coordinator: context.coordinator)
            context.coordinator.harvestPasswordFromField()
        }

        applyEnabled(emailField, passwordField)
        emailField.contentType = .username
        passwordField.contentType = .password
        restyleContainers(in: stack, colors: colors)
        applyFocusIfNeeded(coordinator: context.coordinator, emailField: emailField, passwordField: passwordField)
    }

    private func reconcileEmail(_ field: NSTextField, coordinator: Coordinator) {
        if field.stringValue == email { return }
        if field.currentEditor() != nil {
            // Prefer an external non-empty binding (Fill from Passwords) over
            // stale editor text so email/password stay a matched pair.
            if !email.isEmpty, email != field.stringValue {
                field.stringValue = email
                return
            }
            if field.stringValue != email {
                email = field.stringValue
            }
            return
        }
        field.stringValue = email
    }

    private func reconcilePassword(_ field: NSTextField, coordinator: Coordinator) {
        switch MacAutofillPasswordReconcile.decide(
            binding: password,
            field: field.stringValue,
            lastBinding: coordinator.lastPasswordBinding,
            editing: field.currentEditor() != nil
        ) {
        case .synced:
            coordinator.lastPasswordBinding = password
        case .clearField:
            field.stringValue = ""
            coordinator.lastPasswordBinding = ""
        case .harvest(let value):
            password = value
            coordinator.lastPasswordBinding = value
        case .pushToField(let value):
            field.stringValue = value
            coordinator.lastPasswordBinding = value
        case .acceptFromEditor(let value):
            password = value
            coordinator.lastPasswordBinding = value
        }
    }

    private func applyFocusIfNeeded(
        coordinator: Coordinator,
        emailField: NSTextField,
        passwordField: NSSecureTextField
    ) {
        guard let target = focusTarget else {
            // Clear so returning to .email / .password is not suppressed.
            coordinator.lastFocusTarget = nil
            return
        }
        guard target != coordinator.lastFocusTarget else { return }
        coordinator.lastFocusTarget = target
        let field: NSTextField = target == .email ? emailField : passwordField
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
        }
    }

    private func applyEnabled(_ emailField: NSTextField, _ passwordField: NSTextField) {
        emailField.isEnabled = isEnabled
        emailField.isEditable = isEnabled
        passwordField.isEnabled = isEnabled
        passwordField.isEditable = isEnabled
        emailField.alphaValue = isEnabled ? 1 : 0.5
        passwordField.alphaValue = isEnabled ? 1 : 0.5
        emailField.superview?.alphaValue = isEnabled ? 1 : 0.5
        passwordField.superview?.alphaValue = isEnabled ? 1 : 0.5
    }

    private struct WrappedField {
        var container: NSView
        var textField: NSTextField
    }

    private func makeWrappedField(
        placeholder: String,
        contentType: NSTextContentType,
        secure: Bool,
        colors: DayruleColors
    ) -> WrappedField {
        let field: NSTextField = secure
            ? NSSecureTextField(frame: .zero)
            : NSTextField(frame: .zero)
        field.placeholderString = placeholder
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: 15)
        field.textColor = NSColor.labelColor
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.contentType = contentType
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let box = PaperFieldBox(colors: colors)
        box.addSubview(field)
        field.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            field.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
            field.topAnchor.constraint(equalTo: box.topAnchor, constant: 14),
            field.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -14),
            box.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
        ])
        return WrappedField(container: box, textField: field)
    }

    private func restyleContainers(in stack: NSStackView, colors: DayruleColors) {
        for view in stack.arrangedSubviews {
            (view as? PaperFieldBox)?.apply(colors: colors)
        }
    }
}

/// Paper chrome matching `DayruleFieldModifier` (sidebar fill + field border).
private final class PaperFieldBox: NSView {
    private let fillLayer = CALayer()
    private let borderLayer = CALayer()

    init(colors: DayruleColors) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(fillLayer)
        layer?.addSublayer(borderLayer)
        apply(colors: colors)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        fillLayer.frame = bounds
        borderLayer.frame = bounds
        let radius = Tokens.radiusCard
        fillLayer.cornerRadius = radius
        borderLayer.cornerRadius = radius
        borderLayer.borderWidth = 1
    }

    func apply(colors: DayruleColors) {
        fillLayer.backgroundColor = NSColor(colors.sidebar).cgColor
        borderLayer.borderColor = NSColor(colors.fieldBorder).cgColor
        borderLayer.backgroundColor = NSColor.clear.cgColor
        needsLayout = true
    }
}

/// Pure password reconcile for Mac AutoFill vs explicit clear (audit run-4).
enum MacAutofillPasswordReconcile {
    enum Decision: Equatable {
        case synced
        case clearField
        case harvest(String)
        case pushToField(String)
        case acceptFromEditor(String)
    }

    /// Decide how to reconcile the SwiftUI password binding with the AppKit field.
    /// Explicit clear (`binding == ""`) only blanks the field when it still shows
    /// `lastBinding`; a newer AutoFill value is harvested instead.
    static func decide(
        binding: String,
        field: String,
        lastBinding: String,
        editing: Bool
    ) -> Decision {
        if field == binding { return .synced }
        if binding.isEmpty, !field.isEmpty {
            if !lastBinding.isEmpty, field == lastBinding {
                return .clearField
            }
            return .harvest(field)
        }
        if editing {
            if !binding.isEmpty, binding != field {
                return .pushToField(binding)
            }
            if field != binding {
                return .acceptFromEditor(field)
            }
            return .synced
        }
        return .pushToField(binding)
    }
}
#endif
