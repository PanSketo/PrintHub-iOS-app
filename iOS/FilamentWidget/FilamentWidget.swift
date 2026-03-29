import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Widget-local credential cache (widget extension's own UserDefaults)
// These keys are private to the widget process — independent of App Groups.

private let kWidgetURL = "widget_nas_url"
private let kWidgetKey = "widget_api_key"

// MARK: - Configuration Intent

@available(iOS 17.0, *)
struct FilamentWidgetIntent: AppIntent, WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Printer Connection"
    static var description = IntentDescription("Enter your NAS URL and API key.")

    @Parameter(title: "NAS URL", default: "")
    var nasURL: String

    @Parameter(title: "API Key", default: "")
    var apiKey: String

    init() {
        // Pre-fill from widget's own cached values so the user sees their
        // previous entries when they open Edit Widget again.
        self.nasURL = UserDefaults.standard.string(forKey: kWidgetURL) ?? ""
        self.apiKey = UserDefaults.standard.string(forKey: kWidgetKey) ?? ""
    }

    init(nasURL: String, apiKey: String) {
        self.nasURL = nasURL
        self.apiKey = apiKey
    }
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

// MARK: - Resolve credentials (intent → widget cache → app group)

private func resolveCredentials(intentURL: String, intentKey: String) -> (url: String, key: String) {
    var url = intentURL.trimmingCharacters(in: .whitespaces)
    var key = intentKey.trimmingCharacters(in: .whitespaces)

    // Persist non-empty intent values into widget-local storage
    if !url.isEmpty { UserDefaults.standard.set(url, forKey: kWidgetURL) }
    if !key.isEmpty { UserDefaults.standard.set(key, forKey: kWidgetKey) }

    // Fall back to widget-local cache
    if url.isEmpty { url = UserDefaults.standard.string(forKey: kWidgetURL) ?? "" }
    if key.isEmpty { key = UserDefaults.standard.string(forKey: kWidgetKey) ?? "" }

    // Last resort: App Group shared by main app (works when properly signed)
    if url.isEmpty,
       let suite = UserDefaults(suiteName: "group.com.pansketo.filamentinventory") {
        url = suite.string(forKey: "nas_base_url") ?? ""
        key = suite.string(forKey: "nas_api_key") ?? ""
    }

    return (url, key)
}

// MARK: - Network fetch

private func fetchPrinterEntry(intentURL: String = "", intentKey: String = "") async -> PrintEntry {
    let (baseURL, apiKey) = resolveCredentials(intentURL: intentURL, intentKey: intentKey)

    guard !baseURL.isEmpty, let url = URL(string: "\(baseURL)/api/printer/state") else {
        return PrintEntry(date: Date(), status: "IDLE", printName: "",
                          progress: 0, remainingMinutes: 0, isConnected: false, isConfigured: false)
    }
    var request = URLRequest(url: url)
    request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
    request.timeoutInterval = 10
    do {
        let (data, _) = try await URLSession.shared.data(for: request)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let connected = json["connected"] as? Bool ?? false
            let live      = json["live"] as? [String: Any]
            let status    = live?["print_status"] as? String ?? "IDLE"
            return PrintEntry(
                date: Date(),
                status: status,
                printName: live?["print_name"] as? String ?? "",
                progress: live?["progress"] as? Int ?? 0,
                remainingMinutes: live?["remaining_minutes"] as? Int ?? 0,
                isConnected: connected,
                isConfigured: true
            )
        }
    } catch {}
    return PrintEntry(date: Date(), status: "IDLE", printName: "",
                      progress: 0, remainingMinutes: 0, isConnected: false, isConfigured: true)
}

private func nextRefresh(for entry: PrintEntry) -> Date {
    let interval: TimeInterval = (entry.status == "RUNNING" || entry.status == "PAUSE") ? 60 : 300
    return Date().addingTimeInterval(interval)
}

// MARK: - AppIntentTimelineProvider (iOS 17+)

@available(iOS 17.0, *)
struct IntentFilamentProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PrintEntry {
        // Use a "neutral" placeholder so iOS redaction isn't misleading
        PrintEntry(date: Date(), status: "IDLE", printName: "",
                   progress: 0, remainingMinutes: 0, isConnected: false, isConfigured: true)
    }

    func snapshot(for configuration: FilamentWidgetIntent, in context: Context) async -> PrintEntry {
        await fetchPrinterEntry(intentURL: configuration.nasURL, intentKey: configuration.apiKey)
    }

    func timeline(for configuration: FilamentWidgetIntent, in context: Context) async -> Timeline<PrintEntry> {
        let entry = await fetchPrinterEntry(intentURL: configuration.nasURL, intentKey: configuration.apiKey)
        return Timeline(entries: [entry], policy: .after(nextRefresh(for: entry)))
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
                Text("Hold widget\n→ Edit Widget\nto set NAS URL")
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

// MARK: - iOS 16/17 background compatibility

private struct WidgetBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(.fill.tertiary, for: .widget)
        } else {
            content
        }
    }
}

// MARK: - Widget Entry Point

@main
struct FilamentWidget: Widget {
    let kind = "FilamentWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: FilamentWidgetIntent.self,
                               provider: IntentFilamentProvider()) { entry in
            FilamentWidgetView(entry: entry)
        }
        .configurationDisplayName("Print Progress")
        .description("Live 3D print progress. Hold → Edit Widget to enter NAS URL & API Key.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
