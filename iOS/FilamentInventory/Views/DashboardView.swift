import SwiftUI

// MARK: - Dashboard Card Identifiers

enum DashboardCard: String, CaseIterable, Identifiable {
    case statsSpools    = "stats_spools"
    case statsWeight    = "stats_weight"
    case syncStatus     = "sync_status"
    case camera         = "camera"
    case lowStock       = "low_stock"
    case typeBreakdown  = "type_breakdown"
    case recentPrints   = "recent_prints"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .statsSpools:   return "Spools & Spend"
        case .statsWeight:   return "Weight & Low Stock"
        case .syncStatus:    return "NAS Status"
        case .camera:        return "Camera Feed"
        case .lowStock:      return "Low Stock Alerts"
        case .typeBreakdown: return "Filament by Type"
        case .recentPrints:  return "Recent Prints"
        }
    }

    var icon: String {
        switch self {
        case .statsSpools:   return "shippingbox.fill"
        case .statsWeight:   return "scalemass.fill"
        case .syncStatus:    return "wifi"
        case .camera:        return "camera.fill"
        case .lowStock:      return "exclamationmark.triangle.fill"
        case .typeBreakdown: return "chart.bar.fill"
        case .recentPrints:  return "printer.fill"
        }
    }
}

// MARK: - Dashboard Layout Store

class DashboardLayoutStore: ObservableObject {
    private let key = "dashboard_layout_v1"

    struct CardConfig: Codable, Identifiable {
        var id: String
        var isVisible: Bool
    }

    @Published var cards: [CardConfig]

    init() {
        if let data = UserDefaults.standard.data(forKey: "dashboard_layout_v1"),
           let saved = try? JSONDecoder().decode([CardConfig].self, from: data) {
            // Keep stored order/visibility; append any new cards added in future updates
            var result = saved.filter { DashboardCard(rawValue: $0.id) != nil }
            let stored = Set(result.map { $0.id })
            for card in DashboardCard.allCases where !stored.contains(card.rawValue) {
                result.append(CardConfig(id: card.rawValue, isVisible: true))
            }
            self.cards = result
        } else {
            self.cards = DashboardCard.allCases.map { CardConfig(id: $0.rawValue, isVisible: true) }
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(cards) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    var visibleCards: [DashboardCard] {
        cards.compactMap { c in
            guard c.isVisible, let card = DashboardCard(rawValue: c.id) else { return nil }
            return card
        }
    }
}

// MARK: - Dashboard View

struct DashboardView: View {
    @EnvironmentObject var store: InventoryStore
    @EnvironmentObject var nasService: NASService
    @StateObject private var layout = DashboardLayoutStore()
    @State private var showCustomize = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    ForEach(layout.visibleCards) { card in
                        cardView(for: card)
                    }
                }
                .padding()
            }
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showCustomize = true } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { store.syncFromNAS() }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .refreshable { store.syncFromNAS() }
            .sheet(isPresented: $showCustomize) {
                DashboardCustomizeSheet(layout: layout)
            }
        }
    }

    @ViewBuilder
    func cardView(for card: DashboardCard) -> some View {
        switch card {
        case .statsSpools:
            HStack(spacing: 12) {
                StatCard(
                    title: "Total Spools",
                    value: "\(store.totalFilaments)",
                    icon: "shippingbox.fill",
                    color: .blue
                )
                StatCard(
                    title: "Total Spend",
                    value: String(format: "€%.2f", store.totalSpend),
                    icon: "eurosign.circle.fill",
                    color: .green
                )
            }
        case .statsWeight:
            HStack(spacing: 12) {
                StatCard(
                    title: "Weight Left",
                    value: "\(Int(store.totalWeightRemaining))g",
                    icon: "scalemass.fill",
                    color: .purple
                )
                StatCard(
                    title: "Low Stock",
                    value: "\(store.lowStockFilaments.count)",
                    icon: "exclamationmark.triangle.fill",
                    color: store.lowStockFilaments.isEmpty ? .gray : .orange
                )
            }
        case .syncStatus:
            SyncStatusBar()
        case .camera:
            if nasService.isConfigured {
                CameraFeedCard()
            }
        case .lowStock:
            if !store.lowStockFilaments.isEmpty {
                LowStockSection()
            }
        case .typeBreakdown:
            TypeBreakdownSection()
        case .recentPrints:
            RecentPrintsSection()
        }
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title2)
                Spacer()
            }
            Text(value)
                .font(.system(.title2, design: .rounded))
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .glassCard()
    }
}

// MARK: - Sync Status Bar

struct SyncStatusBar: View {
    @EnvironmentObject var nasService: NASService
    @EnvironmentObject var store: InventoryStore

    var body: some View {
        HStack {
            Circle()
                .fill(nasService.isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(nasService.isConnected ? "NAS Connected" : "NAS Offline")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            if store.isLoading {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassCard(cornerRadius: 10)
    }
}

// MARK: - Low Stock Section

struct LowStockSection: View {
    @EnvironmentObject var store: InventoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Low Stock Alerts", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundColor(.orange)

            ForEach(store.lowStockFilaments) { filament in
                NavigationLink(destination: FilamentDetailView(filament: filament)) {
                    LowStockRow(filament: filament)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding()
        .glassTintCard(fallback: Color.orange.opacity(0.1))
    }
}

struct LowStockRow: View {
    let filament: Filament

    var body: some View {
        HStack {
            Circle()
                .fill(filament.color.color)
                .frame(width: 24, height: 24)
                .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                .shadow(radius: 2)

            VStack(alignment: .leading) {
                Text("\(filament.brand) \(filament.type.rawValue)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(filament.color.name)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text("\(Int(filament.remainingWeightG))g")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.orange)
        }
    }
}

// MARK: - Type Breakdown Section

struct TypeBreakdownSection: View {
    @EnvironmentObject var store: InventoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("By Type")
                .font(.headline)

            ForEach(Array(store.filamentsByType.keys), id: \.self) { type in
                let count = store.filamentsByType[type]?.count ?? 0
                HStack {
                    Image(systemName: type.icon)
                        .frame(width: 20)
                        .foregroundColor(.orange)
                    Text(type.rawValue)
                        .font(.subheadline)
                    Spacer()
                    Text("\(count) spool\(count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .glassInnerCard(cornerRadius: 8)
                }
            }
        }
        .padding()
        .glassCard()
    }
}

// MARK: - Recent Prints Section

struct RecentPrintsSection: View {
    @EnvironmentObject var store: InventoryStore

    var recentJobs: [PrintJob] {
        Array(store.printJobs.sorted(by: { $0.date > $1.date }).prefix(5))
    }

    var body: some View {
        if !recentJobs.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recent Prints")
                    .font(.headline)

                ForEach(recentJobs) { job in
                    HStack {
                        Image(systemName: "printer.fill")
                            .foregroundColor(.blue)
                        VStack(alignment: .leading) {
                            Text(job.printName)
                                .font(.subheadline)
                            Text(job.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("\(Int(job.weightUsedG))g")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
            }
            .padding()
            .glassCard()
        }
    }
}
