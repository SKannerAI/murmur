import SwiftUI

@main
struct MurmurApp: App {
    @StateObject private var controller = DictationController()

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(controller)
                .environmentObject(controller.ollama)
        } label: {
            Image(systemName: controller.phase.symbolName)
        }
        .menuBarExtraStyle(.window)
    }
}
