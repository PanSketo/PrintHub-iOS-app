import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var store: InventoryStore
    @EnvironmentObject var nasService: NASService

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header stats
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

                    // Sync status
                    SyncStatusBar()

                    // Low stock alerts
                    if !store.lowStockFilaments.isEmpty {
                        LowStockSection()
                    }

                    // Filament by type breakdown
                    TypeBreakdownSection()

                    // Recent activity
                    RecentPrintsSection()
                }
                .padding()
            }
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { store.syncFromNAS() }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .refreshable { store.syncFromNAS() }
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
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
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
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
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
        .background(Color.orange.opacity(0.1))
        .cornerRadius(16)
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
                        .background(Color(.tertiarySystemBackground))
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
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
            .background(Color(.secondarySystemBackground))
            .cornerRadius(16)
        }
    }
}
