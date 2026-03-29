import SwiftUI

struct PrintLogView: View {
    @EnvironmentObject var store: InventoryStore
    @State private var searchText = ""

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

    var body: some View {
        NavigationStack {
            List {
                // Summary section
                Section {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(store.printJobs.count)")
                                .font(.system(.title, design: .rounded))
                                .fontWeight(.black)
                            Text("Total Prints")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Divider().frame(height: 40)
                        Spacer()
                        VStack(alignment: .center) {
                            Text("\(Int(totalWeightUsed))g")
                                .font(.system(.title, design: .rounded))
                                .fontWeight(.black)
                            Text("Total Used")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if totalPrintCost > 0 {
                            Spacer()
                            Divider().frame(height: 40)
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(String(format: "€%.2f", totalPrintCost))
                                    .font(.system(.title, design: .rounded))
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
                Text("\(Int(job.weightUsedG))g")
                    .font(.subheadline)
                    .fontWeight(.bold)
                if let cost = job.costEUR {
                    Text(String(format: "€%.3f", cost))
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
