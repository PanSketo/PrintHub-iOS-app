import SwiftUI

// MARK: - Filament Slot Model
private struct FilamentSlot: Identifiable {
    let id: Int
    var filamentID: String? = nil   // nil means "None"
    var gramsText: String = ""

    var grams: Double {
        Double(gramsText) ?? 0
    }
}

// MARK: - Print Cost Calculator View
struct PrintCostCalculatorView: View {
    let filaments: [Filament]

    // MARK: Persistent settings
    @AppStorage("calc_electricity_rate")   private var electricityRate: Double   = 0.25
    @AppStorage("calc_printer_watts")      private var printerWatts: Double      = 300
    @AppStorage("calc_printer_value")      private var printerValue: Double      = 800
    @AppStorage("calc_printer_lifetime_h") private var printerLifetimeH: Double  = 5000
    @AppStorage("calc_profit_margin")      private var profitMargin: Double       = 18

    // MARK: Per-calculation state
    @State private var hours: Int = 0
    @State private var minutes: Int = 0
    @State private var slots: [FilamentSlot] = [
        FilamentSlot(id: 0),
        FilamentSlot(id: 1),
        FilamentSlot(id: 2),
        FilamentSlot(id: 3)
    ]

    // Settings field text bindings (so we can use inline TextFields for Doubles)
    @State private var electricityRateText: String = ""
    @State private var printerWattsText: String    = ""
    @State private var printerValueText: String    = ""
    @State private var printerLifetimeText: String = ""
    @State private var profitMarginText: String    = ""

    // MARK: Computed costs
    private var durationHours: Double {
        Double(hours) + Double(minutes) / 60.0
    }

    private var filamentCost: Double {
        slots.reduce(0.0) { sum, slot in
            guard
                let fid = slot.filamentID,
                let f = filaments.first(where: { $0.id == fid }),
                f.totalWeightG > 0,
                slot.grams > 0
            else { return sum }
            let pricePerGram = f.pricePaid / f.totalWeightG
            return sum + pricePerGram * slot.grams
        }
    }

    private var electricityCost: Double {
        durationHours * (printerWatts / 1000.0) * electricityRate
    }

    private var depreciation: Double {
        guard printerLifetimeH > 0 else { return 0 }
        return durationHours * (printerValue / printerLifetimeH)
    }

    private var subtotal: Double {
        filamentCost + electricityCost + depreciation
    }

    private var profit: Double {
        subtotal * (profitMargin / 100.0)
    }

    private var total: Double {
        subtotal + profit
    }

    // MARK: Body
    var body: some View {
        NavigationStack {
            Form {
                filamentSection
                durationSection
                costSettingsSection
                breakdownSection
            }
            .navigationTitle("Cost Calculator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: resetCalculation) {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .onAppear {
                syncSettingsTexts()
            }
        }
    }

    // MARK: - Filament Section
    private var filamentSection: some View {
        Section {
            ForEach($slots) { $slot in
                SlotRow(
                    slot: $slot,
                    filaments: filaments,
                    slotIndex: slot.id
                )
            }
        } header: {
            Text("Filament")
        } footer: {
            Text("Select up to 4 filaments and enter the grams used for each.")
        }
    }

    // MARK: - Duration Section
    private var durationSection: some View {
        Section {
            HStack(spacing: 16) {
                Text("Hours")
                    .frame(minWidth: 44, alignment: .leading)
                Stepper(value: $hours, in: 0...48) {
                    Text("\(hours)")
                        .monospacedDigit()
                        .frame(minWidth: 24, alignment: .trailing)
                }

                Divider()

                Text("Min")
                    .frame(minWidth: 28, alignment: .leading)
                Stepper(value: $minutes, in: 0...59) {
                    Text("\(String(format: "%02d", minutes))")
                        .monospacedDigit()
                        .frame(minWidth: 24, alignment: .trailing)
                }
            }
        } header: {
            Text("Print Duration")
        } footer: {
            Text("Total: \(durationLabel)")
                .foregroundColor(.secondary)
        }
    }

    private var durationLabel: String {
        if hours == 0 && minutes == 0 { return "0 min" }
        if hours == 0 { return "\(minutes) min" }
        if minutes == 0 { return "\(hours) h" }
        return "\(hours) h \(minutes) min"
    }

    // MARK: - Cost Settings Section
    private var costSettingsSection: some View {
        Section {
            SettingRow(
                label: "Electricity Rate",
                unit: "€/kWh",
                info: "Your energy provider's rate per kilowatt-hour.",
                text: $electricityRateText
            ) { if let v = Double(electricityRateText) { electricityRate = v } }

            SettingRow(
                label: "Printer Power",
                unit: "W",
                info: "Typical power draw of your printer during printing.",
                text: $printerWattsText
            ) { if let v = Double(printerWattsText) { printerWatts = v } }

            SettingRow(
                label: "Printer Value",
                unit: "€",
                info: "Purchase price of your printer for depreciation calculation.",
                text: $printerValueText
            ) { if let v = Double(printerValueText) { printerValue = v } }

            SettingRow(
                label: "Printer Lifetime",
                unit: "h",
                info: "Expected total printing hours before the printer needs replacing.",
                text: $printerLifetimeText
            ) { if let v = Double(printerLifetimeText) { printerLifetimeH = v } }

            SettingRow(
                label: "Profit Margin",
                unit: "%",
                info: "Mark-up percentage to add on top of all costs.",
                text: $profitMarginText
            ) { if let v = Double(profitMarginText) { profitMargin = v } }
        } header: {
            Text("Cost Settings")
        } footer: {
            Text("Settings are saved automatically and persist between sessions.")
        }
    }

