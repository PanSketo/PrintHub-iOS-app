import Foundation
import Combine

class InventoryStore: ObservableObject {
    static let shared = InventoryStore()

    @Published var filaments: [Filament] = []
    @Published var printJobs: [PrintJob] = []
    @Published var untrackedPrints: [NASService.UntrackedPrint] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var lowStockThreshold: Double = 200

    private let nas = NASService.shared
    private let localCacheKey = "local_filaments_cache"
    private let printJobsCacheKey = "local_printjobs_cache"

    // MARK: - Computed Stats
    var totalSpend: Double {
        filaments.reduce(0) { $0 + $1.pricePaid }
    }

    var totalFilaments: Int { filaments.count }

    var lowStockFilaments: [Filament] {
        filaments.filter { $0.remainingWeightG < lowStockThreshold && $0.remainingWeightG > 0 }
    }

    var emptyFilaments: [Filament] {
        filaments.filter { $0.isEmpty }
    }

    var totalWeightRemaining: Double {
        filaments.reduce(0) { $0 + $1.remainingWeightG }
    }

    var filamentsByType: [FilamentType: [Filament]] {
        Dictionary(grouping: filaments, by: { $0.type })
    }

    private init() {
        loadFromLocalCache()
    }

    // MARK: - Sync
    func syncFromNAS() {
        Task {
            await MainActor.run { self.isLoading = true }
            do {
                let fetchedFilaments = try await nas.fetchFilaments()
                let fetchedJobs = try await nas.fetchPrintJobs()
                await MainActor.run {
                    self.filaments = fetchedFilaments
                    self.printJobs = fetchedJobs
                    self.isLoading = false
                    self.saveToLocalCache()
                }
                refreshUntrackedPrints()
                // Back-fill missing images silently in background
                await backfillMissingImages(fetchedFilaments)
            } catch {
                await MainActor.run {
                    // Surface detailed decoding errors so schema mismatches are diagnosable
                    if let de = error as? DecodingError {
                        switch de {
                        case .keyNotFound(let key, _):
                            self.errorMessage = "Sync failed: missing field '\(key.stringValue)'"
                        case .valueNotFound(_, let ctx):
                            self.errorMessage = "Sync failed: null value — \(ctx.debugDescription)"
                        case .typeMismatch(_, let ctx):
                            self.errorMessage = "Sync failed: type mismatch — \(ctx.debugDescription)"
                        case .dataCorrupted(let ctx):
                            self.errorMessage = "Sync failed: bad data — \(ctx.debugDescription)"
                        @unknown default:
                            self.errorMessage = error.localizedDescription
                        }
                    } else {
                        self.errorMessage = error.localizedDescription
                    }
                    self.isLoading = false
                }
            }
        }
    }

    // Fetch and permanently save imageURL for any filament that is missing one,
    // and mirror any remote image URLs to the NAS for local caching.
    private func backfillMissingImages(_ filaments: [Filament]) async {
        let nasBase = nas.baseURL
        var anyChange = false

        for filament in filaments {
            var updated = filament
            var changed = false

            // Step 1: If no imageURL at all, search for one
            if updated.imageURL == nil {
                let imageURL = await FilamentLookupService.shared.searchFilamentImage(
                    brand: filament.brand,
                    color: filament.color.name,
                    type: filament.type.rawValue
                )
                if let imageURL = imageURL {
                    updated.imageURL = imageURL
                    changed = true
                }
            }

            // Step 2: If imageURL exists but is still a remote URL (not yet on NAS), mirror it
            if let currentURL = updated.imageURL,
               !nasBase.isEmpty,
               !currentURL.hasPrefix(nasBase) {
                if let mirrored = await nas.mirrorImage(remoteURL: currentURL) {
                    updated.imageURL = mirrored
                    changed = true
                } else {
                    // Mirror failed (broken URL or download error) — clear so next sync retries fresh
                    updated.imageURL = nil
                    changed = true
                }
            }

            guard changed else { continue }
            anyChange = true

            let snapshot = updated   // immutable copy — avoids Swift 6 captured-var warning
            await MainActor.run {
                if let idx = self.filaments.firstIndex(where: { $0.id == filament.id }) {
                    self.filaments[idx] = snapshot
                }
            }
            try? await nas.saveFilament(snapshot)
        }

        if anyChange {
            await MainActor.run { self.saveToLocalCache() }
        }
    }

    // MARK: - Add Filament
    func addFilament(_ filament: Filament) {
        Task {
            do {
                try await nas.addFilament(filament)
                await MainActor.run {
                    self.filaments.append(filament)
                    self.saveToLocalCache()
                    NotificationManager.shared.scheduleAlertIfNeeded(for: filament)
                }
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
            }
        }
    }

    // MARK: - Update Filament
    func updateFilament(_ filament: Filament) {
        Task {
            do {
                try await nas.saveFilament(filament)
                await MainActor.run {
                    if let idx = self.filaments.firstIndex(where: { $0.id == filament.id }) {
                        self.filaments[idx] = filament
                        self.saveToLocalCache()
                        NotificationManager.shared.scheduleAlertIfNeeded(for: filament)
                    }
                }
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
            }
        }
    }

