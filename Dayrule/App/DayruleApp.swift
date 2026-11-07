import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct DayruleApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(DayruleAppDelegate.self) private var appDelegate
    #endif
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showPrivacyCover = false
    @AppStorage("dayrule.appearance") private var appearanceRaw = AppearancePreference.system.rawValue

    init() {
        Primitives.ready()
        #if os(iOS)
        ReminderBackgroundRefresh.registerLauncher()
        DayruleNavAppearance.configure()
        #endif
    }

    private var preferredScheme: ColorScheme? {
        AppearancePreference(rawValue: appearanceRaw)?.colorScheme
    }

    var body: some Scene {
        WindowGroup {
            RootTint {
                ZStack {
                    GateView(model: model)
                    if showPrivacyCover {
                        PrivacyCover()
                            .transition(.opacity)
                    }
                }
            }
            #if os(macOS)
            // ASC Mac screenshots start at 1280×800; keep a usable smaller minimum.
            .frame(minWidth: 800, minHeight: 500)
            // Dense desktop body (web 15px at ≥900px); explicit role fonts still win.
            .environment(\.font, Font.system(size: 15))
            .modifier(UserActivityMonitor(model: model))
            #endif
            .preferredColorScheme(preferredScheme)
            .onAppear {
                #if os(iOS)
                ReminderBackgroundRefresh.bind(model)
                #endif
            }
            .onChange(of: scenePhase) { _, phase in
                model.scenePhaseChanged(phase)
                setPrivacyCover(privacyCoverNeeded(scenePhase: phase, appPhase: model.phase))
            }
            .onChange(of: model.phase) { _, appPhase in
                // Unlock can finish while the scene is already inactive (app switcher).
                setPrivacyCover(privacyCoverNeeded(scenePhase: scenePhase, appPhase: appPhase))
            }
            #if os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                model.applicationBecameActive()
            }
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1280, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    model.showSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(model.phase != .unlocked)
            }
            CommandGroup(after: .appInfo) {
                Button("Lock") {
                    model.lockNow()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(model.phase != .unlocked)
            }
            CommandGroup(replacing: .newItem) {
                Button("New Project") {
                    model.requestMacChromeAction(.newProject)
                }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(model.phase != .unlocked)
                Button("New Area") {
                    model.requestMacChromeAction(.newArea)
                }
                .keyboardShortcut("a", modifiers: [.command, .option])
                .disabled(model.phase != .unlocked)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    model.undoLast()
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(model.phase != .unlocked || !model.store.canUndo)
                Button("Redo") {
                    model.redoLast()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(model.phase != .unlocked || !model.store.canRedo)
            }
            CommandGroup(after: .pasteboard) {
                Button("Find…") {
                    model.showFind = true
                }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(model.phase != .unlocked)
                Button("Move to Trash") {
                    model.requestMacChromeAction(.trashSelection)
                }
                .keyboardShortcut(.delete)
                .disabled(model.phase != .unlocked)
            }
        }
        #endif
    }

    /// On Mac, `.inactive` is common while the window is still usable (e.g. another
    /// app’s menu), so only cover when backgrounded. On iOS cover whenever the scene
    /// isn't active and the screen holds something sensitive: the lists, or the
    /// recovery words shown or typed. The gate's sign-in and biometric prompt stay
    /// uncovered so Face ID doesn't flash the cover.
    private func privacyCoverNeeded(scenePhase: ScenePhase, appPhase: AppModel.Phase) -> Bool {
        #if os(macOS)
        return scenePhase == .background
        #else
        let sensitive: [AppModel.Phase] = [.unlocked, .confirmRecovery, .needsRecovery]
        return sensitive.contains(appPhase) && scenePhase != .active
        #endif
    }

    /// The cover appears in the same frame (no fade) so the app-switcher snapshot
    /// never catches vault contents (PLAN §8.7); only the reveal fades.
    private func setPrivacyCover(_ cover: Bool) {
        guard cover != showPrivacyCover else { return }
        if cover {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { showPrivacyCover = true }
        } else {
            withAnimation(Motion.system(Motion.fade)) { showPrivacyCover = false }
        }
    }
}

/// App-wide tint from the accent token, resolved for the current scheme, so
/// toggles, pickers, carets and selection never fall back to system blue.
private struct RootTint<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var content: Content

    var body: some View {
        content.tint(DayruleColors.resolve(colorScheme: colorScheme).accent)
    }
}

#if os(macOS)
/// Treats key presses, clicks and scrolling as activity for the idle auto-lock.
/// The monitor only observes: every event is returned unchanged.
private struct UserActivityMonitor: ViewModifier {
    let model: AppModel
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .scrollWheel]) { event in
                    MainActor.assumeIsolated { model.noteUserActivity() }
                    return event
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }
}
#endif
