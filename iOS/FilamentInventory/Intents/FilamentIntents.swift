import AppIntents
import Foundation

// MARK: - Siri / Shortcuts Integration
// App Intents auto-register on iOS 16+ without any Info.plist changes.
// Users can add these to the Shortcuts app or invoke them via Siri.

// MARK: - Shortcuts Provider

@available(iOS 16, *)
struct FilamentShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: FilamentStockIntent(),
            phrases: [
                "Check my \(.applicationName) stock",
                "How much filament in \(.applicationName)",
                "What filament do I have in \(.applicationName)"
            ],
            shortTitle: "Filament Stock",
            systemImageName: "cylinder.split.1x2.fill"
        )
        AppShortcut(
            intent: LowStockIntent(),
            phrases: [
                "What filament is running low in \(.applicationName)",
                "Low stock in \(.applicationName)",
                "Show low stock in \(.applicationName)"
            ],
            shortTitle: "Low Stock",
            systemImageName: "exclamationmark.triangle.fill"
        )
        AppShortcut(
            intent: PrinterStatusIntent(),
            phrases: [
                "What's printing in \(.applicationName)",
                "Check my printer in \(.applicationName)",
                "Printer status in \(.applicationName)"
            ],
            shortTitle: "Printer Status",
            systemImageName: "printer.fill"
        )
        AppShortcut(
            intent: TotalSpendIntent(),
            phrases: [
                "How much have I spent on filament in \(.applicationName)",
                "Filament spend in \(.applicationName)"
            ],
            shortTitle: "Total Spend",
            systemImageName: "eurosign.circle.fill"
        )
    }
}

// MARK: - Filament Stock Intent

@available(iOS 16, *)
struct FilamentStockIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Filament Stock"
    static var description = IntentDescription("Shows a summary of your filament inventory.")

    func perform() async throws -> some ReturnsValue<String> & ProvidesDialog {
        let store = InventoryStore.shared
        let total = store.totalFilaments
        let low   = store.lowStockFilaments.count
        let empty = store.emptyFilaments.count
        let weightKg = String(format: "%.1f", store.totalWeightRemaining / 1000)

        var parts = ["You have \(total) spool\(total == 1 ? "" : "s") with \(weightKg) kg remaining."]
        if empty > 0 { parts.append("\(empty) spool\(empty == 1 ? "" : "s") are empty.") }
        if low > 0   { parts.append("\(low) spool\(low == 1 ? "" : "s") are running low.") }

        let msg = parts.joined(separator: " ")
        return .result(value: msg, dialog: "\(msg)")
    }
}

// MARK: - Low Stock Intent

@available(iOS 16, *)
struct LowStockIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Low Stock"
    static var description = IntentDescription("Lists filaments that are low or empty.")

    func perform() async throws -> some ReturnsValue<String> & ProvidesDialog {
        let store = InventoryStore.shared
        let low   = store.lowStockFilaments
        let empty = store.emptyFilaments

        if low.isEmpty && empty.isEmpty {
            return .result(value: "All spools are well stocked!", dialog: "All spools are well stocked!")
        }

        var lines: [String] = []
        for f in (empty + low).prefix(6) {
            let status = f.isEmpty ? "empty" : "\(Int(f.remainingWeightG))g left"
            lines.append("\(f.brand) \(f.type.rawValue) \(f.color.name): \(status)")
        }
        let remainder = (low.count + empty.count) - lines.count
        if remainder > 0 { lines.append("…and \(remainder) more.") }
        let msg = lines.joined(separator: "\n")
        return .result(value: msg, dialog: "\(msg)")
    }
}

// MARK: - Printer Status Intent

@available(iOS 16, *)
struct PrinterStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Printer Status"
    static var description = IntentDescription("Fetches the current printer state from your NAS.")

    func perform() async throws -> some ReturnsValue<String> & ProvidesDialog {
        let nas = NASService.shared
        guard nas.isConfigured else {
            return .result(value: "NAS is not configured yet.", dialog: "NAS is not configured yet.")
        }
        do {
            let state = try await nas.fetchPrinterState()
            guard state.connected, let live = state.live else {
                let msg = state.connected ? "Printer is connected but idle." : "Printer is offline."
                return .result(value: msg, dialog: "\(msg)")
            }
            let msg: String
            switch live.printStatus {
            case "RUNNING":
                msg = "Printing \"\(live.printName)\", \(live.progress)% done with \(live.remainingMinutes) minutes left."
            case "PAUSE":
                msg = "Print paused: \"\(live.printName)\" at \(live.progress)%."
            case "FINISH":
                msg = "Last print finished: \"\(live.printName)\"."
            case "FAILED":
                msg = "Last print failed: \"\(live.printName)\"."
            default:
                msg = "Printer is idle and ready."
            }
            return .result(value: msg, dialog: "\(msg)")
        } catch {
            let msg = "Could not reach printer."
            return .result(value: msg, dialog: "\(msg)")
        }
    }
}

// MARK: - Total Spend Intent

@available(iOS 16, *)
struct TotalSpendIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Total Filament Spend"
    static var description = IntentDescription("Reports your total filament spending.")

    func perform() async throws -> some ReturnsValue<String> & ProvidesDialog {
        let store = InventoryStore.shared
        let total = store.totalSpend
        let printCost = store.printJobs.compactMap(\.costEUR).reduce(0, +)
        var msg = "You've spent \(euEuro(total)) on filament across \(store.totalFilaments) spools."
        if printCost > 0 {
            msg += " Logged prints total \(euEuro(printCost))."
        }
        return .result(value: msg, dialog: "\(msg)")
    }
}
