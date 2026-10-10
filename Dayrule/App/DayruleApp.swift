import SwiftUI

@main
struct DayruleApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showPrivacyCover = false

    init() {
        #if os(iOS)
        ReminderBackgroundRefresh.registerLauncher()
        #endif
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
            .onAppear {
                #if os(iOS)
                ReminderBackgroundRefresh.bind(model)
                #endif
            }
            .onChange(of: scenePhase) { _, phase in
                model.scenePhaseChanged(phase)
                withAnimation(.easeInOut(duration: 0.15)) {
                    showPrivacyCover = phase != .active
                }
            }
        }
    }
}