    // MARK: - Delete Filament

    /// Immediately removes from the local array and returns the filament for undo.
    /// Call confirmDelete(id:) after the undo window to remove from NAS.
    @MainActor
    func removeLocally(id: String) -> Filament? {
        guard let idx = filaments.firstIndex(where: { $0.id == id }) else { return nil }
        let filament = filaments[idx]
        filaments.remove(at: idx)
        saveToLocalCache()
        return filament
    }

    /// Restores a previously removed filament (undo path).
    @MainActor
    func restore(_ filament: Filament) {
        filaments.append(filament)
        filaments.sort { $0.brand.lowercased() < $1.brand.lowercased() }
        saveToLocalCache()
    }

    /// Commits the delete to NAS — call this after the undo window expires.
    func confirmDelete(id: String) {
        Task {
            do {
                try await nas.deleteFilament(id: id)
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
            }
        }
    }

    func deleteFilament(id: String) {
        Task {
            do {
                try await nas.deleteFilament(id: id)
                await MainActor.run {
                    self.filaments.removeAll { $0.id == id }
                    self.saveToLocalCache()
                }
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
            }
        }
    }

    // MARK: - Log Print Job
    func logPrintJob(_ job: PrintJob) {
        Task {
            do {
                // Stamp the cost at log time (price per gram × grams used)
                let costEUR: Double? = await MainActor.run {
                    guard let filament = self.filaments.first(where: { $0.id == job.filamentId }),
                          filament.totalWeightG > 0 else { return nil }
                    return (filament.pricePaid / filament.totalWeightG) * job.weightUsedG
                }
                var jobWithCost = job
                jobWithCost.costEUR = costEUR

                try await nas.addPrintJob(jobWithCost)
                // Capture the updated filament inside MainActor, then persist outside
                let updatedFilament: Filament? = await MainActor.run {
                    self.printJobs.append(jobWithCost)
                    guard let idx = self.filaments.firstIndex(where: { $0.id == jobWithCost.filamentId }) else { return nil }
                    var updated = self.filaments[idx]
                    updated.remainingWeightG = max(0, updated.remainingWeightG - jobWithCost.weightUsedG)
                    updated.stockStatus = StockStatus.from(remaining: updated.remainingWeightG, total: updated.totalWeightG)
                    updated.lastUpdated = Date()
                    updated.printJobs.append(jobWithCost)
                    self.filaments[idx] = updated
                    self.saveToLocalCache()
                    NotificationManager.shared.scheduleAlertIfNeeded(for: updated)
                    return updated
                }
                // Persist to NAS using the captured value — no race condition
                if let filament = updatedFilament {
                    try await nas.saveFilament(filament)
                }

            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
            }
        }
    }

    // MARK: - Untracked Prints

    func refreshUntrackedPrints() {
        Task {
            guard nas.isConfigured else { return }
            if let prints = try? await nas.fetchUntrackedPrints() {
                await MainActor.run { self.untrackedPrints = prints }
            }
        }
    }

    func logUntrackedPrint(eventId: String, filamentId: String, printName: String, weightG: Double, durationSeconds: Double?, success: Bool) {
        let job = PrintJob(
            id: UUID().uuidString,
            filamentId: filamentId,
            printName: printName,
            weightUsedG: weightG,
            duration: durationSeconds,
            date: Date(),
            notes: "Manually logged",
            success: success
        )
        logPrintJob(job)
        Task {
            try? await nas.clearUntrackedPrint(id: eventId)
            await MainActor.run {
                self.untrackedPrints.removeAll { $0.id == eventId }
            }
        }
    }

    // MARK: - Filter
    func filteredFilaments(searchText: String, type: FilamentType?, status: StockStatus?) -> [Filament] {
        filaments.filter { f in
            let matchesSearch = searchText.isEmpty ||
                f.brand.localizedCaseInsensitiveContains(searchText) ||
                f.color.name.localizedCaseInsensitiveContains(searchText) ||
                f.type.rawValue.localizedCaseInsensitiveContains(searchText) ||
                f.sku.localizedCaseInsensitiveContains(searchText)
            let matchesType = type == nil || f.type == type
            let matchesStatus = status == nil || f.stockStatus == status
            return matchesSearch && matchesType && matchesStatus
        }
    }

    // MARK: - Local Cache
    private func saveToLocalCache() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(filaments) {
            UserDefaults.standard.set(data, forKey: localCacheKey)
        }
        if let data = try? encoder.encode(printJobs) {
            UserDefaults.standard.set(data, forKey: printJobsCacheKey)
        }
    }

    private func loadFromLocalCache() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = UserDefaults.standard.data(forKey: localCacheKey),
           let cached = try? decoder.decode([Filament].self, from: data) {
            self.filaments = cached
        }
        if let data = UserDefaults.standard.data(forKey: printJobsCacheKey),
           let cached = try? decoder.decode([PrintJob].self, from: data) {
            self.printJobs = cached
        }
    }
}
