import Foundation
import Combine

// MARK: - iCloud Backup Service
// Backs up the inventory JSON to NSUbiquitousKeyValueStore (iCloud Key-Value Storage).
//
// SETUP REQUIRED (one-time in Xcode):
//   Project → Signing & Capabilities → "+ Capability" → iCloud
//   Enable "Key-value storage"  ← that's all.
//
// The service degrades gracefully when:
//   • The user is not signed into iCloud  (isAvailable = false)
//   • The entitlement is missing          (isAvailable = false)
//   • The payload exceeds 1 MB            (shows a warning, partial backup)

class CloudBackupService: ObservableObject {
    static let shared = CloudBackupService()

    @Published var lastBackupDate: Date?
    @Published var isAvailable: Bool = false
    @Published var statusMessage: String = ""

    private let kv = NSUbiquitousKeyValueStore.default
    private let filamentsKey  = "icloud_filaments_v1"
    private let jobsKey       = "icloud_printjobs_v1"
    private let backupDateKey = "icloud_backup_date_v1"

    private static let kvMaxBytes = 1_000_000   // iCloud KV store hard limit per app

    private init() {
        refreshAvailability()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(kvStoreDidChange),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kv
        )
        kv.synchronize()
    }

    // MARK: - Availability

    func refreshAvailability() {
        isAvailable = FileManager.default.ubiquityIdentityToken != nil
        let ts = kv.double(forKey: backupDateKey)
        if ts > 0 { lastBackupDate = Date(timeIntervalSince1970: ts) }
    }

    // MARK: - Backup

    func backup(filaments: [Filament], jobs: [PrintJob]) async {
        guard isAvailable else {
            await setStatus("iCloud not available. Sign in to iCloud in Settings.")
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let fData = try? encoder.encode(filaments),
              let jData = try? encoder.encode(jobs) else {
            await setStatus("Backup failed: encoding error.")
            return
        }
        let totalBytes = fData.count + jData.count
        if totalBytes > Self.kvMaxBytes {
            await setStatus("⚠️ Inventory too large for iCloud KV (\(totalBytes / 1024) KB). Only filaments backed up.")
            kv.set(fData, forKey: filamentsKey)
        } else {
            kv.set(fData, forKey: filamentsKey)
            kv.set(jData, forKey: jobsKey)
        }
        kv.set(Date().timeIntervalSince1970, forKey: backupDateKey)
        kv.synchronize()
        await MainActor.run {
            self.lastBackupDate = Date()
            self.statusMessage = "✅ Backed up \(totalBytes / 1024) KB to iCloud"
        }
    }

    // MARK: - Restore

    func restore() async throws -> (filaments: [Filament], jobs: [PrintJob]) {
        guard isAvailable else { throw BackupError.notAvailable }
        guard let fData = kv.data(forKey: filamentsKey) else { throw BackupError.noBackupFound }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let filaments = try decoder.decode([Filament].self, from: fData)
        var jobs: [PrintJob] = []
        if let jData = kv.data(forKey: jobsKey) {
            jobs = (try? decoder.decode([PrintJob].self, from: jData)) ?? []
        }
        return (filaments, jobs)
    }

    // MARK: - KV Change from another device

    @objc private func kvStoreDidChange(_ notification: Notification) {
        refreshAvailability()
    }

    @MainActor private func setStatus(_ msg: String) { statusMessage = msg }

    // MARK: - Errors

    enum BackupError: LocalizedError {
        case notAvailable
        case noBackupFound
        var errorDescription: String? {
            switch self {
            case .notAvailable:  return "iCloud is not available. Sign in to iCloud in Settings."
            case .noBackupFound: return "No iCloud backup found. Back up your inventory first."
            }
        }
    }
}
