import SwiftUI

struct PrintLogView: View {
    @EnvironmentObject var store: InventoryStore
    @State private var searchText = ""
    @State private var logSheet: NASService.UntrackedPrint?

    var filteredJobs: [PrintJob] {
        let jobs = store.printJobs.sorted(by: { $0.date > $1.date })
        if searchText.isEmpty { return jobs }
        return jobs.filter { $0.printName.localizedCaseInsensitiveContains(searchText) }
    }

    var totalWeightUsed: Double {
        store.printJobs.reduce(0) { $0 + $1.weightUsedG }
    }

    var totalPrintCost: Double {
        store.printJobs.compactMap(\.costEUR).reduce(0, +)
    }

    // Returns grams-per-metre for 1.75 mm filament of the given type.
    // Formula: density (g/cm³) × cross-section area (π × 0.0875² cm²) × 100 cm/m
    private func gramsPerMeter(for type: FilamentType) -> Double {
        let area = Double.pi * pow(0.0875, 2)   // cm² for 1.75 mm diameter
        let density: Double
        switch type {
        case .pla, .plaPlus, .silk, .wood: density = 1.24
        case .petg:                        density = 1.27
        case .abs:                         density = 1.05
        case .asa:                         density = 1.07
        case .tpu, .tpe, .flex:           density = 1.21
        case .nylon:                       density = 1.13
        case .hips:                        density = 1.07
        case .pva:                         density = 1.19
        case .carbon:                      density = 1.30
        default:                           density = 1.24
        }
        return density * area * 100
    }

    var totalLengthMeters: Double {
        store.printJobs.reduce(0.0) { total, job in
            let type = store.filaments.first(where: { $0.id == job.filamentId })?.type ?? .pla
            return total + job.weightUsedG / gramsPerMeter(for: type)
        }
    }

    var totalLengthText: String {
        let meters = totalLengthMeters
        if meters >= 1000 {
            return euDecimal(meters / 1000, decimals: 2) + "km"
        } else {
            return "\(Int(meters.rounded()))m"
        }
    }

    var formattedWeight: String { euGrams(totalWeightUsed) }

    var formattedCost: String { euEuro(totalPrintCost) }

    var body: some View {
        NavigationStack {
            List {
                // Summary section
                Section {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(store.printJobs.count)")
                                .font(.system(.title2, design: .rounded))
                                .fontWeight(.black)
                            Text("Total Prints")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Divider().frame(height: 40)
                        Spacer()
                        VStack(alignment: .center) {
                            Text(formattedWeight)
                                .font(.system(.title2, design: .rounded))
                                .fontWeight(.black)
                            Text("Total Used")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Divider().frame(height: 40)
                        Spacer()
                        VStack(alignment: .center) {
                            Text(totalLengthText)
                                .font(.system(.title2, design: .rounded))
                                .fontWeight(.black)
                                .foregroundColor(.orange)
                            Text("Length")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if totalPrintCost > 0 {
                            Spacer()
                            Divider().frame(height: 40)
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(formattedCost)
                                    .font(.system(.title2, design: .rounded))
                                    .fontWeight(.black)
                                    .foregroundColor(.blue)
                                Text("Print Cost")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }

                // Untracked prints — need manual weight entry
                if !store.untrackedPrints.isEmpty {
                    Section {
                        ForEach(store.untrackedPrints) { item in
                            HStack {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(.orange)
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.printName)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Text("Weight not logged — tap to enter")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button("Log") { logSheet = item }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.orange)
                                    .controlSize(.small)
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        Text("Needs Manual Entry")
                            .foregroundColor(.orange)
                    }
                }

                // Grouped by date
                ForEach(groupedByDate.keys.sorted(by: >), id: \.self) { date in
                    Section(header: Text(date.formatted(date: .abbreviated, time: .omitted))) {
                        ForEach(groupedByDate[date] ?? []) { job in
                            PrintJobRow(job: job, filament: filamentFor(job))
                        }
                    }
                }
            }
            .navigationTitle("Print Log")
            .searchable(text: $searchText, prompt: "Search prints...")
            .task { store.refreshUntrackedPrints() }
            .sheet(item: $logSheet) { item in
                ManualPrintLogSheet(untracked: item)
                    .environmentObject(store)
            }
            .overlay {
                if store.printJobs.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "printer")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)
                        Text("No prints logged yet")
                            .foregroundColor(.secondary)
                        Text("Log a print from the filament detail view")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    var groupedByDate: [Date: [PrintJob]] {
        let calendar = Calendar.current
        return Dictionary(grouping: filteredJobs) { job in
            calendar.startOfDay(for: job.date)
        }
    }

    func filamentFor(_ job: PrintJob) -> Filament? {
        store.filaments.first { $0.id == job.filamentId }
    }
}

struct PrintJobRow: View {
    let job: PrintJob
    let filament: Filament?

    var body: some View {
        HStack(spacing: 12) {
            // Color dot
            if let f = filament {
                Circle()
                    .fill(f.color.color)
                    .frame(width: 32, height: 32)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
            } else {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.title2)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(job.printName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                if let f = filament {
                    Text("\(f.brand) \(f.type.rawValue) — \(f.color.name)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let duration = job.duration {
                    Text(formatDuration(duration))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(euGrams(job.weightUsedG))
                    .font(.subheadline)
                    .fontWeight(.bold)
                if let cost = job.costEUR {
                    Text(euEuro(cost, decimals: 3))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Image(systemName: job.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(job.success ? .green : .red)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    func formatDuration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
