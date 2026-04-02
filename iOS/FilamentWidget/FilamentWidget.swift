import WidgetKit
import SwiftUI
import Security

// MARK: - Credential resolution
// Priority order: Keychain (shared with main app) → App Group → own cache

private let kWidgetURL    = "widget_nas_url"
private let kWidgetKey    = "widget_nas_key"
private let kKeychainSvc  = "PrintHubNASConfig"
private let kKeychainAcct = "nas_credentials"
private let kAppGroupSuite = "group.com.pansketo.filamentinventory"
private let kGroupURL      = "nas_base_url"
private let kGroupKey      = "nas_api_key"

/// Reads the NAS credentials written by the main app.
/// App extensions automatically inherit access to the containing app's
/// default Keychain group (same Team ID) — no entitlement needed.
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

    // Try JSON format first (current main app format)
    if let jsonData = str.data(using: .utf8),
       let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: String],
       let url = json["url"], let key = json["key"], !url.isEmpty {
        return (url, key)
    }
    // Fall back to legacy newline-delimited format
    let parts = str.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
    let url   = parts.count > 0 ? String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
    let key   = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
    return url.isEmpty && key.isEmpty ? nil : (url, key)
}

private func resolveCredentials() -> (url: String, key: String) {
    // 1. Keychain (set by main app; shared automatically with extension)
    if let kc = keychainLoad(), !kc.url.isEmpty {
        // Cache locally so we have them even if Keychain is briefly unavailable
        UserDefaults.standard.set(kc.url, forKey: kWidgetURL)
        UserDefaults.standard.set(kc.key, forKey: kWidgetKey)
        return kc
    }

    // 2. Widget's own UserDefaults (populated on previous successful Keychain read)
    let cachedURL = (UserDefaults.standard.string(forKey: kWidgetURL) ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
    let cachedKey = (UserDefaults.standard.string(forKey: kWidgetKey) ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
    if !cachedURL.isEmpty { return (cachedURL, cachedKey) }

    // 3. App Group UserDefaults (works when properly signed / not sideloaded)
    if let suite = UserDefaults(suiteName: kAppGroupSuite) {
        let groupURL = (suite.string(forKey: kGroupURL) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let groupKey = (suite.string(forKey: kGroupKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !groupURL.isEmpty { return (groupURL, groupKey) }
    }

    return ("", "")
}

// MARK: - Data Model

struct PrintEntry: TimelineEntry {
    let date: Date
    let status: String
    let printName: String
    let progress: Int
    let remainingMinutes: Int
    let isConnected: Bool
    let isConfigured: Bool
}

// MARK: - Network fetch

private func fetchPrinterEntry() async -> PrintEntry {
    let (baseURL, apiKey) = resolveCredentials()

    guard !baseURL.isEmpty,
          let url = URL(string: "\(baseURL)/api/printer/state") else {
        return PrintEntry(date: Date(), status: "IDLE", printName: "",
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
            return PrintEntry(
                date: Date(),
                status: status,
                printName: live?["print_name"]        as? String ?? "",
                progress:  live?["progress"]          as? Int    ?? 0,
                remainingMinutes: live?["remaining_minutes"] as? Int ?? 0,
                isConnected: connected,
                isConfigured: true
            )
        }
    } catch {}
    return PrintEntry(date: Date(), status: "IDLE", printName: "",
                      progress: 0, remainingMinutes: 0,
                      isConnected: false, isConfigured: true)
}

private func nextRefresh(for entry: PrintEntry) -> Date {
    let mins: Double = (entry.status == "RUNNING" || entry.status == "PAUSE") ? 1 : 5
    return Date().addingTimeInterval(mins * 60)
}

// MARK: - Static Provider

struct FilamentProvider: TimelineProvider {
    func placeholder(in context: Context) -> PrintEntry {
        PrintEntry(date: Date(), status: "IDLE", printName: "",
                   progress: 0, remainingMinutes: 0,
                   isConnected: false, isConfigured: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (PrintEntry) -> Void) {
        Task { completion(await fetchPrinterEntry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PrintEntry>) -> Void) {
        Task {
            let entry = await fetchPrinterEntry()
            let nextDate = nextRefresh(for: entry)
            completion(Timeline(entries: [entry], policy: .after(nextDate)))
        }
    }
}

// MARK: - Widget View

struct FilamentWidgetView: View {
    var entry: PrintEntry
    @Environment(\.widgetFamily) var family

    var statusColor: Color {
        switch entry.status {
        case "RUNNING": return .blue
        case "PAUSE":   return .orange
        case "FINISH":  return .green
        case "FAILED":  return .red
        default:        return .secondary
        }
    }

    var statusLabel: String {
        switch entry.status {
        case "RUNNING": return "Printing"
        case "PAUSE":   return "Paused"
        case "FINISH":  return "Finished"
        case "FAILED":  return "Failed"
        default:        return "Idle"
        }
    }

    var isActive: Bool { entry.status == "RUNNING" || entry.status == "PAUSE" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: isActive ? "printer.fill" : "printer")
                    .foregroundColor(statusColor)
                    .font(.caption)
                Text(statusLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(statusColor)
                Spacer()
                Circle()
                    .fill(entry.isConnected ? Color.green : Color.gray)
                    .frame(width: 7, height: 7)
            }

            if !entry.isConfigured {
                Spacer()
                Text("Open PrintHub\nto activate widget")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else if isActive {
                Text(entry.printName.isEmpty ? "Print in progress" : entry.printName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(family == .systemSmall ? 1 : 2)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(Color(.systemFill))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(statusColor)
                            .frame(width: geo.size.width * CGFloat(entry.progress) / 100)
                    }
                }
                .frame(height: 6)

                HStack(alignment: .bottom) {
                    Text("\(entry.progress)%")
                        .font(.title2.weight(.black))
                        .foregroundColor(statusColor)
                    Spacer()
                    if entry.remainingMinutes > 0 {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(formatMinutes(entry.remainingMinutes))
                                .font(.caption.weight(.semibold))
                            Text("left")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } else {
                Spacer()
                Text(entry.isConnected ? "Ready to print" : "Printer offline")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding()
        .modifier(WidgetBackgroundModifier())
    }

    private func formatMinutes(_ mins: Int) -> String {
        mins < 60 ? "\(mins)m" : "\(mins / 60)h \(mins % 60)m"
    }
}

// MARK: - Background compat

private struct WidgetBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(.fill.tertiary, for: .widget)
        } else {
            content
        }
    }
}

// MARK: - Entry Point

@main
struct FilamentWidget: Widget {
    let kind = "FilamentWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FilamentProvider()) { entry in
            FilamentWidgetView(entry: entry)
        }
        .configurationDisplayName("Print Progress")
        .description("Live 3D print progress. Open PrintHub once to activate.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
