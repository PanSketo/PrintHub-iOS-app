import SwiftUI

// MARK: - Restock Sheet
// Shown when a scanned barcode or typed SKU matches an existing filament in inventory
struct RestockView: View {
    @EnvironmentObject var store: InventoryStore
    @Environment(\.dismiss) var dismiss

    let matchedFilament: Filament

    // Restock inputs
    @State private var numberOfSpools: Int = 1
    @State private var pricePerSpool: String = ""
    @State private var restockNotes: String = ""
    @FocusState private var focusedField: RestockField?
    @State private var showSuccess = false

    enum RestockField { case price, notes }

    var totalNewWeight: Double {
        matchedFilament.totalWeightG * Double(numberOfSpools)
    }

    var newRemainingWeight: Double {
        matchedFilament.remainingWeightG + totalNewWeight
    }

    var parsedPrice: Double {
        Double(pricePerSpool.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    var totalCost: Double { parsedPrice * Double(numberOfSpools) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {

                    // ── Matched filament card ──────────────────────────
                    matchedFilamentCard

                    // ── Restock inputs ─────────────────────────────────
                    restockInputsCard

                    // ── Weight preview ─────────────────────────────────
                    weightPreviewCard

                    // ── Cost preview ───────────────────────────────────
                    if parsedPrice > 0 {
                        costPreviewCard
                    }

                    // ── Notes ──────────────────────────────────────────
                    notesCard

                    // ── Save button ────────────────────────────────────
                    Button(action: saveRestock) {
                        HStack {
                            Image(systemName: "arrow.clockwise.circle.fill")
                            Text("Restock \(numberOfSpools) Spool\(numberOfSpools > 1 ? "s" : "")")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                    .disabled(parsedPrice == 0)

                    if parsedPrice == 0 {
                        Text("Enter a price to continue")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.horizontal)
                    }
                }
                .padding(.bottom, 40)
            }
            .navigationTitle("Restock Filament")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if focusedField != nil {
                        Button(action: { focusedField = nil }) {
                            Image(systemName: "keyboard.chevron.compact.down")
                        }
                    }
                }
            }
            .simultaneousGesture(TapGesture().onEnded { focusedField = nil })
            .alert("Restocked! ✅", isPresented: $showSuccess) {
                Button("Done") { dismiss() }
            } message: {
                Text("\(numberOfSpools) spool\(numberOfSpools > 1 ? "s" : "") of \(matchedFilament.brand) \(matchedFilament.type.rawValue) \(matchedFilament.color.name) added. New total: \(Int(newRemainingWeight))g")
            }
        }
    }

    // MARK: - Matched Filament Card
    var matchedFilamentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(.green)
                Text("Existing filament found")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
            }

            HStack(spacing: 14) {
                // Colour dot
                Circle()
                    .fill(matchedFilament.color.color)
                    .frame(width: 48, height: 48)
                    .shadow(color: matchedFilament.color.color.opacity(0.4), radius: 6)

                VStack(alignment: .leading, spacing: 4) {
                    Text(matchedFilament.brand)
                        .font(.headline).fontWeight(.bold)
                    Text("\(matchedFilament.type.rawValue) — \(matchedFilament.color.name)")
                        .font(.subheadline).foregroundColor(.secondary)
                    if !matchedFilament.sku.isEmpty {
                        Text("SKU: \(matchedFilament.sku)")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Image(systemName: matchedFilament.stockStatus.icon)
                        .foregroundColor(matchedFilament.stockStatus.color)
                        .font(.title3)
                    Text("\(Int(matchedFilament.remainingWeightG))g left")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .glassCard()
        .padding(.horizontal)
    }

    // MARK: - Restock Inputs Card
    var restockInputsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Restock Details")
                .font(.headline)

            // Number of spools stepper
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Number of Spools")
                        .font(.subheadline)
                    Text("Each spool = \(Int(matchedFilament.totalWeightG))g")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                HStack(spacing: 0) {
                    Button(action: { if numberOfSpools > 1 { numberOfSpools -= 1 } }) {
                        Image(systemName: "minus.circle.fill")
                            .font(.title2)
                            .foregroundColor(numberOfSpools > 1 ? .orange : .gray)
                    }
                    .disabled(numberOfSpools <= 1)

                    Text("\(numberOfSpools)")
                        .font(.system(.title2, design: .rounded))
                        .fontWeight(.black)
                        .frame(width: 44)
                        .multilineTextAlignment(.center)

                    Button(action: { numberOfSpools += 1 }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.orange)
                    }
                }
            }

            Divider()

            // Price per spool
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Price per Spool (€)")
                        .font(.subheadline)
                    Text("Last paid: €\(euDecimal(matchedFilament.pricePaid, decimals: 2))")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                TextField("0.00", text: $pricePerSpool)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: .price)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .frame(width: 90)
            }
        }
        .padding()
        .glassCard()
        .padding(.horizontal)
    }

    // MARK: - Weight Preview Card
    var weightPreviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Weight After Restock")
                .font(.headline)

            HStack(spacing: 0) {
                weightTile(
                    label: "Currently",
                    value: "\(Int(matchedFilament.remainingWeightG))g",
                    color: matchedFilament.stockStatus.color
                )
                Image(systemName: "plus")
                    .foregroundColor(.secondary)
                    .frame(width: 30)
                weightTile(
                    label: "Adding",
                    value: "\(Int(totalNewWeight))g",
                    color: .orange
                )
                Image(systemName: "equal")
                    .foregroundColor(.secondary)
                    .frame(width: 30)
                weightTile(
                    label: "New Total",
                    value: "\(Int(newRemainingWeight))g",
                    color: .green
                )
            }

            // Progress bar showing new fill level
            let maxWeight = matchedFilament.totalWeightG * Double(numberOfSpools + 1)
            let fraction = min(newRemainingWeight / maxWeight, 1.0)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6).fill(Color(.systemFill))
                    // Old amount
                    RoundedRectangle(cornerRadius: 6)
                        .fill(matchedFilament.stockStatus.color.opacity(0.5))
                        .frame(width: geo.size.width * CGFloat(min(matchedFilament.remainingWeightG / maxWeight, 1.0)))
                    // New addition
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.orange)
                        .frame(width: geo.size.width * CGFloat(fraction))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.orange.opacity(0.4), lineWidth: 1)
                        )
                }
            }
            .frame(height: 16)

            HStack {
                Circle().fill(matchedFilament.stockStatus.color.opacity(0.5)).frame(width: 8, height: 8)
                Text("Current stock").font(.caption).foregroundColor(.secondary)
                Spacer()
                Circle().fill(Color.orange).frame(width: 8, height: 8)
                Text("After restock").font(.caption).foregroundColor(.secondary)
            }
        }
        .padding()
        .glassCard()
        .padding(.horizontal)
    }

    // MARK: - Cost Preview Card
    var costPreviewCard: some View {
        HStack(spacing: 0) {
            costTile(label: "Per Spool", value: euEuro(parsedPrice), color: .orange)
            Divider().frame(height: 40)
            costTile(label: "Total Cost", value: euEuro(totalCost), color: .blue)
            Divider().frame(height: 40)
            let diff = parsedPrice - matchedFilament.pricePaid
            costTile(
                label: "vs Last Price",
                value: (diff >= 0 ? "+" : "") + euDecimal(abs(diff), decimals: 2),
                color: parsedPrice <= matchedFilament.pricePaid ? .green : .red
            )
        }
        .padding()
        .glassCard()
        .padding(.horizontal)
    }

    // MARK: - Notes Card
    var notesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes (optional)")
                .font(.headline)
            TextField("e.g. Bought on sale, new supplier...", text: $restockNotes, axis: .vertical)
                .lineLimit(3)
                .focused($focusedField, equals: .notes)
        }
        .padding()
        .glassCard()
        .padding(.horizontal)
    }

    // MARK: - Helper tiles
    func weightTile(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.black)
                .foregroundColor(color)
            Text(label)
                .font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    func costTile(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.subheadline).fontWeight(.bold).foregroundColor(color)
            Text(label)
                .font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Save Restock
    func saveRestock() {
        focusedField = nil
        var updated = matchedFilament

        // Add weight for each new spool
        updated.remainingWeightG += totalNewWeight
        // Cap at a sensible max (e.g. 10 spools worth)
        updated.totalWeightG = max(updated.totalWeightG, updated.remainingWeightG)
        updated.stockStatus = StockStatus.from(remaining: updated.remainingWeightG, total: updated.totalWeightG)
        updated.pricePaid = parsedPrice
        updated.lastUpdated = Date()

        // Add price history entry
        let priceEntry = PriceEntry(
            price: parsedPrice,
            date: Date(),
            notes: restockNotes.isEmpty
                ? "Restocked \(numberOfSpools) spool\(numberOfSpools > 1 ? "s" : "") (+\(Int(totalNewWeight))g)"
                : restockNotes
        )
        updated.priceHistory.append(priceEntry)

        store.updateFilament(updated)
        showSuccess = true
    }
}
