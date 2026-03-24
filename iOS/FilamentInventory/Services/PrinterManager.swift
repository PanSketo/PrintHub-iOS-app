import Foundation
import Combine

// MARK: - Printer Manager
// Manages a list of printer configurations (each pointing to its own NAS/mqtt-bridge).
// A single printer is the common case — the UI only shows the picker when more than one
// printer is configured.

class PrinterManager: ObservableObject {
    static let shared = PrinterManager()

    @Published var printers: [PrinterConfig] = []
    @Published var activePrinterId: String?

    private let printersKey = "configured_printers_v2"
    private let activeIdKey  = "active_printer_id_v2"

    var activePrinter: PrinterConfig? {
        printers.first { $0.id == activePrinterId } ?? printers.first
    }

    private init() { load() }

    // MARK: - CRUD

    func addPrinter(_ config: PrinterConfig) {
        printers.append(config)
        if activePrinterId == nil { activePrinterId = config.id }
        save()
    }

    func updatePrinter(_ config: PrinterConfig) {
        guard let idx = printers.firstIndex(where: { $0.id == config.id }) else { return }
        printers[idx] = config
        save()
    }

    func removePrinter(id: String) {
        printers.removeAll { $0.id == id }
        if activePrinterId == id { activePrinterId = printers.first?.id }
        save()
    }

    func setActive(id: String) {
        activePrinterId = id
        UserDefaults.standard.set(id, forKey: activeIdKey)
    }

    // MARK: - Persistence

    private func save() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(printers) {
            UserDefaults.standard.set(data, forKey: printersKey)
        }
        if let id = activePrinterId {
            UserDefaults.standard.set(id, forKey: activeIdKey)
        }
    }

    private func load() {
        let decoder = JSONDecoder()
        if let data = UserDefaults.standard.data(forKey: printersKey),
           let saved = try? decoder.decode([PrinterConfig].self, from: data) {
            printers = saved
        }
        activePrinterId = UserDefaults.standard.string(forKey: activeIdKey) ?? printers.first?.id
    }
}
