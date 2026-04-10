import SwiftUI
import AppIntents
import UIKit

// MARK: - App Delegate

class AppDelegate: NSObject, UIApplicationDelegate {
    // Matches Info.plist — portrait + both landscapes, no upside-down.
    // Declaring it here lets the camera fullscreen's requestGeometryUpdate
    // snap to landscape immediately without Info.plist ambiguity.
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        .allButUpsideDown
    }
}

// MARK: - App Entry Point

@main
struct FilamentInventoryApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var nasService = NASService.shared
    @StateObject private var inventoryStore = InventoryStore.shared
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var printerManager = PrinterManager.shared
    @StateObject private var cloudBackup = CloudBackupService.shared

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
                .environmentObject(printerManager)
                .preferredColorScheme(preferredColorScheme)
                .onAppear {
                    notificationManager.requestPermission()
                    cloudBackup.refreshAvailability()
                    if !nasService.isConnected && nasService.isConfigured {
                        Task { await nasService.autoConnect() }
                    }
                    // Donate App Shortcuts to Siri on every launch
                    if #available(iOS 16, *) {
                        FilamentShortcutsProvider.updateAppShortcutParameters()
                    }
                }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active && nasService.isConfigured {
                Task {
                    await nasService.autoConnect()
                    await nasService.checkPrintEvents()
                }
            }
        }
    }
}
