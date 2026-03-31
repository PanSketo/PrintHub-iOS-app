import Foundation
import SwiftUI

// MARK: - Full Backup Bundle

struct FullBackup: Codable {
    let version: Int
    let savedAt: String
    let filaments: [Filament]
    let printJobs: [PrintJob]
    let printerConfigs: [PrinterConfig]
    let activePrinterId: String?
    let settings: BackupSettings
}

struct BackupSettings: Codable {
    let lowStockThreshold: Double
    let colorSchemePreference: String
    let inventoryViewMode: String
    // Cost calculator
    let electricityRate: Double
    let printerWatts: Double
    let printerValue: Double
    let printerLifetimeH: Double
    let failureRate: Double
    let consumablesPH: Double
    let profitMargin: Double
    let monthlyHours: Double
    let rent: Double
    let internet: Double
    let accounting: Double
    let misc: Double
}

// MARK: - NAS Backup Service

class NASBackupService: ObservableObject {
    static let shared = NASBackupService()

    @Published var lastBackupDate: Date?
    @Published var isBusy = false
    @Published var statusMessage = ""

    private let lastBackupKey = "nas_full_backup_date"

    private init() {
        let ts = UserDefaults.standard.double(forKey: lastBackupKey)
        if ts > 0 { lastBackupDate = Date(timeIntervalSince1970: ts) }
    }

    // MARK: - Back Up to NAS

    func backup(store: InventoryStore, printerManager: PrinterManager, nas: NASService) async {
        await MainActor.run { isBusy = true; statusMessage = "" }
        do {
            let bundle = buildBundle(store: store, printerManager: printerManager)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(bundle)
            try await nas.uploadFullBackup(data)
            let now = Date()
            await MainActor.run {
                lastBackupDate = now
                UserDefaults.standard.set(now.timeIntervalSince1970, forKey: lastBackupKey)
                statusMessage = "✅ Backup saved to NAS"
                isBusy = false
            }
        } catch {
            await MainActor.run {
                statusMessage = "❌ \(error.localizedDescription)"
                isBusy = false
            }
        }
    }

    // MARK: - Restore from NAS

    func restore(nas: NASService, store: InventoryStore, printerManager: PrinterManager) async {
        await MainActor.run { isBusy = true; statusMessage = "" }
        do {
            let data = try await nas.downloadFullBackup()
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let bundle = try decoder.decode(FullBackup.self, from: data)

            // 1. Push filaments + jobs back to NAS database
            try await nas.restoreToNAS(filaments: bundle.filaments, printJobs: bundle.printJobs)

            // 2. Apply everything on main thread
            await MainActor.run {
                applyBundle(bundle, store: store, printerManager: printerManager)
                statusMessage = "✅ Restored \(bundle.filaments.count) spools, \(bundle.printJobs.count) jobs"
                isBusy = false
            }

            // 3. Re-sync from NAS to confirm local state matches
            store.syncFromNAS()

        } catch {
            await MainActor.run {
                statusMessage = "❌ \(error.localizedDescription)"
                isBusy = false
            }
        }
    }

    // MARK: - Private helpers

    private func buildBundle(store: InventoryStore, printerManager: PrinterManager) -> FullBackup {
        let d = UserDefaults.standard
        let settings = BackupSettings(
            lowStockThreshold:    d.double(forKey: "low_stock_threshold").ifZero(200),
            colorSchemePreference: d.string(forKey: "app_color_scheme") ?? "system",
            inventoryViewMode:    d.string(forKey: "inventory_view_mode") ?? "grid",
            electricityRate:      d.double(forKey: "calc_electricity_rate").ifZero(0.11),
            printerWatts:         d.double(forKey: "calc_printer_watts").ifZero(190),
            printerValue:         d.double(forKey: "calc_printer_value").ifZero(820.47),
            printerLifetimeH:     d.double(forKey: "calc_printer_lifetime_h").ifZero(3500),
            failureRate:          d.double(forKey: "calc_failure_rate").ifZero(2),
            consumablesPH:        d.double(forKey: "calc_consumables_ph").ifZero(0.125),
            profitMargin:         d.double(forKey: "calc_profit_margin").ifZero(18),
            monthlyHours:         d.double(forKey: "calc_monthly_hours").ifZero(80),
            rent:                 d.double(forKey: "calc_rent").ifZero(400),
            internet:             d.double(forKey: "calc_internet").ifZero(50),
            accounting:           d.double(forKey: "calc_accounting").ifZero(50),
            misc:                 d.double(forKey: "calc_misc")
        )
        return FullBackup(
            version:         2,
            savedAt:         ISO8601DateFormatter().string(from: Date()),
            filaments:       store.filaments,
            printJobs:       store.printJobs,
            printerConfigs:  printerManager.printers,
            activePrinterId: printerManager.activePrinterId,
            settings:        settings
        )
    }

    @MainActor
    private func applyBundle(_ bundle: FullBackup, store: InventoryStore, printerManager: PrinterManager) {
        // Filaments & jobs (NAS is already updated; local state updated here)
        store.filaments  = bundle.filaments
        store.printJobs  = bundle.printJobs

        // Printer configs
        printerManager.printers        = bundle.printerConfigs
        printerManager.activePrinterId = bundle.activePrinterId ?? bundle.printerConfigs.first?.id

        // App settings → UserDefaults
        let d = UserDefaults.standard
        let s = bundle.settings
        d.set(s.lowStockThreshold,     forKey: "low_stock_threshold")
        d.set(s.colorSchemePreference, forKey: "app_color_scheme")
        d.set(s.inventoryViewMode,     forKey: "inventory_view_mode")
        d.set(s.electricityRate,       forKey: "calc_electricity_rate")
        d.set(s.printerWatts,          forKey: "calc_printer_watts")
        d.set(s.printerValue,          forKey: "calc_printer_value")
        d.set(s.printerLifetimeH,      forKey: "calc_printer_lifetime_h")
        d.set(s.failureRate,           forKey: "calc_failure_rate")
        d.set(s.consumablesPH,         forKey: "calc_consumables_ph")
        d.set(s.profitMargin,          forKey: "calc_profit_margin")
        d.set(s.monthlyHours,          forKey: "calc_monthly_hours")
        d.set(s.rent,                  forKey: "calc_rent")
        d.set(s.internet,              forKey: "calc_internet")
        d.set(s.accounting,            forKey: "calc_accounting")
        d.set(s.misc,                  forKey: "calc_misc")

        store.lowStockThreshold = s.lowStockThreshold
    }
}

private extension Double {
    func ifZero(_ fallback: Double) -> Double { self == 0 ? fallback : self }
}
