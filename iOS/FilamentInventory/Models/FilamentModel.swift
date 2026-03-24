import Foundation
import SwiftUI

// MARK: - Filament Model
struct Filament: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var brand: String
    var sku: String = ""
    var barcode: String = ""
    var type: FilamentType
    var color: FilamentColor
    var totalWeightG: Double        // original spool weight in grams
    var remainingWeightG: Double    // current remaining weight
    var pricePaid: Double
    var currency: String = "EUR"
    var purchaseDate: Date
    var imageURL: String?
    var brandLogoURL: String?
    var notes: String = ""
    var stockStatus: StockStatus
    var printJobs: [PrintJob] = []
    var lastUpdated: Date = Date()
    var priceHistory: [PriceEntry] = []
    var reorderURL: String? = nil

    // Online-fetched metadata
    var diameter: Double = 1.75     // mm
    var printTempMin: Int?
    var printTempMax: Int?
    var bedTempMin: Int?
    var bedTempMax: Int?
    var productDescription: String?

    // CodingKeys declared here so the extension decoder can reference them.
    // Defining explicit CodingKeys does NOT suppress the synthesized memberwise initializer.
    enum CodingKeys: String, CodingKey {
        case id, brand, sku, barcode, type, color, totalWeightG, remainingWeightG
        case pricePaid, currency, purchaseDate, imageURL, brandLogoURL, notes
        case stockStatus, printJobs, lastUpdated, priceHistory, reorderURL
        case diameter, printTempMin, printTempMax, bedTempMin, bedTempMax, productDescription
    }

    var usedWeightG: Double {
        totalWeightG - remainingWeightG
    }

    var percentageRemaining: Double {
        guard totalWeightG > 0 else { return 0 }
        return (remainingWeightG / totalWeightG) * 100
    }

    var isLowStock: Bool {
        remainingWeightG < 200
    }

    var isEmpty: Bool {
        remainingWeightG <= 0
    }
}

// MARK: - Filament Type
enum FilamentType: String, Codable, CaseIterable {
    case pla = "PLA"
    case plaPlus = "PLA+"
    case abs = "ABS"
    case petg = "PETG"
    case tpu = "TPU"
    case asa = "ASA"
    case nylon = "Nylon"
    case wood = "Wood"
    case silk = "Silk"
    case carbon = "Carbon Fiber"
    case resin = "Resin"
    case hips = "HIPS"
    case pva = "PVA"
    case other = "Other"

    var icon: String {
        switch self {
        case .pla, .plaPlus: return "circle.fill"
        case .abs: return "hexagon.fill"
        case .petg: return "diamond.fill"
        case .tpu: return "heart.fill"
        case .silk: return "star.fill"
        case .carbon: return "bolt.fill"
        default: return "capsule.fill"
        }
    }
}

// MARK: - Filament Color
struct FilamentColor: Codable, Hashable {
    var name: String
    var hexCode: String

    var color: Color {
        Color(hex: hexCode) ?? .gray
    }

    static let commonColors: [FilamentColor] = [
        FilamentColor(name: "Black", hexCode: "#1A1A1A"),
        FilamentColor(name: "White", hexCode: "#F5F5F5"),
        FilamentColor(name: "Red", hexCode: "#E53935"),
        FilamentColor(name: "Blue", hexCode: "#1E88E5"),
        FilamentColor(name: "Green", hexCode: "#43A047"),
        FilamentColor(name: "Yellow", hexCode: "#FDD835"),
        FilamentColor(name: "Orange", hexCode: "#FB8C00"),
        FilamentColor(name: "Purple", hexCode: "#8E24AA"),
        FilamentColor(name: "Pink", hexCode: "#E91E63"),
        FilamentColor(name: "Grey", hexCode: "#757575"),
        FilamentColor(name: "Silver", hexCode: "#BDBDBD"),
        FilamentColor(name: "Gold", hexCode: "#FFD700"),
        FilamentColor(name: "Transparent", hexCode: "#E0F7FA"),
        FilamentColor(name: "Brown", hexCode: "#6D4C41"),
        FilamentColor(name: "Cyan", hexCode: "#00BCD4"),
    ]
}

