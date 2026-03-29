import SwiftUI

// MARK: - Log Print View
struct LogPrintView: View {
    let filament: Filament
    var onSave: (PrintJob) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var printName = ""
    @State private var weightUsed: Double = 50
    @State private var hours: Double = 0
    @State private var minutes: Double = 0
    @State private var notes = ""
    @State private var success = true

    var body: some View {
        NavigationView {
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
                            Text("\(Int(weightUsed))g")
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
                                Text(String(format: "€%.3f", (filament.pricePaid / filament.totalWeightG) * weightUsed))
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
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Hours")
                            Spacer()
                            Text("\(Int(hours))h")
                        }
                        Slider(value: $hours, in: 0...72, step: 1)
                        HStack {
                            Text("Minutes")
                            Spacer()
                            Text("\(Int(minutes))m")
                        }
                        Slider(value: $minutes, in: 0...59, step: 5)
                    }
                } header: {
                    Text("Print Duration (Optional)")
                }

                Section {
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
                        let duration = (hours * 3600) + (minutes * 60)
                        let job = PrintJob(
                            filamentId: filament.id,
                            printName: printName.isEmpty ? "Untitled Print" : printName,
                            weightUsedG: weightUsed,
                            duration: duration > 0 ? duration : nil,
                            date: Date(),
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
        NavigationView {
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
                            Text("\(Int(totalWeight))g").fontWeight(.semibold)
                        }
                        Slider(value: $totalWeight, in: 100...5000, step: 50).tint(.orange)
                    }
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Remaining")
                            Spacer()
                            Text("\(Int(remainingWeight))g").fontWeight(.semibold)
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
                pricePaid = String(format: "%.2f", filament.pricePaid)
                notes = filament.notes
                imageURL = filament.imageURL ?? ""
            }
        }
    }
}
