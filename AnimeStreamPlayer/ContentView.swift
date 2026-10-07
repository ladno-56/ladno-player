import SwiftUI

@MainActor
struct ContentView: View {
    @StateObject private var appStore = AnimeAppStore()

    var body: some View {
        AnimeAppShell()
            .environmentObject(appStore)
            .preferredColorScheme(appStore.preferences.theme == .light ? .light : .dark)
            .tint(appStore.preferences.accentColor)
    }
}