// MARK: - Stock Status
enum StockStatus: String, Codable, CaseIterable {
    case full = "Full"
    case partial = "Partial"
    case low = "Low"
    case empty = "Empty"

    var color: Color {
        switch self {
        case .full: return .green
        case .partial: return .blue
        case .low: return .orange
        case .empty: return .red
        }
    }

    var icon: String {
        switch self {
        case .full: return "checkmark.circle.fill"
        case .partial: return "circle.lefthalf.filled"
        case .low: return "exclamationmark.circle.fill"
        case .empty: return "xmark.circle.fill"
        }
    }

    static func from(remaining: Double, total: Double) -> StockStatus {
        guard total > 0 else { return .empty }
        let pct = remaining / total
        if remaining <= 0 { return .empty }
        if remaining < 200 { return .low }
        if pct < 0.5 { return .partial }
        return .full
    }
}

// MARK: - Price Entry
struct PriceEntry: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var price: Double
    var date: Date
    var notes: String = ""

    enum CodingKeys: String, CodingKey { case id, price, date, notes }
}

// MARK: - Print Job
struct PrintJob: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var filamentId: String
    var printName: String
    var weightUsedG: Double
    var duration: TimeInterval?     // seconds
    var date: Date
    var notes: String = ""
    var success: Bool = true

    enum CodingKeys: String, CodingKey {
        case id, filamentId, printName, weightUsedG, duration, date, notes, success
    }
}

// MARK: - Resilient Codable decoders
// Moving init(from:) to extensions preserves the synthesized memberwise initializer
// (which callers like AddFilamentView rely on) while still overriding the synthesized
// Codable decoder so older NAS records with missing fields load without crashing.

extension Filament {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Core fields — always present in any stored record
        brand            = try c.decode(String.self,        forKey: .brand)
        type             = try c.decode(FilamentType.self,  forKey: .type)
        color            = try c.decode(FilamentColor.self, forKey: .color)
        totalWeightG     = try c.decode(Double.self,        forKey: .totalWeightG)
        remainingWeightG = try c.decode(Double.self,        forKey: .remainingWeightG)
        pricePaid        = try c.decode(Double.self,        forKey: .pricePaid)
        purchaseDate     = try c.decode(Date.self,          forKey: .purchaseDate)
        stockStatus      = try c.decode(StockStatus.self,   forKey: .stockStatus)
        // Fields added in later app versions — fall back to defaults if absent
        id           = (try? c.decodeIfPresent(String.self,       forKey: .id))           ?? UUID().uuidString
        sku          = (try? c.decodeIfPresent(String.self,       forKey: .sku))          ?? ""
        barcode      = (try? c.decodeIfPresent(String.self,       forKey: .barcode))      ?? ""
        currency     = (try? c.decodeIfPresent(String.self,       forKey: .currency))     ?? "EUR"
        notes        = (try? c.decodeIfPresent(String.self,       forKey: .notes))        ?? ""
        diameter     = (try? c.decodeIfPresent(Double.self,       forKey: .diameter))     ?? 1.75
        lastUpdated  = (try? c.decodeIfPresent(Date.self,         forKey: .lastUpdated))  ?? Date()
        printJobs    = (try? c.decodeIfPresent([PrintJob].self,   forKey: .printJobs))    ?? []
        priceHistory = (try? c.decodeIfPresent([PriceEntry].self, forKey: .priceHistory)) ?? []
        // Optional fields
        imageURL           = try? c.decodeIfPresent(String.self, forKey: .imageURL)
        brandLogoURL       = try? c.decodeIfPresent(String.self, forKey: .brandLogoURL)
        reorderURL         = try? c.decodeIfPresent(String.self, forKey: .reorderURL)
        printTempMin       = try? c.decodeIfPresent(Int.self,    forKey: .printTempMin)
        printTempMax       = try? c.decodeIfPresent(Int.self,    forKey: .printTempMax)
        bedTempMin         = try? c.decodeIfPresent(Int.self,    forKey: .bedTempMin)
        bedTempMax         = try? c.decodeIfPresent(Int.self,    forKey: .bedTempMax)
        productDescription = try? c.decodeIfPresent(String.self, forKey: .productDescription)
    }
}