    // MARK: - Breakdown Section
    private var breakdownSection: some View {
        Section {
            BreakdownRow(label: "Filament", value: filamentCost, color: .orange)
            BreakdownRow(label: "Electricity", value: electricityCost, color: .yellow)
            BreakdownRow(label: "Printer Wear", value: depreciation, color: .blue)

            Divider()
                .padding(.vertical, 2)

            BreakdownRow(label: "Subtotal", value: subtotal, color: .primary)
            BreakdownRow(label: "Profit (\(formattedPercent)%)", value: profit, color: .green)

            Divider()
                .padding(.vertical, 4)

            HStack {
                Text("Total")
                    .font(.title2)
                    .fontWeight(.black)
                Spacer()
                Text(euroFormatted(total))
                    .font(.title2)
                    .fontWeight(.black)
                    .foregroundColor(.orange)
            }
            .padding(.vertical, 6)
        } header: {
            Text("Breakdown")
        } footer: {
            if total == 0 {
                Text("Fill in print duration and at least one filament slot to see costs.")
            }
        }
    }

    // MARK: - Helpers
    private var formattedPercent: String {
        profitMargin.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", profitMargin)
            : String(format: "%.1f", profitMargin)
    }

    private func euroFormatted(_ value: Double) -> String {
        String(format: "€%.2f", value)
    }

    private func syncSettingsTexts() {
        electricityRateText = formatSettingDouble(electricityRate)
        printerWattsText    = formatSettingDouble(printerWatts)
        printerValueText    = formatSettingDouble(printerValue)
        printerLifetimeText = formatSettingDouble(printerLifetimeH)
        profitMarginText    = formatSettingDouble(profitMargin)
    }

    private func formatSettingDouble(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", v)
            : String(format: "%.2f", v)
    }

    private func resetCalculation() {
        hours   = 0
        minutes = 0
        slots   = [
            FilamentSlot(id: 0),
            FilamentSlot(id: 1),
            FilamentSlot(id: 2),
            FilamentSlot(id: 3)
        ]
    }
}

// MARK: - Slot Row
private struct SlotRow: View {
    @Binding var slot: FilamentSlot
    let filaments: [Filament]
    let slotIndex: Int

    @State private var isExpanded: Bool = false

    private var selectedFilament: Filament? {
        guard let fid = slot.filamentID else { return nil }
        return filaments.first(where: { $0.id == fid })
    }

    private var isActive: Bool {
        slot.filamentID != nil || !slot.gramsText.isEmpty
    }

    var body: some View {
        DisclosureGroup(
            isExpanded: $isExpanded,
            content: {
                VStack(alignment: .leading, spacing: 10) {
                    // Filament picker
                    Picker("Filament", selection: $slot.filamentID) {
                        Text("None").tag(String?.none)
                        ForEach(filaments) { filament in
                            FilamentPickerLabel(filament: filament)
                                .tag(String?.some(filament.id))
                        }
                    }
                    .pickerStyle(.menu)

                    // Grams field
                    HStack {
                        Text("Grams used")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        TextField("0", text: $slot.gramsText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("g")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 4)
            },
            label: {
                HStack(spacing: 10) {
                    // Slot number badge
                    Text("\(slotIndex + 1)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(width: 22, height: 22)
                        .background(isActive ? Color.orange : Color.secondary)
                        .clipShape(Circle())

                    if let f = selectedFilament {
                        // Color swatch
                        Circle()
                            .fill(f.color.color)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 0.5))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(f.brand)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Text(f.type.rawValue)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if slot.grams > 0 {
                            Text("\(String(format: "%.0f", slot.grams)) g")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("Slot \(slotIndex + 1) — None")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            }
        )
    }
}

// MARK: - Filament Picker Label
private struct FilamentPickerLabel: View {
    let filament: Filament

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(filament.color.color)
                .frame(width: 12, height: 12)
            Text("\(filament.brand) \(filament.type.rawValue) — \(filament.color.name)")
        }
        .tag(filament.id)
    }
}

// MARK: - Setting Row
private struct SettingRow: View {
    let label: String
    let unit: String
    let info: String
    @Binding var text: String
    let onCommit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                TextField("0", text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .onChange(of: text) { _ in
                        onCommit()
                    }
                Text(unit)
                    .foregroundColor(.secondary)
                    .frame(minWidth: 36, alignment: .leading)
            }
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(info)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Breakdown Row
private struct BreakdownRow: View {
    let label: String
    let value: Double
    let color: Color

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(color == .primary ? .primary : .primary)
            Spacer()
            Text(String(format: "€%.2f", value))
                .fontWeight(.medium)
                .foregroundColor(color)
                .monospacedDigit()
        }
    }
}

// MARK: - Preview
#if DEBUG
struct PrintCostCalculatorView_Previews: PreviewProvider {
    static var previews: some View {
        PrintCostCalculatorView(filaments: [])
    }
}
#endif
