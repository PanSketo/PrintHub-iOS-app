import SwiftUI

// MARK: - Log Print View
struct LogPrintView: View {
    let filament: Filament
    var onSave: (PrintJob) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var printName = ""
    @State private var weightUsed: Double = 50
    @State private var durationText: String = ""
    @State private var notes = ""
    @State private var success = true
    @State private var printDate = Date()

    private struct ParsedDuration {
        let seconds: TimeInterval
        let label: String
    }

    private var parsedDuration: ParsedDuration? {
        let text = durationText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        let parts = text.split(separator: ":").map { Int($0) }
        if parts.count == 2, let h = parts[0], let m = parts[1], h >= 0, m >= 0, m < 60 {
            let label = h > 0 ? "\(h)h \(m)m" : "\(m)m"
            return ParsedDuration(seconds: TimeInterval(h * 3600 + m * 60), label: label)
        }
        if parts.count == 1, let m = parts[0], m >= 0 {
            let h = m / 60; let mins = m % 60
            let label = h > 0 ? "\(h)h \(mins)m" : "\(m)m"
            return ParsedDuration(seconds: TimeInterval(m * 60), label: label)
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Circle()
                            .fill(filament.color.color)
                            .frame(width: 20, height: 20)
                        Text("\(filament.brand) \(filament.type.rawValue) — \(filament.color.name)")
                            .font(.subheadline)
                        Spacer()
                        Text("\(Int(filament.remainingWeightG))g left")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Filament")
                }

                Section {
                    TextField("Print name / description", text: $printName)
                } header: {
                    Text("Print Name")
                }

                Section {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Weight Used")
                            Spacer()
                            Text(euGrams(weightUsed))
                                .fontWeight(.bold)
                                .foregroundColor(.orange)
                        }
                        Slider(value: $weightUsed, in: 1...filament.remainingWeightG, step: 1)
                            .tint(.orange)
                        HStack {
                            Text("Remaining after:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(filament.remainingWeightG - weightUsed))g")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(filament.remainingWeightG - weightUsed < 200 ? .orange : .secondary)
                        }
                        if filament.totalWeightG > 0 && filament.pricePaid > 0 {
                            HStack {
                                Text("Estimated cost:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(euEuro((filament.pricePaid / filament.totalWeightG) * weightUsed, decimals: 3))
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                } header: {
                    Text("Filament Used")
                }

                Section {
                    HStack {
                        Image(systemName: "clock").foregroundColor(.secondary)
                        TextField("e.g. 2:30", text: $durationText)
                            .keyboardType(.numbersAndPunctuation)
                        if let parsed = parsedDuration {
                            Text(parsed.label)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Print Duration (Optional)")
                } footer: {
                    Text("Format: H:MM — e.g. 1:30 for 1 hour 30 min")
                        .font(.caption2)
                }

                Section {
                    DatePicker("Date", selection: $printDate, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    Toggle("Print Successful", isOn: $success)
                        .tint(.green)
                    TextField("Notes...", text: $notes, axis: .vertical)
                        .lineLimit(3)
                } header: {
                    Text("Result")
                }
            }
            .navigationTitle("Log Print")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        let duration = parsedDuration?.seconds
                        let job = PrintJob(
                            filamentId: filament.id,
                            printName: printName.isEmpty ? "Untitled Print" : printName,
                            weightUsedG: weightUsed,
                            duration: duration,
                            date: printDate,
                            notes: notes,
                            success: success
                        )
                        onSave(job)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Edit Filament View
struct EditFilamentView: View {
    @Binding var filament: Filament
    var onSave: (Filament) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var brand: String = ""
    @State private var sku: String = ""
    @State private var colorName: String = ""
    @State private var colorHex: String = ""
    @State private var selectedType: FilamentType = .pla
    @State private var totalWeight: Double = 1000
    @State private var remainingWeight: Double = 1000
    @State private var pricePaid: String = ""
    @State private var notes: String = ""
    @State private var imageURL: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Brand")
                        Spacer()
                        TextField("Brand", text: $brand).multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("SKU")
                        Spacer()
                        TextField("SKU", text: $sku).multilineTextAlignment(.trailing)
                    }
                    Picker("Type", selection: $selectedType) {
                        ForEach(FilamentType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .simultaneousGesture(TapGesture().onEnded { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) })
                } header: { Text("Product") }

                Section {
                    HStack {
                        Text("Color Name")
                        Spacer()
                        TextField("Color", text: $colorName).multilineTextAlignment(.trailing)
                    }
                    ColorSwatchPicker(hexCode: $colorHex)
                } header: { Text("Color") }

                Section {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Total Weight")
                            Spacer()
                            Text(euGrams(totalWeight)).fontWeight(.semibold)
                        }
                        Slider(value: $totalWeight, in: 100...5000, step: 50).tint(.orange)
                    }
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Remaining")
                            Spacer()
                            Text(euGrams(remainingWeight)).fontWeight(.semibold)
                        }
                        Slider(value: $remainingWeight, in: 0...totalWeight, step: 10).tint(.blue)
                    }
                } header: { Text("Weight") }

                Section {
                    HStack {
                        Text("Price Paid (€)")
                        Spacer()
                        TextField("0.00", text: $pricePaid)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                    }
                } header: { Text("Purchase") }

                Section {
                    HStack {
                        Text("Image URL")
                        Spacer()
                        TextField("Optional", text: $imageURL)
                            .multilineTextAlignment(.trailing)
                            .font(.caption)
                    }
                    TextField("Notes...", text: $notes, axis: .vertical).lineLimit(3)
                } header: { Text("Additional") }
            }
            .navigationTitle("Edit Filament")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        filament.brand = brand
                        filament.sku = sku
                        filament.type = selectedType
                        filament.color = FilamentColor(name: colorName, hexCode: colorHex)
                        filament.totalWeightG = totalWeight
                        filament.remainingWeightG = remainingWeight
                        filament.pricePaid = Double(pricePaid.replacingOccurrences(of: ",", with: ".")) ?? filament.pricePaid
                        filament.notes = notes
                        filament.imageURL = imageURL.isEmpty ? nil : imageURL
                        filament.stockStatus = StockStatus.from(remaining: remainingWeight, total: totalWeight)
                        filament.lastUpdated = Date()
                        onSave(filament)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                brand = filament.brand
                sku = filament.sku
                colorName = filament.color.name
                colorHex = filament.color.hexCode
                selectedType = filament.type
                totalWeight = filament.totalWeightG
                remainingWeight = filament.remainingWeightG
                pricePaid = euDecimal(filament.pricePaid, decimals: 2)
                notes = filament.notes
                imageURL = filament.imageURL ?? ""
            }
        }
    }
}
