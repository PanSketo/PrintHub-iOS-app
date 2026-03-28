import WidgetKit
import SwiftUI

// MARK: - Data Model

struct PrintEntry: TimelineEntry {
    let date: Date
    let status: String        // IDLE, RUNNING, PAUSE, FINISH, FAILED
    let printName: String
    let progress: Int
    let remainingMinutes: Int
    let isConnected: Bool
}

// MARK: - Timeline Provider

struct FilamentProvider: TimelineProvider {
    private let appGroup = "group.com.pansketo.filamentinventory"
    private let baseURLKey = "nas_base_url"
    private let apiKeyKey  = "nas_api_key"

    func placeholder(in context: Context) -> PrintEntry {
        PrintEntry(date: Date(), status: "RUNNING", printName: "Benchy.3mf",
                   progress: 42, remainingMinutes: 75, isConnected: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (PrintEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PrintEntry>) -> Void) {
        let defaults  = UserDefaults(suiteName: appGroup)
        let baseURL   = defaults?.string(forKey: baseURLKey) ?? ""
        let apiKey    = defaults?.string(forKey: apiKeyKey)  ?? ""

        guard !baseURL.isEmpty, let url = URL(string: "\(baseURL)/api/printer/state") else {
            let entry = PrintEntry(date: Date(), status: "IDLE", printName: "",
                                   progress: 0, remainingMinutes: 0, isConnected: false)
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(300))))
            return
        }

        var request = URLRequest(url: url)
        request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { data, _, _ in
            var entry = PrintEntry(date: Date(), status: "IDLE", printName: "",
                                   progress: 0, remainingMinutes: 0, isConnected: false)
            if let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let connected = json["connected"] as? Bool ?? false
                let live      = json["live"] as? [String: Any]
                let status    = live?["print_status"] as? String ?? "IDLE"
                entry = PrintEntry(
                    date: Date(),
                    status: status,
                    printName: live?["print_name"] as? String ?? "",
                    progress: live?["progress"] as? Int ?? 0,
                    remainingMinutes: live?["remaining_minutes"] as? Int ?? 0,
                    isConnected: connected
                )
            }
            let isActive = entry.status == "RUNNING" || entry.status == "PAUSE"
            let next = Date().addingTimeInterval(isActive ? 60 : 300)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }.resume()
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
            // Header
            HStack {
                Image(systemName: isActive ? "printer.fill" : "printer")
                    .foregroundColor(statusColor)
                    .font(.caption)
                Text(statusLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(statusColor)
                Spacer()
                Circle()
                    .fill(entry.isConnected ? Color.green : Color.red)
                    .frame(width: 7, height: 7)
            }

            if isActive {
                // Print name
                Text(entry.printName.isEmpty ? "Print in progress" : entry.printName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(family == .systemSmall ? 1 : 2)

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(.systemFill))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(statusColor)
                            .frame(width: geo.size.width * CGFloat(entry.progress) / 100)
                    }
                }
                .frame(height: 6)

                // Progress + time
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
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func formatMinutes(_ mins: Int) -> String {
        mins < 60 ? "\(mins)m" : "\(mins / 60)h \(mins % 60)m"
    }
}

// MARK: - Widget Definition

struct FilamentWidget: Widget {
    let kind = "FilamentWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FilamentProvider()) { entry in
            FilamentWidgetView(entry: entry)
        }
        .configurationDisplayName("Print Progress")
        .description("Live 3D print progress from your Filament Inventory.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
