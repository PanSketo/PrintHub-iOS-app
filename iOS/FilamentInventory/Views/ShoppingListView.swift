import SwiftUI

struct ShoppingListView: View {
    @EnvironmentObject var store: InventoryStore
    @State private var showShareSheet = false
    @State private var shareText = ""
    @State private var includeEmpty = true
    @State private var includeLow = true

    var shoppingItems: [Filament] {
        store.filaments.filter { f in
            (includeEmpty && f.isEmpty) || (includeLow && f.isLowStock && !f.isEmpty)
        }
        .sorted { a, b in
            // Empty first, then low stock; within each group sort by brand
            if a.isEmpty != b.isEmpty { return a.isEmpty }
            return a.brand < b.brand
        }
    }

    var totalEstimatedCost: Double {
        shoppingItems.reduce(0) { $0 + $1.pricePaid }
    }

    var body: some View {
        Group {
            if shoppingItems.isEmpty {
                emptyState
            } else {
                List {
                    // Summary card
                    Section {
                        HStack(spacing: 0) {
                            summaryTile(value: "\(shoppingItems.count)", label: "Items needed", color: .orange)
                            Divider().frame(height: 44)
                            summaryTile(value: "\(shoppingItems.filter(\.isEmpty).count)", label: "Empty", color: .red)
                            Divider().frame(height: 44)
                            summaryTile(value: "\(shoppingItems.filter { $0.isLowStock && !$0.isEmpty }.count)", label: "Low stock", color: .orange)
                            Divider().frame(height: 44)
                            summaryTile(value: String(format: "€%.0f", totalEstimatedCost), label: "Est. cost", color: .green)
                        }
                        .padding(.vertical, 6)
                    }

                    // Filters
                    Section {
                        Toggle("Include empty spools", isOn: $includeEmpty)
                            .tint(.red)
                        Toggle("Include low stock (<200g)", isOn: $includeLow)
                            .tint(.orange)
                    } header: { Text("Filters") }

                    // Shopping items
                    Section {
                        ForEach(shoppingItems) { filament in
                            ShoppingItemRow(filament: filament)
                        }
                    } header: {
                        Text("Shopping List (\(shoppingItems.count))")
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(activityItems: [shareText])
        }
    }

    var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "cart.badge.checkmark")
                .font(.system(size: 56))
                .foregroundColor(.green)
            Text("All stocked up!")
                .font(.title2).fontWeight(.semibold)
            Text("No filaments are empty or running low.")
                .font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    func summaryTile(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.title3, design: .rounded))
                .fontWeight(.black)
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    func shareList() {
        var lines = ["🧵 Filament Shopping List", "Generated: \(Date().formatted(date: .abbreviated, time: .omitted))", ""]

        let emptyItems = shoppingItems.filter(\.isEmpty)
        let lowItems = shoppingItems.filter { $0.isLowStock && !$0.isEmpty }

        if !emptyItems.isEmpty {
            lines.append("❌ EMPTY — Need to replace:")
            for f in emptyItems {
                lines.append("  • \(f.brand) \(f.type.rawValue) \(f.color.name) (\(Int(f.totalWeightG))g) — Last paid €\(String(format: "%.2f", f.pricePaid))")
                if let url = f.reorderURL { lines.append("    🔗 \(url)") }
            }
            lines.append("")
        }

        if !lowItems.isEmpty {
            lines.append("⚠️ LOW STOCK — Consider reordering:")
            for f in lowItems {
                lines.append("  • \(f.brand) \(f.type.rawValue) \(f.color.name) — \(Int(f.remainingWeightG))g remaining")
                if let url = f.reorderURL { lines.append("    🔗 \(url)") }
            }
            lines.append("")
        }

        lines.append("Total estimated reorder cost: €\(String(format: "%.2f", totalEstimatedCost))")

        shareText = lines.joined(separator: "\n")
        showShareSheet = true
    }
}

// MARK: - Shopping Item Row
struct ShoppingItemRow: View {
    let filament: Filament

    var body: some View {
        HStack(spacing: 12) {
            // Colour dot with status
            ZStack {
                Circle()
                    .fill(filament.color.color)
                    .frame(width: 40, height: 40)
                    .shadow(color: filament.color.color.opacity(0.4), radius: 4)
                Image(systemName: filament.stockStatus.icon)
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(filament.brand)
                        .font(.subheadline).fontWeight(.semibold)
                    Text(filament.type.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .foregroundColor(.orange)
                        .cornerRadius(6)
                }
                Text(filament.color.name)
                    .font(.caption).foregroundColor(.secondary)

                if filament.isEmpty {
                    Label("Empty — needs replacement", systemImage: "xmark.circle.fill")
                        .font(.caption2).foregroundColor(.red)
                } else {
                    Label("\(Int(filament.remainingWeightG))g remaining", systemImage: "exclamationmark.circle.fill")
                        .font(.caption2).foregroundColor(.orange)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(String(format: "€%.2f", filament.pricePaid))
                    .font(.subheadline).fontWeight(.bold)
                Text("last price")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
