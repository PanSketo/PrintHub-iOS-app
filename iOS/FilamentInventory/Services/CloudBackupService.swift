import Foundation
import Combine
import UIKit

// MARK: - Backup Service
// Exports / imports the full inventory as a single JSON file.
// Works without ANY entitlements or special capabilities — no Xcode/Mac needed.
//
// Export: encodes filaments + print jobs → writes to a temp file → returns a URL
//         the caller presents as a share sheet (UIActivityViewController) or
//         SwiftUI .shareLink / fileExporter.
//
// Import: the caller presents a .fileImporter → user picks the JSON →
//         calls restore(from:) with the chosen URL.

class CloudBackupService: ObservableObject {
    static let shared = CloudBackupService()

    @Published var lastBackupDate: Date?
    @Published var statusMessage: String = ""

    // Always available — no entitlements required
    var isAvailable: Bool { true }

    private let lastBackupKey = "json_backup_date_v1"

    private init() {
        let ts = UserDefaults.standard.double(forKey: lastBackupKey)
        if ts > 0 { lastBackupDate = Date(timeIntervalSince1970: ts) }
    }

    // MARK: - Export

    /// Encodes the inventory to a JSON file in the temp directory and returns its URL.
    /// Present the URL with UIActivityViewController or SwiftUI .shareLink.
    func exportURL(filaments: [Filament], jobs: [PrintJob]) -> URL? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        let payload: [String: Any] = [
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "version": 1
        ]
        _ = payload // metadata kept for future versioning; not yet encoded separately

        struct BackupPayload: Encodable {
            let exportedAt: String
            let version: Int
            let filaments: [Filament]
            let printJobs: [PrintJob]
        }
        let backup = BackupPayload(
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            version: 1,
            filaments: filaments,
            printJobs: jobs
        )
        guard let data = try? encoder.encode(backup) else { return nil }

        let fileName = "FilamentInventory-\(dateStamp()).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? data.write(to: url)

        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastBackupKey)
        lastBackupDate = Date()
        statusMessage = "✅ Ready to share (\(data.count / 1024) KB)"
        return url
    }

    // MARK: - Import

    enum BackupError: LocalizedError {
        case unreadable
        case invalidFormat
        var errorDescription: String? {
            switch self {
            case .unreadable:     return "Could not read the backup file."
            case .invalidFormat:  return "File is not a valid Filament Inventory backup."
            }
        }
    }

    /// Decodes a previously exported JSON file and returns the inventory objects.
    func restore(from url: URL) throws -> (filaments: [Filament], jobs: [PrintJob]) {
        // Security-scoped resource access for files picked via UIDocumentPickerViewController
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else { throw BackupError.unreadable }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Try versioned wrapper first, then fall back to bare arrays
        struct BackupPayload: Decodable {
            let filaments: [Filament]
            let printJobs: [PrintJob]
        }
        if let payload = try? decoder.decode(BackupPayload.self, from: data) {
            return (payload.filaments, payload.printJobs)
        }
        // Bare filament array (legacy / manual export)
        if let filaments = try? decoder.decode([Filament].self, from: data) {
            return (filaments, [])
        }
        throw BackupError.invalidFormat
    }

    // MARK: - Helpers

    func refreshAvailability() {}   // kept so callers don't need changes

    func backup(filaments: [Filament], jobs: [PrintJob]) async {}  // no-op; export is manual

    private func dateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
