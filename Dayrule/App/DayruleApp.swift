import SwiftUI

@main
struct DayruleApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showPrivacyCover = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                GateView(model: model)
                if showPrivacyCover {
                    PrivacyCover()
                        .transition(.opacity)
                }
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
