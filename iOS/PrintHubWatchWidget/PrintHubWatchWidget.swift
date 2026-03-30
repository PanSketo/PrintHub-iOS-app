import WidgetKit
import SwiftUI
import Security

// MARK: - Credential resolution (same Keychain as iOS app + widget)

private let kWidgetURL    = "widget_nas_url"
private let kWidgetKey    = "widget_nas_key"
private let kKeychainSvc  = "PrintHubNASConfig"
private let kKeychainAcct = "nas_credentials"

private func keychainLoad() -> (url: String, key: String)? {
    let query: [CFString: Any] = [
        kSecClass:       kSecClassGenericPassword,
        kSecAttrService: kKeychainSvc  as CFString,
        kSecAttrAccount: kKeychainAcct as CFString,
        kSecReturnData:  true,
        kSecMatchLimit:  kSecMatchLimitOne,
    ]
    var item: AnyObject?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
          let data = item as? Data,
          let str  = String(data: data, encoding: .utf8)
    else { return nil }
    let parts = str.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
    let url   = parts.count > 0 ? String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
    let key   = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
    return url.isEmpty && key.isEmpty ? nil : (url, key)
}

private func resolveCredentials() -> (url: String, key: String) {
    if let kc = keychainLoad(), !kc.url.isEmpty {
        UserDefaults.standard.set(kc.url, forKey: kWidgetURL)
        UserDefaults.standard.set(kc.key, forKey: kWidgetKey)
        return kc
    }
    let cachedURL = (UserDefaults.standard.string(forKey: kWidgetURL) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let cachedKey = (UserDefaults.standard.string(forKey: kWidgetKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if !cachedURL.isEmpty { return (cachedURL, cachedKey) }
    return ("", "")
}

// MARK: - Entry model

struct WatchPrintEntry: TimelineEntry {
    let date: Date
    let status: String
    let printName: String
    let progress: Int
    let remainingMinutes: Int
    let isConnected: Bool
    let isConfigured: Bool
}

// MARK: - Network fetch

private func fetchEntry() async -> WatchPrintEntry {
    let (baseURL, apiKey) = resolveCredentials()
    guard !baseURL.isEmpty,
          let url = URL(string: "\(baseURL)/api/printer/state") else {
        return WatchPrintEntry(date: Date(), status: "IDLE", printName: "",
                               progress: 0, remainingMinutes: 0,
                               isConnected: false, isConfigured: false)
    }
    var req = URLRequest(url: url)
    req.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
    req.timeoutInterval = 10
    do {
        let (data, _) = try await URLSession.shared.data(for: req)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let connected = json["connected"] as? Bool ?? false
            let live      = json["live"] as? [String: Any]
            let status    = live?["print_status"] as? String ?? "IDLE"
            return WatchPrintEntry(
                date: Date(),
                status: status,
                printName:        live?["print_name"]         as? String ?? "",
                progress:         live?["progress"]           as? Int    ?? 0,
                remainingMinutes: live?["remaining_minutes"]  as? Int    ?? 0,
                isConnected: connected,
                isConfigured: true
            )
        }
    } catch {}
    return WatchPrintEntry(date: Date(), status: "IDLE", printName: "",
                           progress: 0, remainingMinutes: 0,
                           isConnected: false, isConfigured: true)
}

// MARK: - Provider

struct WatchProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchPrintEntry {
        WatchPrintEntry(date: Date(), status: "RUNNING", printName: "Benchy",
                        progress: 72, remainingMinutes: 18,
                        isConnected: true, isConfigured: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchPrintEntry) -> Void) {
        Task { completion(await fetchEntry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchPrintEntry>) -> Void) {
        Task {
            let entry = await fetchEntry()
            let interval: Double = (entry.status == "RUNNING" || entry.status == "PAUSE") ? 60 : 300
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(interval))))
        }
    }
}

// MARK: - Complication views

private func formatMins(_ m: Int) -> String {
    m < 60 ? "\(m)m" : "\(m / 60)h \(m % 60)m"
}

// Circular — shows progress ring or printer icon
struct CircularView: View {
    let entry: WatchPrintEntry
    var body: some View {
        ZStack {
            if entry.status == "RUNNING" {
                Circle()
                    .trim(from: 0, to: CGFloat(entry.progress) / 100)
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(2)
                Text("\(entry.progress)%")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            } else {
                Image(systemName: entry.isConnected ? "printer.fill" : "printer")
                    .font(.title3)
                    .foregroundColor(entry.isConnected ? .orange : .secondary)
            }
        }
    }
}

// Rectangular — progress bar + remaining time
struct RectangularView: View {
    let entry: WatchPrintEntry

    var statusLabel: String {
        switch entry.status {
        case "RUNNING": return "Printing"
        case "PAUSE":   return "Paused"
        case "FINISH":  return "Finished"
        case "FAILED":  return "Failed"
        default:        return "PrintHub"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "printer.fill")
                    .font(.caption2)
                    .foregroundColor(.orange)
                Text(statusLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.orange)
                Spacer()
                if entry.status == "RUNNING" {
                    Text("\(entry.progress)%")
                        .font(.caption2.weight(.bold))
                }
            }
            if entry.status == "RUNNING" {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.3)).frame(height: 4)
                        Capsule().fill(Color.orange)
                            .frame(width: geo.size.width * CGFloat(entry.progress) / 100, height: 4)
                    }
                }
                .frame(height: 4)
                if entry.remainingMinutes > 0 {
                    Text("\(formatMins(entry.remainingMinutes)) left")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
                Text(entry.isConfigured
                     ? (entry.isConnected ? "Ready to print" : "Printer offline")
                     : "Open PrintHub")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// Inline — single line of text
struct InlineView: View {
    let entry: WatchPrintEntry
    var body: some View {
        if entry.status == "RUNNING" {
            Label("\(entry.progress)% · \(formatMins(entry.remainingMinutes)) left",
                  systemImage: "printer.fill")
        } else {
            Label(entry.isConnected ? "Printer ready" : "Printer offline",
                  systemImage: "printer")
        }
    }
}

// MARK: - Complication container

struct WatchComplicationView: View {
    let entry: WatchPrintEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularView(entry: entry)
        case .accessoryRectangular:
            RectangularView(entry: entry)
        case .accessoryInline:
            InlineView(entry: entry)
        default:
            CircularView(entry: entry)
        }
    }
}

// MARK: - Widget entry point

@main
struct PrintHubWatchWidget: Widget {
    let kind = "PrintHubWatchWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchProvider()) { entry in
            WatchComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Print Progress")
        .description("Live 3D print status on your wrist.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
