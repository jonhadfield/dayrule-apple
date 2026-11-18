import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct DayruleApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(DayruleAppDelegate.self) private var appDelegate
    #elseif os(macOS)
    @NSApplicationDelegateAdaptor(DayruleAppDelegate.self) private var appDelegate
    #endif
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showPrivacyCover = false
    #if os(macOS)
    /// AppKit active state — Mission Control / other apps resign active without
    /// using scenePhase `.inactive` (that also fires for in-app menus).
    @State private var macAppActive = true
    /// Bumped when macOS Light/Dark changes so System appearance re-resolves.
    @State private var macSystemAppearanceTick = 0
    #endif
    @AppStorage("dayrule.appearance") private var appearanceRaw = AppearancePreference.system.rawValue

    init() {
        Primitives.ready()
        #if os(iOS)
        ReminderBackgroundRefresh.registerLauncher()
        DayruleNavAppearance.configure()
        #endif
    }

    private var appearancePreference: AppearancePreference {
        AppearancePreference(rawValue: appearanceRaw) ?? .system
    }

    /// SwiftUI scheme for the main window. On Mac, System is resolved to the
    /// current OS scheme (not `nil`) — `nil` after Light/Dark leaves the list
    /// stuck light while sheets correctly go dark.
    private var preferredScheme: ColorScheme? {
        switch appearancePreference {
        case .light: return .light
        case .dark: return .dark
        case .system:
            #if os(macOS)
            _ = macSystemAppearanceTick
            return macSystemColorScheme()
            #else
            return nil
            #endif
        }
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
            #if os(iOS)
            .sensoryFeedback(.impact(weight: .light), trigger: model.haptics.add)
            .sensoryFeedback(.impact(weight: .medium), trigger: model.haptics.trash)
            .sensoryFeedback(.success, trigger: model.haptics.unlock)
            .sensoryFeedback(.selection, trigger: model.haptics.chip)
            .sensoryFeedback(.error, trigger: model.haptics.error)
            .sensoryFeedback(.error, trigger: model.notices.errorPulse)
            #endif
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
                QuickActions.bind(model)
                #endif
                #if os(macOS)
                MacWindowCloseGate.model = model
                // Clear any pinned aqua/darkAqua so System can follow the OS.
                applyMacAppearance(appearancePreference)
                #endif
            }
            #if os(macOS)
            .onChange(of: appearanceRaw) { _, _ in
                applyMacAppearance(appearancePreference)
                macSystemAppearanceTick &+= 1
            }
            .onReceive(
                DistributedNotificationCenter.default()
                    .publisher(for: Notification.Name("AppleInterfaceThemeChangedNotification"))
            ) { _ in
                macSystemAppearanceTick &+= 1
                if appearancePreference == .system {
                    applyMacAppearance(.system)
                }
            }
            #endif
            .onChange(of: scenePhase) { _, phase in
                model.scenePhaseChanged(phase)
                refreshPrivacyCover()
            }
            .onChange(of: model.phase) { _, _ in
                // Unlock can finish while the scene is already inactive (app switcher).
                refreshPrivacyCover()
            }
            #if os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                macAppActive = true
                model.applicationBecameActive()
                refreshPrivacyCover()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                macAppActive = false
                refreshPrivacyCover()
            }
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1280, height: 800)
        .windowResizability(.contentMinSize)
        #endif
        // Mac menu bar and iPad ⌘-hold list (PLAN §6.6 / decision 36).
        .commands {
            #if os(macOS)
            CommandGroup(replacing: .appInfo) {
                Button("About Dayrule") {
                    showAboutPanel()
                }
            }
            #endif
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
                Button("New To-Do") {
                    model.requestFocusAdd()
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(model.phase != .unlocked)
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
                // ⌘⌫ — Finder/Mail style; bare ⌫ fights text fields (decision 56).
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(model.phase != .unlocked || !model.hasMacListSelection)
            }
            // Replace Apple Help Viewer (no help book) with offline in-app Help
            // (PLAN decision 21 / 52). Available locked or unlocked — no vault needed.
            CommandGroup(replacing: .help) {
                Button("Dayrule Help") {
                    model.showHelp = true
                }
                .keyboardShortcut("?", modifiers: .command)
            }
        }
    }

    private func refreshPrivacyCover() {
        #if os(macOS)
        setPrivacyCover(privacyCoverNeeded(macAppActive: macAppActive, appPhase: model.phase))
        #else
        setPrivacyCover(privacyCoverNeeded(scenePhase: scenePhase, appPhase: model.phase))
        #endif
    }

    #if os(macOS)
    /// Cover when the app resigns active (Mission Control / another app). Do not
    /// use scenePhase `.inactive` — that fires for ordinary menu use (§8.7).
    private func privacyCoverNeeded(macAppActive: Bool, appPhase: AppModel.Phase) -> Bool {
        PrivacyCoverPolicy.needed(macAppActive: macAppActive, phase: appPhase)
    }

    private func showAboutPanel() {
        var credits = "Build \(BuildInfo.build)"
        if BuildInfo.gitCommit != "unknown" {
            credits += " · Commit \(BuildInfo.gitCommit)"
        }
        let opts: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationVersion: BuildInfo.shortVersion,
            .version: credits,
        ]
        NSApplication.shared.orderFrontStandardAboutPanel(options: opts)
    }
    #else
    /// Cover whenever the scene isn't active and the screen holds something
    /// sensitive. The gate's sign-in and biometric prompt stay uncovered so
    /// Face ID doesn't flash the cover.
    private func privacyCoverNeeded(scenePhase: ScenePhase, appPhase: AppModel.Phase) -> Bool {
        PrivacyCoverPolicy.needed(sceneActive: scenePhase == .active, phase: appPhase)
    }
    #endif

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

/// OS Light/Dark, ignoring a pinned `NSApp.appearance` (so Light → System while
/// macOS is Dark resolves dark, not the leftover aqua pin).
@MainActor
private func macSystemColorScheme() -> ColorScheme {
    UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" ? .dark : .light
}

/// Keep AppKit in lockstep with Settings → Appearance. `nil` follows the OS;
/// Light/Dark pin aqua / darkAqua. Apply to every window so the main window
/// does not keep a pinned appearance after System is chosen.
@MainActor
private func applyMacAppearance(_ preference: AppearancePreference) {
    let appearance: NSAppearance?
    switch preference {
    case .system:
        appearance = nil
    case .light:
        appearance = NSAppearance(named: .aqua)
    case .dark:
        appearance = NSAppearance(named: .darkAqua)
    }
    NSApp.appearance = appearance
    for window in NSApp.windows {
        window.appearance = appearance
    }
}
#endif
