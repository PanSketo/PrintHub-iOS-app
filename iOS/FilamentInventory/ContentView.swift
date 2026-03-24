import SwiftUI

struct ContentView: View {
    @EnvironmentObject var nasService: NASService
    @EnvironmentObject var inventoryStore: InventoryStore
    @State private var selectedTab = 0

    var body: some View {
        Group {
            if !nasService.isConfigured {
                NASSetupView()
            } else {
                TabView(selection: $selectedTab) {

                    // Tab 1: Dashboard
                    DashboardView()
                        .tabItem { Label("Dashboard", systemImage: "square.grid.2x2.fill") }
                        .tag(0)

                    // Tab 2: Inventory (includes search, filter, add)
                    InventoryListView()
                        .tabItem { Label("Inventory", systemImage: "shippingbox.fill") }
                        .tag(1)

                    // Tab 3: Add filament (center prominent button)
                    AddFilamentView()
                        .tabItem { Label("Add", systemImage: "plus.circle.fill") }
                        .tag(2)

                    // Tab 4: Printer (live status + print log + AMS mapping)
                    PrinterView()
                        .tabItem { Label("Printer", systemImage: "printer.fill") }
                        .tag(3)

                    // Tab 5: Settings (includes Stats, Shopping List, theme, NAS config)
                    SettingsView()
                        .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                        .tag(4)
                }
                .accentColor(.orange)
            }
        }
    }
}