extension PriceEntry {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        price = try c.decode(Double.self, forKey: .price)
        date  = try c.decode(Date.self,   forKey: .date)
        id    = (try? c.decodeIfPresent(String.self, forKey: .id))    ?? UUID().uuidString
        notes = (try? c.decodeIfPresent(String.self, forKey: .notes)) ?? ""
    }
}

extension PrintJob {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        filamentId  = try c.decode(String.self, forKey: .filamentId)
        printName   = try c.decode(String.self, forKey: .printName)
        weightUsedG = try c.decode(Double.self, forKey: .weightUsedG)
        date        = try c.decode(Date.self,   forKey: .date)
        id          = (try? c.decodeIfPresent(String.self,      forKey: .id))      ?? UUID().uuidString
        notes       = (try? c.decodeIfPresent(String.self,      forKey: .notes))   ?? ""
        success     = (try? c.decodeIfPresent(Bool.self,        forKey: .success)) ?? true
        duration    = try? c.decodeIfPresent(TimeInterval.self, forKey: .duration)
    }
}

// MARK: - Color Extension
extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        let r = Double((rgb & 0xFF0000) >> 16) / 255
        let g = Double((rgb & 0x00FF00) >> 8) / 255
        let b = Double(rgb & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b)
    }

    func toHex() -> String {
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r*255), Int(g*255), Int(b*255))
    }
}

// MARK: - Printer Models

struct PrinterState: Codable {
    var connected: Bool
    var live: PrinterLiveState?

    // Explicit keys so decoder works regardless of keyDecodingStrategy setting
    enum CodingKeys: String, CodingKey {
        case connected
        case live
    }
}

struct PrinterLiveState: Codable {
    var printStatus: String       // IDLE, RUNNING, PAUSE, FINISH, FAILED
    var printName: String
    var progress: Int             // 0-100
    var remainingMinutes: Int
    var layerCurrent: Int
    var layerTotal: Int
    var nozzleTemp: Double
    var bedTemp: Double
    var chamberTemp: Double
    var printSpeed: Int           // 1=Silent, 2=Standard, 3=Sport, 4=Ludicrous
    var timestamp: String
    var amsSlots: [String: AMSSlotState]?
    var activeAMSSlot: String?   // Bambu sends this as a string e.g. "255" or "0"

    enum CodingKeys: String, CodingKey {
        case printStatus = "print_status"
        case printName = "print_name"
        case progress
        case remainingMinutes = "remaining_minutes"
        case layerCurrent = "layer_current"
        case layerTotal = "layer_total"
        case nozzleTemp = "nozzle_temp"
        case bedTemp = "bed_temp"
        case chamberTemp = "chamber_temp"
        case printSpeed = "print_speed"
        case timestamp
        case amsSlots = "ams_slots"
        case activeAMSSlot = "active_ams_slot"
    }

