import SwiftUI

@main
struct PenteApp: App {
    @StateObject private var game = PenteGameViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(game)
                .frame(minWidth: 920, minHeight: 760)
        }
    }
}
