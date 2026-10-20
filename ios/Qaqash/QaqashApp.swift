import SwiftUI

@main
struct QaqashApp: App {
    @StateObject private var island = Island()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            Group {
                if island.pairing == nil {
                    PairView()
                } else {
                    HomeView()
                }
            }
            .environmentObject(island)
            .preferredColorScheme(.dark)
        }
        .onChange(of: phase) { _, phase in
            if phase == .active { island.start() } else if phase == .background { island.stop() }
        }
    }
}
