#if os(macOS)
import AppKit
import SwiftUI

/// AppKit username + password so macOS Passwords AutoFill can write both values.
/// SwiftUI `SecureField` often never receives the password; a lone
/// `NSSecureTextField` representable also loses it when email’s binding update
/// re-enters `updateNSView` and pushes the still-empty password binding back
/// into the field (wiping AutoFill). One representable owns both fields and
/// never clobbers a non-empty field with an empty binding.
struct MacAutofillCredentialFields: NSViewRepresentable {
    @Binding var email: String
    @Binding var password: String
    var colors: DayruleColors
    var isEnabled: Bool = true
    var onSubmitPassword: (() -> Void)?

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: MacAutofillCredentialFields
        weak var emailField: NSTextField?
        weak var passwordField: NSSecureTextField?
        private var harvestTask: Task<Void, Never>?

        init(_ parent: MacAutofillCredentialFields) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            if field === emailField {
                if parent.email != field.stringValue {
                    parent.email = field.stringValue
                }
                // Passwords often writes the secure field just after the username.
                schedulePasswordHarvest()
            } else if field === passwordField {
                if parent.password != field.stringValue {
                    parent.password = field.stringValue
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
            // AutoFill may set the secure field after the username binding update.
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

        reconcile(emailField, binding: email) { email = $0 }
        reconcile(passwordField, binding: password) { password = $0 }
        // If AutoFill landed in the secure field during this turn, lift it now.
        context.coordinator.harvestPasswordFromField()
        applyEnabled(emailField, passwordField)
        emailField.contentType = .username
        passwordField.contentType = .password
        restyleContainers(in: stack, colors: colors)
    }

    /// Push binding → field only when safe. Never replace a non-empty field with
    /// an empty binding (that is the AutoFill wipe). Prefer lifting field → binding.
    private func reconcile(
        _ field: NSTextField,
        binding: String,
        setBinding: (String) -> Void
    ) {
        if field.stringValue == binding { return }
        if binding.isEmpty, !field.stringValue.isEmpty {
            setBinding(field.stringValue)
            return
        }
        // Don't fight the field editor / AutoFill mid-insert.
        if field.currentEditor() != nil {
            if field.stringValue != binding {
                setBinding(field.stringValue)
            }
            return
        }
        field.stringValue = binding
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
#endif
