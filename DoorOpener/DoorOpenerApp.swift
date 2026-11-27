import SwiftUI

@main
struct DoorOpenerApp: App {
    @StateObject private var api = DoorAPI.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(api)
        }
    }
}
