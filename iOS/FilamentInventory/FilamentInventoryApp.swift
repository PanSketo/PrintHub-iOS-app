import SwiftUI

@main
struct FilamentInventoryApp: App {
    @StateObject private var nasService = NASService.shared
    @StateObject private var inventoryStore = InventoryStore.shared
    @StateObject private var notificationManager = NotificationManager.shared

    @AppStorage("app_color_scheme") private var colorSchemePreference: String = "system"
    @Environment(\.scenePhase) private var scenePhase

    var preferredColorScheme: ColorScheme? {
        switch colorSchemePreference {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil   // nil = follow system
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(nasService)
                .environmentObject(inventoryStore)
                .environmentObject(notificationManager)
                .preferredColorScheme(preferredColorScheme)
                .onAppear {
                    notificationManager.requestPermission()
                    if !nasService.isConnected && nasService.isConfigured {
                        Task { await nasService.autoConnect() }
                    }
                }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active && nasService.isConfigured {
                Task { await nasService.autoConnect() }
            }
        }
    }
}
