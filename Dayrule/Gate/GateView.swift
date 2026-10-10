import SwiftUI

struct GateView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var password = ""
    @State private var busy = false

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        ZStack {
            colors.bg.ignoresSafeArea()
            switch model.phase {
            case .locked, .unlocking:
                lockedForm(colors: colors)
            case .showRecovery(let words):
                RecoveryPhraseView(words: words) {
                    model.confirmRecoverySaved()
                }
            case .unlocked:
                UnlockedHomeView(model: model)
            }
        }
        .task {
            await model.tryDeviceUnlock()
        }
    }

    @ViewBuilder
    private func lockedForm(colors: DayruleColors) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Dayrule")
                .font(DayruleFont.brand())
                .foregroundStyle(colors.text)
            Text("Your lists, encrypted on this device.")
                .font(.body)
                .foregroundStyle(colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            SecureField("Password", text: $password)
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(14)
                .background(colors.sidebar)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous))
                .padding(.horizontal, 32)
                .disabled(model.phase == .unlocking)

            Toggle("Stay unlocked on this device", isOn: $model.stayUnlocked)
                .foregroundStyle(colors.textSecondary)
                .padding(.horizontal, 32)

            Button {
                Task {
                    busy = true
                    await model.unlock(password: password)
                    password = ""
                    busy = false
                }
            } label: {
                Text(model.phase == .unlocking || busy ? "Unlocking…" : "Unlock")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(colors.bg)
                    .background(colors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusPopover, style: .continuous))
            }
            .disabled(password.isEmpty || model.phase == .unlocking || busy)
            .padding(.horizontal, 32)

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(Tokens.Light.deadline)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
    }
}

struct UnlockedHomeView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = DayruleColors.resolve(colorScheme: colorScheme)
        VStack(spacing: 16) {
            Text("Dayrule")
                .font(DayruleFont.brand())
                .foregroundStyle(colors.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 24)

            Text("Inbox, Today, Scheduled and Backlog will land in M3.")
                .foregroundStyle(colors.textSecondary)
                .padding(.horizontal, 24)

            Spacer()

            Button("Lock") {
                model.lock()
            }
            .foregroundStyle(colors.accent)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.bg.ignoresSafeArea())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0).onChanged { _ in model.bumpIdle() }
        )
    }
}
