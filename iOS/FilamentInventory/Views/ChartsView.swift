import SwiftUI

// MARK: - Charts Dashboard View
struct ChartsView: View {
    @EnvironmentObject var store: InventoryStore

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                SpendChartCard()
                TypeDonutCard()
                ColourBarCard()
                WeightSummaryCard()
            }
            .padding()
        }
    }
}

// MARK: - Spend Chart Card
struct SpendChartCard: View {
    @EnvironmentObject var store: InventoryStore

    // Group purchases by month
    var monthlySpend: [(label: String, amount: Double)] {
        let cal = Calendar.current
        var grouped: [String: Double] = [:]
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM yy"
        for f in store.filaments {
            let key = fmt.string(from: f.purchaseDate)
            grouped[key, default: 0] += f.pricePaid
        }
        // Sort by date
        let sorted = grouped.sorted { a, b in
            fmt.date(from: a.key) ?? .distantPast < fmt.date(from: b.key) ?? .distantPast
        }
        return sorted.map { ($0.key, $0.value) }
    }

    var maxAmount: Double { monthlySpend.map(\.amount).max() ?? 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Spend Over Time", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)

            if monthlySpend.isEmpty {
                Text("No purchase data yet")
                    .font(.subheadline).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                // Bar chart
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(monthlySpend, id: \.label) { item in
                        VStack(spacing: 4) {
                            Text(String(format: "€%.0f", item.amount))
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .lineLimit(1)

                            RoundedRectangle(cornerRadius: 6)
                                .fill(LinearGradient(
                                    colors: [.orange, .orange.opacity(0.6)],
                                    startPoint: .top, endPoint: .bottom))
                                .frame(
                                    height: max(8, CGFloat(item.amount / maxAmount) * 100)
                                )

                            Text(item.label)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 130)

                HStack {
                    Text("Total spend:")
                        .font(.subheadline).foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "€%.2f", store.totalSpend))
                        .font(.subheadline).fontWeight(.bold)
                }
            }
        }
        .padding()
        .glassCard()
    }
}

// MARK: - Type Donut Card
struct TypeDonutCard: View {
    @EnvironmentObject var store: InventoryStore

