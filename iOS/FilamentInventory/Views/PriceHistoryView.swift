import SwiftUI

struct PriceHistoryView: View {
    @EnvironmentObject var store: InventoryStore
    var filament: Filament
    @Binding var currentFilament: Filament

    @State private var showAddPrice = false
    @State private var newPrice = ""
    @State private var newNotes = ""

    var allEntries: [PriceEntry] {
        currentFilament.priceHistory.sorted { $0.date > $1.date }
    }

    var avgPrice: Double {
        guard !allEntries.isEmpty else { return currentFilament.pricePaid }
        return allEntries.reduce(0) { $0 + $1.price } / Double(allEntries.count)
    }

    var minPrice: Double { allEntries.map(\.price).min() ?? currentFilament.pricePaid }
    var maxPrice: Double { allEntries.map(\.price).max() ?? currentFilament.pricePaid }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Price History", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline)
                Spacer()
                Button(action: { showAddPrice = true }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.orange)
                        .font(.title3)
                }
            }

            // Summary stats
            HStack(spacing: 0) {
                priceTile(label: "Current", value: currentFilament.pricePaid, color: .orange)
                Divider().frame(height: 40)
                priceTile(label: "Average", value: avgPrice, color: .blue)
                Divider().frame(height: 40)
                priceTile(label: "Lowest", value: minPrice, color: .green)
                Divider().frame(height: 40)
                priceTile(label: "Highest", value: maxPrice, color: .red)
            }
            .padding(.vertical, 4)
            .glassInnerCard()

            // Trend mini chart
            if allEntries.count > 1 {
                PriceTrendChart(entries: allEntries.reversed())
                    .frame(height: 60)
                    .padding(.vertical, 4)
            }

            // History list
            if allEntries.isEmpty {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                    Text("Tap + to record a price change")
                        .font(.caption).foregroundColor(.secondary)
                }
            } else {
                ForEach(allEntries) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(format: "€%.2f", entry.price))
                                .font(.subheadline).fontWeight(.semibold)
                            Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption).foregroundColor(.secondary)
                            if !entry.notes.isEmpty {
                                Text(entry.notes)
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        // Price change indicator vs previous
                        if let prev = previousPrice(for: entry) {
                            let diff = entry.price - prev
                            Label(String(format: "%+.2f", diff), systemImage: diff >= 0 ? "arrow.up" : "arrow.down")
                                .font(.caption).fontWeight(.semibold)
                                .foregroundColor(diff >= 0 ? .red : .green)
                        }
                    }
                    .padding(.vertical, 2)
                    Divider()
                }
            }
        }
        .padding()
        .glassCard()
        .sheet(isPresented: $showAddPrice) {
            addPriceSheet
        }
    }

    var addPriceSheet: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("New Price (€)")
                        Spacer()
                        TextField("0.00", text: $newPrice)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                    }
                    TextField("Notes (e.g. sale, new supplier)", text: $newNotes)
                } header: { Text("Record Price") }

                Section {
                    HStack {
                        Text("Current price")
                        Spacer()
                        Text(String(format: "€%.2f", currentFilament.pricePaid))
                            .foregroundColor(.secondary)
                    }
                } header: { Text("Reference") }
            }
            .navigationTitle("Add Price Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { showAddPrice = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        guard let price = Double(newPrice.replacingOccurrences(of: ",", with: ".")) else { return }
                        let entry = PriceEntry(price: price, date: Date(), notes: newNotes)
                        currentFilament.priceHistory.append(entry)
                        currentFilament.pricePaid = price   // also update current price
                        currentFilament.lastUpdated = Date()
                        store.updateFilament(currentFilament)
                        newPrice = ""
                        newNotes = ""
                        showAddPrice = false
                    }
                    .fontWeight(.semibold)
                    .disabled(newPrice.isEmpty)
                }
            }
        }
    }

    func priceTile(label: String, value: Double, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(String(format: "€%.2f", value))
                .font(.caption).fontWeight(.bold).foregroundColor(color)
            Text(label)
                .font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    func previousPrice(for entry: PriceEntry) -> Double? {
        let sorted = allEntries  // already sorted newest first
        guard let idx = sorted.firstIndex(where: { $0.id == entry.id }),
              idx + 1 < sorted.count else { return nil }
        return sorted[idx + 1].price
    }
}

// MARK: - Mini Trend Line Chart
struct PriceTrendChart: View {
    let entries: [PriceEntry]  // oldest first

    var prices: [Double] { entries.map(\.price) }
    var minP: Double { prices.min() ?? 0 }
    var maxP: Double { prices.max() ?? 1 }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let range = max(maxP - minP, 0.01)
            let pts = prices.enumerated().map { idx, price -> CGPoint in
                let x = prices.count > 1 ? CGFloat(idx) / CGFloat(prices.count - 1) * w : w / 2
                let y = h - CGFloat((price - minP) / range) * h * 0.8 - h * 0.1
                return CGPoint(x: x, y: y)
            }

            ZStack {
                // Fill area
                if pts.count > 1 {
                    Path { path in
                        path.move(to: CGPoint(x: pts[0].x, y: h))
                        path.addLine(to: pts[0])
                        for p in pts.dropFirst() { path.addLine(to: p) }
                        path.addLine(to: CGPoint(x: pts.last?.x ?? w, y: h))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [.orange.opacity(0.3), .clear],
                                        startPoint: .top, endPoint: .bottom))
                }

                // Line
                if pts.count > 1 {
                    Path { path in
                        path.move(to: pts[0])
                        for p in pts.dropFirst() { path.addLine(to: p) }
                    }
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }

                // Dots
                ForEach(Array(pts.enumerated()), id: \.offset) { _, pt in
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                        .position(pt)
                }
            }
        }
    }
}
