import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct DayruleApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showPrivacyCover = false
    @AppStorage("dayrule.appearance") private var appearanceRaw = AppearancePreference.system.rawValue

    init() {
        Primitives.ready()
        #if os(iOS)
        ReminderBackgroundRefresh.registerLauncher()
        #endif
    }

    private var preferredScheme: ColorScheme? {
        AppearancePreference(rawValue: appearanceRaw)?.colorScheme
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                GateView(model: model)
                if showPrivacyCover {
                    PrivacyCover()
                        .transition(.opacity)
                }
            }
            .preferredColorScheme(preferredScheme)
            .onAppear {
                #if os(iOS)
                ReminderBackgroundRefresh.bind(model)
                #endif
            }
            .onChange(of: scenePhase) { _, phase in
                model.scenePhaseChanged(phase)
                withAnimation(.easeInOut(duration: 0.15)) {
                    // On Mac, `.inactive` is common while the window is still usable
                    // (e.g. another app’s menu). Only cover when backgrounded.
                    #if os(macOS)
                    showPrivacyCover = phase == .background
                    #else
                    showPrivacyCover = phase != .active
                    #endif
                }
            }
            #if os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                model.applicationBecameActive()
            }
            #endif
        }
    }
}