    var typeData: [(type: FilamentType, count: Int, fraction: Double)] {
        let total = Double(store.filaments.count)
        guard total > 0 else { return [] }
        return store.filamentsByType
            .map { (type: $0.key, count: $0.value.count, fraction: Double($0.value.count) / total) }
            .sorted { $0.count > $1.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Filaments by Type", systemImage: "chart.pie.fill")
                .font(.headline)

            if typeData.isEmpty {
                Text("No filaments yet")
                    .font(.subheadline).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center).padding()
            } else {
                HStack(alignment: .center, spacing: 20) {
                    // Donut chart
                    DonutChart(segments: typeData.map {
                        DonutSegment(
                            label: $0.type.rawValue,
                            fraction: $0.fraction,
                            color: typeColor($0.type)
                        )
                    }, centerLabel: "\(store.totalFilaments)", centerSublabel: "spools")
                    .frame(width: 120, height: 120)

                    // Legend
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(typeData, id: \.type) { item in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(typeColor(item.type))
                                    .frame(width: 10, height: 10)
                                Text(item.type.rawValue)
                                    .font(.caption)
                                Spacer()
                                Text("\(item.count)")
                                    .font(.caption).fontWeight(.bold)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .glassCard()
    }

    func typeColor(_ type: FilamentType) -> Color {
        let palette: [Color] = [.orange, .blue, .green, .purple, .red, .teal, .pink, .yellow, .indigo, .mint]
        let idx = FilamentType.allCases.firstIndex(of: type) ?? 0
        return palette[idx % palette.count]
    }
}

// MARK: - Donut Chart
struct DonutSegment {
    let label: String
    let fraction: Double
    let color: Color
}

struct DonutChart: View {
    let segments: [DonutSegment]
    let centerLabel: String
    let centerSublabel: String

    var body: some View {
        ZStack {
            ForEach(Array(segments.enumerated()), id: \.offset) { idx, seg in
                let startAngle = startAngle(for: idx)
                let endAngle = startAngle + Angle(degrees: seg.fraction * 360)
                DonutSlice(startAngle: startAngle, endAngle: endAngle,
                           innerRadius: 0.55, color: seg.color)
            }
            VStack(spacing: 1) {
                Text(centerLabel)
                    .font(.system(.title3, design: .rounded)).fontWeight(.black)
                Text(centerSublabel)
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
    }

    func startAngle(for index: Int) -> Angle {
        var total = 0.0
        for i in 0..<index { total += segments[i].fraction }
        return Angle(degrees: total * 360 - 90)
    }
}

struct DonutSlice: View {
    let startAngle: Angle
    let endAngle: Angle
    let innerRadius: CGFloat
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let r = min(geo.size.width, geo.size.height) / 2
            let cx = geo.size.width / 2
            let cy = geo.size.height / 2
            Path { path in
                path.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                            startAngle: startAngle, endAngle: endAngle, clockwise: false)
                path.addArc(center: CGPoint(x: cx, y: cy), radius: r * innerRadius,
                            startAngle: endAngle, endAngle: startAngle, clockwise: true)
                path.closeSubpath()
            }
            .fill(color)
        }
    }
}

// MARK: - Colour Bar Card
struct ColourBarCard: View {
    @EnvironmentObject var store: InventoryStore

    var colourData: [(name: String, hex: String, count: Int)] {
        var grouped: [String: (hex: String, count: Int)] = [:]
        for f in store.filaments {
            let key = f.color.name
            grouped[key] = (hex: f.color.hexCode, count: (grouped[key]?.count ?? 0) + 1)
        }
        return grouped.map { (name: $0.key, hex: $0.value.hex, count: $0.value.count) }
            .sorted { $0.count > $1.count }
            .prefix(8)
            .map { $0 }
    }

    var maxCount: Int { colourData.map(\.count).max() ?? 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Filaments by Colour", systemImage: "paintpalette.fill")
                .font(.headline)

            if colourData.isEmpty {
                Text("No filaments yet")
                    .font(.subheadline).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center).padding()
            } else {
                VStack(spacing: 8) {
                    ForEach(colourData, id: \.name) { item in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Color(hex: item.hex) ?? .gray)
                                .frame(width: 14, height: 14)
                                .shadow(color: (Color(hex: item.hex) ?? .gray).opacity(0.5), radius: 3)

                            Text(item.name)
                                .font(.caption)
                                .frame(width: 70, alignment: .leading)

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color(.systemFill))
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color(hex: item.hex) ?? .orange)
                                        .frame(width: geo.size.width * CGFloat(item.count) / CGFloat(maxCount))
                                }
                            }
                            .frame(height: 14)

                            Text("\(item.count)")
                                .font(.caption).fontWeight(.bold)
                                .frame(width: 20, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .padding()
        .glassCard()
    }
}

// MARK: - Weight Summary Card
struct WeightSummaryCard: View {
    @EnvironmentObject var store: InventoryStore

    var totalWeight: Double { store.filaments.reduce(0) { $0 + $1.totalWeightG } }
    var usedWeight: Double { store.filaments.reduce(0) { $0 + $1.usedWeightG } }
    var remainingWeight: Double { store.totalWeightRemaining }
    var usedFraction: Double { totalWeight > 0 ? usedWeight / totalWeight : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Weight Overview", systemImage: "scalemass.fill")
                .font(.headline)

            HStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text("\(Int(remainingWeight))g")
                        .font(.system(.title2, design: .rounded)).fontWeight(.black)
                        .foregroundColor(.green)
                    Text("Remaining")
                        .font(.caption).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    Text("\(Int(usedWeight))g")
                        .font(.system(.title2, design: .rounded)).fontWeight(.black)
                        .foregroundColor(.orange)
                    Text("Used")
                        .font(.caption).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    Text("\(Int(totalWeight))g")
                        .font(.system(.title2, design: .rounded)).fontWeight(.black)
                    Text("Total")
                        .font(.caption).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }

            // Stacked bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange.opacity(0.3))
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.green)
                        .frame(width: totalWeight > 0
                               ? geo.size.width * CGFloat(remainingWeight / totalWeight)
                               : 0)
                }
            }
            .frame(height: 18)

            HStack {
                Circle().fill(Color.green).frame(width: 8, height: 8)
                Text("Remaining").font(.caption).foregroundColor(.secondary)
                Spacer()
                Circle().fill(Color.orange.opacity(0.6)).frame(width: 8, height: 8)
                Text("Used").font(.caption).foregroundColor(.secondary)
            }
        }
        .padding()
        .glassCard()
    }
}
