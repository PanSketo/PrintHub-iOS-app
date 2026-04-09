import Foundation
import Combine
import Security

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

    private let appGroupSuite = "group.com.pansketo.filamentinventory"

    var baseURL: String {
        get { defaults.string(forKey: baseURLKey) ?? "" }
        set {
            defaults.set(newValue, forKey: baseURLKey)
            UserDefaults(suiteName: appGroupSuite)?.set(newValue, forKey: baseURLKey)
            isConfigured = !newValue.isEmpty
            NASKeychainBridge.save(url: newValue, key: defaults.string(forKey: apiKeyKey) ?? "")
        }
    }

    var apiKey: String {
        get { defaults.string(forKey: apiKeyKey) ?? "" }
        set {
            defaults.set(newValue, forKey: apiKeyKey)
            UserDefaults(suiteName: appGroupSuite)?.set(newValue, forKey: apiKeyKey)
            NASKeychainBridge.save(url: defaults.string(forKey: baseURLKey) ?? "", key: newValue)
        }
    }

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
        isConfigured = !defaults.string(forKey: baseURLKey).isNilOrEmpty

        // Mirror current values to App Group + Keychain so widget can always read them.
        let url = defaults.string(forKey: baseURLKey) ?? ""
        let key = defaults.string(forKey: apiKeyKey) ?? ""
        let suite = UserDefaults(suiteName: appGroupSuite)
        if !url.isEmpty { suite?.set(url, forKey: baseURLKey) }
        if !key.isEmpty { suite?.set(key, forKey: apiKeyKey) }
        // Keychain is shared between app and widget extension by default team ID
        if !url.isEmpty || !key.isEmpty {
            NASKeychainBridge.save(url: url, key: key)
        }

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

    func updatePrintJob(_ job: PrintJob) async throws {
        guard let url = URL(string: "\(baseURL)/api/printjobs/\(job.id)") else {
            throw NASError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(job)
        let (_, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw NASError.serverError }
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

    // MARK: - Untracked Prints

    struct UntrackedPrint: Decodable, Identifiable {
        let id: String
        let printName: String
        let createdAt: Date
        let activeSlotKey: String?
        let durationSeconds: Double?

        enum CodingKeys: String, CodingKey {
            case id, printName, createdAt, reason
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id        = try c.decode(String.self, forKey: .id)
            printName = try c.decode(String.self, forKey: .printName)
            createdAt = try c.decode(Date.self,   forKey: .createdAt)
            if let reasonStr = try? c.decode(String.self, forKey: .reason),
               let data = reasonStr.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                activeSlotKey   = json["activeSlotKey"]   as? String
                durationSeconds = json["durationSeconds"] as? Double
            } else {
                activeSlotKey   = nil
                durationSeconds = nil
            }
        }
    }

    func fetchUntrackedPrints() async throws -> [UntrackedPrint] {
        guard let url = URL(string: "\(baseURL)/api/printer/untracked-prints") else {
            throw NASError.invalidURL
        }
        var request = URLRequest(url: url)
        request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw NASError.serverError }
        return try NASService.makeDateDecoder().decode([UntrackedPrint].self, from: data)
    }

    func clearUntrackedPrint(id: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/printer/untracked-prints/\(id)") else {
            throw NASError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
        let (_, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw NASError.serverError }
    }

    /// Polls for new print events and fires local notifications. Rate-limited to once per 20 s
    /// per printer. Accepts an optional PrinterConfig; falls back to the global NAS when nil.
    private var lastEventCheckByPrinter: [String: Date] = [:]
    private let lastEventCheckKey = "last_print_event_check_iso"

    func checkPrintEvents(using config: PrinterConfig? = nil) async {
        guard isConfigured, isConnected else { return }

        // Rate-limit key: printer id if known, else "default"
        let rateKey = config?.id ?? "default"
        let last = lastEventCheckByPrinter[rateKey] ?? .distantPast
        guard Date().timeIntervalSince(last) >= 20 else { return }
        lastEventCheckByPrinter[rateKey] = Date()

        // Persist cursor per printer so events from different printers don't clobber each other
        let defaults = UserDefaults.standard
        let cursorKey = lastEventCheckKey + "_" + rateKey
        let formatter = ISO8601DateFormatter()

        guard let sinceIso = defaults.string(forKey: cursorKey),
              let since = formatter.date(from: sinceIso) else {
            // First run — set cursor to now; don't notify for historical events
            defaults.set(formatter.string(from: Date()), forKey: cursorKey)
            return
        }

        // Fetch events from the correct backend
        let base = config?.nasURL ?? baseURL
        let key  = config?.apiKey ?? apiKey
        var components = URLComponents(string: "\(base)/api/printer/events")
        components?.queryItems = [URLQueryItem(name: "since", value: formatter.string(from: since))]
        guard let url = components?.url else { return }
        var request = URLRequest(url: url)
        request.addValue(key, forHTTPHeaderField: "X-API-Key")

        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let events = try NASService.makeDateDecoder().decode([PrinterEvent].self, from: data)
            defaults.set(formatter.string(from: Date()), forKey: cursorKey)
            for event in events {
                switch event.eventType {
                case "print_started":
                    NotificationManager.shared.notifyPrintStarted(printName: event.printName)
                case "print_completed":
                    NotificationManager.shared.notifyPrintCompleted(printName: event.printName)
                case "print_failed":
                    NotificationManager.shared.notifyPrintFailed(printName: event.printName, reason: event.reason)
                case "print_untracked":
                    NotificationManager.shared.notifyPrintUntracked(printName: event.printName)
                    await MainActor.run { InventoryStore.shared.refreshUntrackedPrints() }
                default:
                    break
                }
            }
        } catch { }
    }

    // MARK: - Printer State
    // Accepts an optional PrinterConfig; falls back to the global NAS credentials when nil.
    func fetchPrinterState(using config: PrinterConfig? = nil) async throws -> PrinterState {
        let base = config?.nasURL ?? baseURL
        let key  = config?.apiKey ?? apiKey
        guard let url = URL(string: "\(base)/api/printer/state") else {
            throw NASError.invalidURL
        }
        var request = URLRequest(url: url)
        request.addValue(key, forHTTPHeaderField: "X-API-Key")
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
    func fetchAMSMappings(using config: PrinterConfig? = nil) async throws -> [String: String] {
        let base = config?.nasURL ?? baseURL
        let key  = config?.apiKey ?? apiKey
        guard let url = URL(string: "\(base)/api/ams/mappings") else {
            throw NASError.invalidURL
        }
        var request = URLRequest(url: url)
        request.addValue(key, forHTTPHeaderField: "X-API-Key")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw NASError.serverError
        }
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    func saveAMSMapping(slotKey: String, filamentId: String, using config: PrinterConfig? = nil) async throws {
        let base = config?.nasURL ?? baseURL
        let key  = config?.apiKey ?? apiKey
        guard let url = URL(string: "\(base)/api/ams/mappings/\(slotKey)") else {
            throw NASError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(key, forHTTPHeaderField: "X-API-Key")
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

    // MARK: - Printer Commands
    func sendPrinterCommand(_ command: String, value: String? = nil, using config: PrinterConfig? = nil) async throws {
        let base = config?.nasURL ?? baseURL
        let key  = config?.apiKey ?? apiKey
        guard let url = URL(string: "\(base)/api/printer/command") else { throw NASError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(key, forHTTPHeaderField: "X-API-Key")
        var body: [String: Any] = ["command": command]
        if let v = value { body["value"] = v }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 15
        let (_, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw NASError.serverError }
    }

    // MARK: - Chamber Light
    func fetchLightState() async -> Bool? {
        guard let url = URL(string: "\(baseURL)/api/printer/light") else { return nil }
        var request = URLRequest(url: url)
        request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let known = json["known"] as? Bool, known,
              let on = json["on"] as? Bool else { return nil }
        return on
    }

    func setLight(on: Bool) async throws {
        guard let url = URL(string: "\(baseURL)/api/printer/light") else { throw NASError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["on": on])
        request.timeoutInterval = 15
        let (_, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw NASError.serverError }
    }

    func deleteAMSMapping(slotKey: String, using config: PrinterConfig? = nil) async throws {
        let base = config?.nasURL ?? baseURL
        let key  = config?.apiKey ?? apiKey
        guard let url = URL(string: "\(base)/api/ams/mappings/\(slotKey)") else {
            throw NASError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.addValue(key, forHTTPHeaderField: "X-API-Key")
        let (_, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw NASError.serverError
        }
    }

    // MARK: - Printer File Browser

    /// Lists files on the printer's internal / USB storage.
    /// Backend connects to the printer via implicit FTPS (port 990).
    func fetchPrinterFiles(path: String = "/", using config: PrinterConfig? = nil) async throws -> [PrinterFile] {
        let base = config?.nasURL ?? baseURL
        let key  = config?.apiKey ?? apiKey
        var components = URLComponents(string: "\(base)/api/printer/files")
        components?.queryItems = [URLQueryItem(name: "path", value: path)]
        guard let url = components?.url else { throw NASError.invalidURL }
        var request = URLRequest(url: url)
        request.addValue(key, forHTTPHeaderField: "X-API-Key")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw NASError.serverError }
        return try JSONDecoder().decode([PrinterFile].self, from: data)
    }

    /// Returns a URL for the .3mf thumbnail endpoint, with ?key= for AsyncImage compatibility.
    func thumbnailURL(forFile filePath: String, using config: PrinterConfig? = nil) -> URL? {
        let base = config?.nasURL ?? baseURL
        let key  = config?.apiKey ?? apiKey
        var comps = URLComponents(string: "\(base)/api/printer/thumbnail")
        comps?.queryItems = [
            URLQueryItem(name: "path", value: filePath),
            URLQueryItem(name: "key",  value: key),
        ]
        return comps?.url
    }

    /// Sends a project_file print command to the printer via the backend.
    func startPrint(filePath: String, using config: PrinterConfig? = nil) async throws {
        let base = config?.nasURL ?? baseURL
        let key  = config?.apiKey ?? apiKey
        guard let url = URL(string: "\(base)/api/printer/print") else { throw NASError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(key, forHTTPHeaderField: "X-API-Key")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["file_path": filePath])
        request.timeoutInterval = 30
        let (_, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw NASError.serverError }
    }

    // MARK: - Timelapse

    /// Lists .mp4 timelapse files stored on the printer's SD card.
    func fetchTimelapses(using config: PrinterConfig? = nil) async throws -> [TimelapseFile] {
        let base = config?.nasURL ?? baseURL
        let key  = config?.apiKey ?? apiKey
        guard let url = URL(string: "\(base)/api/printer/timelapse") else { throw NASError.invalidURL }
        var request = URLRequest(url: url)
        request.addValue(key, forHTTPHeaderField: "X-API-Key")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw NASError.serverError }
        return try JSONDecoder().decode([TimelapseFile].self, from: data)
    }

    /// Returns an HTTP URL that streams the timelapse from the NAS backend proxy.
    /// Uses ?key= query parameter so AVPlayer can fetch it without custom headers.
    func timelapseStreamURL(path: String, using config: PrinterConfig? = nil) -> URL? {
        let base = config?.nasURL ?? baseURL
        let key  = config?.apiKey ?? apiKey
        var components = URLComponents(string: "\(base)/api/printer/timelapse/stream")
        components?.queryItems = [
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "key",  value: key)
        ]
        return components?.url
    }

    /// Downloads a timelapse video to the temp directory and returns the local URL.
    func downloadTimelapse(path: String, using config: PrinterConfig? = nil) async throws -> URL {
        guard let streamURL = timelapseStreamURL(path: path, using: config) else {
            throw NASError.invalidURL
        }
        let fileName = path.split(separator: "/").last.map(String.init) ?? "timelapse.mp4"
        let tempURL  = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        let downloadSession = URLSession(configuration: {
            let c = URLSessionConfiguration.default
            c.timeoutIntervalForRequest  = 120
            c.timeoutIntervalForResource = 300
            return c
        }())
        let (localURL, response) = try await downloadSession.download(from: streamURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw NASError.serverError }
        if FileManager.default.fileExists(atPath: tempURL.path) {
            try? FileManager.default.removeItem(at: tempURL)
        }
        try FileManager.default.moveItem(at: localURL, to: tempURL)
        return tempURL
    }

    func deleteTimelapse(path: String, using config: PrinterConfig? = nil) async throws {
        let base = config?.nasURL ?? baseURL
        let key  = config?.apiKey ?? apiKey
        guard var components = URLComponents(string: "\(base)/api/printer/timelapse") else {
            throw NASError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        guard let url = components.url else { throw NASError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.addValue(key, forHTTPHeaderField: "X-API-Key")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            // Surface the actual FTP error message from the server
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw NASError.custom(msg ?? "Server error")
        }
    }
}

// MARK: - Printer File Model

struct PrinterFile: Codable, Identifiable {
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int?
    let modifiedDate: String?

    var id: String { path }

    var displaySize: String? {
        guard let s = size, !isDirectory else { return nil }
        if s < 1_024             { return "\(s) B" }
        if s < 1_048_576         { return "\(s / 1_024) KB" }
        return String(format: "%.1f MB", Double(s) / 1_048_576)
    }

    var isPrintable: Bool {
        let l = name.lowercased()
        return l.hasSuffix(".3mf") || l.hasSuffix(".gcode") || l.hasSuffix(".gcode.3mf")
    }

    var friendlyName: String {
        switch name.lowercased() {
        case "sdcard": return "Internal Storage"
        case "usb":    return "USB Drive"
        default:       return name
        }
    }
}

// MARK: - Timelapse File Model

struct TimelapseFile: Codable, Identifiable {
    let name: String
    let path: String
    let size: Int?
    let modifiedDate: String?

    var id: String { path }

    var displaySize: String? {
        guard let s = size else { return nil }
        if s < 1_048_576 { return "\(s / 1_024) KB" }
        return String(format: "%.1f MB", Double(s) / 1_048_576)
    }

    /// Human-readable name: strips ".mp4" suffix.
    var displayName: String {
        name.hasSuffix(".mp4") ? String(name.dropLast(4)) : name
    }
}

// MARK: - NAS Errors
enum NASError: LocalizedError {
    case invalidURL
    case serverError
    case notConfigured
    case decodingError
    case unauthorized
    case notFound
    case custom(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:    return "Invalid NAS URL"
        case .serverError:   return "NAS server returned an error"
        case .notConfigured: return "NAS is not configured"
        case .decodingError: return "Failed to decode response"
        case .unauthorized:  return "API key incorrect — update Settings"
        case .notFound:      return "No backup found on NAS"
        case .custom(let msg): return msg
        }
    }
}

// MARK: - NAS Backup / Restore
extension NASService {
    func uploadFullBackup(_ data: Data) async throws {
        guard let url = URL(string: "\(baseURL)/api/backup") else { throw NASError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        let (_, response) = try await session.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw NASError.serverError }
    }

    func downloadFullBackup() async throws -> Data {
        guard let url = URL(string: "\(baseURL)/api/backup") else { throw NASError.invalidURL }
        var req = URLRequest(url: url)
        req.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw NASError.serverError }
        if http.statusCode == 404 { throw NASError.notFound }
        guard http.statusCode == 200 else { throw NASError.serverError }
        return data
    }

    func restoreToNAS(filaments: [Filament], printJobs: [PrintJob]) async throws {
        guard let url = URL(string: "\(baseURL)/api/restore") else { throw NASError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct Payload: Encodable { let filaments: [Filament]; let printJobs: [PrintJob] }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        req.httpBody = try encoder.encode(Payload(filaments: filaments, printJobs: printJobs))
        let (_, response) = try await session.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw NASError.serverError }
    }
}

extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool {
        guard let value = self else { return true }
        return value.isEmpty
    }
}