    // Custom decoder: Bambu may send numeric fields as Int or Double, and
    // active_ams_slot as an Int rather than a String — handle all variants.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        printStatus       = (try? c.decodeIfPresent(String.self, forKey: .printStatus))    ?? "IDLE"
        printName         = (try? c.decodeIfPresent(String.self, forKey: .printName))      ?? ""
        remainingMinutes  = (try? c.decodeIfPresent(Int.self,    forKey: .remainingMinutes)) ?? 0
        layerCurrent      = (try? c.decodeIfPresent(Int.self,    forKey: .layerCurrent))    ?? 0
        layerTotal        = (try? c.decodeIfPresent(Int.self,    forKey: .layerTotal))      ?? 0
        nozzleTemp        = (try? c.decodeIfPresent(Double.self,  forKey: .nozzleTemp))     ?? 0
        bedTemp           = (try? c.decodeIfPresent(Double.self,  forKey: .bedTemp))        ?? 0
        chamberTemp       = (try? c.decodeIfPresent(Double.self,  forKey: .chamberTemp))    ?? 0
        printSpeed        = (try? c.decodeIfPresent(Int.self,    forKey: .printSpeed))      ?? 2
        timestamp         = (try? c.decodeIfPresent(String.self, forKey: .timestamp))      ?? ""
        amsSlots          = (try? c.decodeIfPresent([String: AMSSlotState].self, forKey: .amsSlots)) ?? nil

        // progress can arrive as Int or Double from Bambu
        if let i = (try? c.decodeIfPresent(Int.self, forKey: .progress)) ?? nil {
            progress = i
        } else {
            progress = Int((try? c.decodeIfPresent(Double.self, forKey: .progress)) ?? nil ?? 0)
        }

        // active_ams_slot: bridge now stringifies, but guard against bare Int from Bambu
        if let s = (try? c.decodeIfPresent(String.self, forKey: .activeAMSSlot)) ?? nil {
            activeAMSSlot = s
        } else if let i = (try? c.decodeIfPresent(Int.self, forKey: .activeAMSSlot)) ?? nil {
            activeAMSSlot = String(i)
        } else {
            activeAMSSlot = nil
        }
    }

    // "255" means no active slot (idle), otherwise 0-3 = slot index
    var activeAMSSlotIndex: Int? {
        guard let s = activeAMSSlot, let i = Int(s), i != 255 else { return nil }
        return i
    }

    var isIdle: Bool { printStatus == "IDLE" || printStatus == "FINISH" || printStatus == "FAILED" }
    var isPrinting: Bool { printStatus == "RUNNING" }
    var isPaused: Bool { printStatus == "PAUSE" }

    var statusIcon: String {
        switch printStatus {
        case "RUNNING": return "printer.fill"
        case "PAUSE":   return "pause.circle.fill"
        case "FINISH":  return "checkmark.circle.fill"
        case "FAILED":  return "xmark.circle.fill"
        default:        return "printer"
        }
    }

    var statusColor: SwiftUI.Color {
        switch printStatus {
        case "RUNNING": return .blue
        case "PAUSE":   return .orange
        case "FINISH":  return .green
        case "FAILED":  return .red
        default:        return .secondary
        }
    }

    var speedLabel: String {
        switch printSpeed {
        case 1: return "Silent"
        case 2: return "Standard"
        case 3: return "Sport"
        case 4: return "Ludicrous"
        default: return "Standard"
        }
    }
}

struct AMSSlotState: Codable {
    var amsIndex: Int
    var slotIndex: Int
    var trayColor: String
    var trayType: String
    var remain: Int    // % remaining (-1 if unknown)

    enum CodingKeys: String, CodingKey {
        case amsIndex = "ams_index"
        case slotIndex = "slot_index"
        case trayColor = "tray_color"
        case trayType = "tray_type"
        case remain
    }

    // Custom init so unknown fields (tray_sub_brands, cols) are silently ignored
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        amsIndex = try c.decodeIfPresent(Int.self, forKey: .amsIndex) ?? 0
        slotIndex = try c.decodeIfPresent(Int.self, forKey: .slotIndex) ?? 0
        trayColor = try c.decodeIfPresent(String.self, forKey: .trayColor) ?? ""
        trayType = try c.decodeIfPresent(String.self, forKey: .trayType) ?? ""
        remain = try c.decodeIfPresent(Int.self, forKey: .remain) ?? -1
    }
}
