import Foundation
import Combine

class NASService: ObservableObject {
    static let shared = NASService()

    @Published var isConfigured: Bool = false
    @Published var isConnected: Bool = false
    @Published var isSyncing: Bool = false
    @Published var lastSyncDate: Date?
    @Published var syncError: String?

    private let defaults = UserDefaults.standard
    private let baseURLKey = "nas_base_url"
    private let apiKeyKey = "nas_api_key"
    private var session: URLSession

    var baseURL: String {
        get { defaults.string(forKey: baseURLKey) ?? "" }
        set {
            defaults.set(newValue, forKey: baseURLKey)
            isConfigured = !newValue.isEmpty
        }
    }

    var apiKey: String {
        get { defaults.string(forKey: apiKeyKey) ?? "" }
        set { defaults.set(newValue, forKey: apiKeyKey) }
    }

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
        isConfigured = !defaults.string(forKey: baseURLKey).isNilOrEmpty

        // Auto-connect immediately on launch if already configured
        if isConfigured {
            Task { await self.autoConnect() }
        }
    }

    // MARK: - Date Decoder
    // Handles both ISO8601 without fractional seconds (iOS app) and with fractional
    // seconds ("2024-01-15T10:30:00.000Z") — which JavaScript's Date.toISOString() produces
    // and the MQTT bridge stores when it auto-logs print jobs and updates filaments.
    private static func makeDateDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { dec in
            let container = try dec.singleValueContainer()
            let str = try container.decode(String.self)
            let plain = ISO8601DateFormatter()
            if let d = plain.date(from: str) { return d }
            let frac = ISO8601DateFormatter()
            frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = frac.date(from: str) { return d }
            throw DecodingError.dataCorruptedError(in: container,
                debugDescription: "Cannot parse date: \(str)")
        }
        return decoder
    }

    // MARK: - Auto Connect
    // Called on launch, foreground restore, and after saving new NAS settings.
    // Verifies connection then triggers a full data sync on success.
    func autoConnect() async {
        guard isConfigured else { return }
        let connected = await testConnection()
        if connected {
            await MainActor.run {
                InventoryStore.shared.syncFromNAS()
            }
        }
    }

    // MARK: - Connection Test
    func testConnection() async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/health") else { return false }
        var request = URLRequest(url: url)
        request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
        do {
            let (_, response) = try await session.data(for: request)
            let connected = (response as? HTTPURLResponse)?.statusCode == 200
            await MainActor.run {
                self.isConnected = connected
                if connected { self.lastSyncDate = Date() }
            }
            return connected
        } catch {
            await MainActor.run { self.isConnected = false }
            return false
        }
    }

    // MARK: - Fetch All Filaments
    func fetchFilaments() async throws -> [Filament] {
        guard let url = URL(string: "\(baseURL)/api/filaments") else {
            throw NASError.invalidURL
        }
        var request = URLRequest(url: url)
        request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw NASError.serverError
        }
        let decoder = NASService.makeDateDecoder()
        return try decoder.decode([Filament].self, from: data)
    }

    // MARK: - Save Filament
    func saveFilament(_ filament: Filament) async throws {
        guard let url = URL(string: "\(baseURL)/api/filaments/\(filament.id)") else {
            throw NASError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(filament)
        let (_, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw NASError.serverError
        }
    }

    // MARK: - Add Filament
    func addFilament(_ filament: Filament) async throws {
        guard let url = URL(string: "\(baseURL)/api/filaments") else {
            throw NASError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(filament)
        let (_, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 201 else {
            throw NASError.serverError
        }
    }

    // MARK: - Delete Filament
    func deleteFilament(id: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/filaments/\(id)") else {
            throw NASError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
        let (_, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw NASError.serverError
        }
    }

    // MARK: - Add Print Job
    func addPrintJob(_ job: PrintJob) async throws {
        guard let url = URL(string: "\(baseURL)/api/printjobs") else {
            throw NASError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(job)
        let (_, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 201 else {
            throw NASError.serverError
        }
    }

    // MARK: - Fetch Print Jobs
    func fetchPrintJobs() async throws -> [PrintJob] {
        guard let url = URL(string: "\(baseURL)/api/printjobs") else {
            throw NASError.invalidURL
        }
        var request = URLRequest(url: url)
        request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw NASError.serverError
        }
        let decoder = NASService.makeDateDecoder()
        return try decoder.decode([PrintJob].self, from: data)
    }
    // MARK: - Printer Events
    struct PrinterEvent: Codable {
        let id: String
        let eventType: String
        let printName: String
        let reason: String?
        let createdAt: Date
    }

    /// Fetches print lifecycle events (started / completed / failed) newer than `since`.
    func fetchPrinterEvents(since: Date) async throws -> [PrinterEvent] {
        var components = URLComponents(string: "\(baseURL)/api/printer/events")
        let formatter = ISO8601DateFormatter()
        components?.queryItems = [URLQueryItem(name: "since", value: formatter.string(from: since))]
        guard let url = components?.url else { throw NASError.invalidURL }
        var request = URLRequest(url: url)
        request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw NASError.serverError }
        return try NASService.makeDateDecoder().decode([PrinterEvent].self, from: data)
    }

    /// Polls for new print events and fires local notifications. Rate-limited to once per 20 s.
    /// Call this from the Printer tab polling loop AND whenever the app returns to foreground.
    private var lastEventCheckAt: Date = .distantPast
    private let lastEventCheckKey = "last_print_event_check_iso"

    func checkPrintEvents() async {
        guard isConfigured, isConnected else { return }
        guard Date().timeIntervalSince(lastEventCheckAt) >= 20 else { return }
        lastEventCheckAt = Date()

        let defaults = UserDefaults.standard
        let formatter = ISO8601DateFormatter()

        guard let sinceIso = defaults.string(forKey: lastEventCheckKey),
              let since = formatter.date(from: sinceIso) else {
            // First launch — set cursor to now; don't notify for historical events
            defaults.set(formatter.string(from: Date()), forKey: lastEventCheckKey)
            return
        }

        do {
            let events = try await fetchPrinterEvents(since: since)
            defaults.set(formatter.string(from: Date()), forKey: lastEventCheckKey)
            for event in events {
                switch event.eventType {
                case "print_started":
                    NotificationManager.shared.notifyPrintStarted(printName: event.printName)
                case "print_completed":
                    NotificationManager.shared.notifyPrintCompleted(printName: event.printName)
                case "print_failed":
                    NotificationManager.shared.notifyPrintFailed(printName: event.printName, reason: event.reason)
                default:
                    break
                }
            }
        } catch { }
    }

    // MARK: - Printer State
    func fetchPrinterState() async throws -> PrinterState {
        guard let url = URL(string: "\(baseURL)/api/printer/state") else {
            throw NASError.invalidURL
        }
        var request = URLRequest(url: url)
        request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else {
            if statusCode == 401 { throw NASError.unauthorized }
            throw NASError.serverError
        }
        let decoder = NASService.makeDateDecoder()
        // Wrap in try? to get graceful nil instead of throw on partial decode failure
        if let state = try? decoder.decode(PrinterState.self, from: data) {
            return state
        }
        // If full decode fails, try to at least get the connected status
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let connected = json["connected"] as? Bool {
            return PrinterState(connected: connected, live: nil)
        }
        return PrinterState(connected: false, live: nil)
    }

    // MARK: - AMS Mappings
    func fetchAMSMappings() async throws -> [String: String] {
        guard let url = URL(string: "\(baseURL)/api/ams/mappings") else {
            throw NASError.invalidURL
        }
        var request = URLRequest(url: url)
        request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw NASError.serverError
        }
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    func saveAMSMapping(slotKey: String, filamentId: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/ams/mappings/\(slotKey)") else {
            throw NASError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.httpBody = try JSONEncoder().encode(["filamentId": filamentId])
        let (_, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw NASError.serverError
        }
    }

    // MARK: - Mirror Image
    /// Downloads a remote image URL onto the NAS and returns the local server URL.
    /// Returns nil silently if the NAS is not configured, unreachable, or the download fails,
    /// so callers can fall back to the original URL without crashing.
    func mirrorImage(remoteURL: String) async -> String? {
        guard isConfigured,
              let url = URL(string: "\(baseURL)/api/images/mirror") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["url": remoteURL])
        // Server needs up to 30 s to download the remote image — give iOS 60 s so the
        // server's own timeout fires first and we receive the 502 rather than race with it.
        request.timeoutInterval = 60
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let localURL = json["localURL"] else { return nil }
        return localURL
    }

    func deleteAMSMapping(slotKey: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/ams/mappings/\(slotKey)") else {
            throw NASError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
        let (_, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw NASError.serverError
        }
    }
}

// MARK: - NAS Errors
enum NASError: LocalizedError {
    case invalidURL
    case serverError
    case notConfigured
    case decodingError
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid NAS URL"
        case .serverError: return "NAS server returned an error"
        case .notConfigured: return "NAS is not configured"
        case .decodingError: return "Failed to decode response"
        case .unauthorized: return "API key incorrect — update Settings"
        }
    }
}

extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool { self == nil || self!.isEmpty }
}
