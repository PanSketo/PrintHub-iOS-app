import SwiftUI

// MARK: - Filament Slot Model
private struct FilamentSlot: Identifiable {
    let id: Int
    var filamentID: String? = nil
    var gramsText: String = ""

    var grams: Double { Double(gramsText) ?? 0 }
}

// MARK: - Print Cost Calculator View
struct PrintCostCalculatorView: View {
    let filaments: [Filament]
    @Environment(\.dismiss) private var dismiss

    // MARK: Persistent settings — pre-filled with your actual business values
    @AppStorage("calc_electricity_rate")   private var electricityRate:    Double = 0.11   // €/kWh
    @AppStorage("calc_printer_watts")      private var printerWatts:       Double = 190    // W (avg 180-200W)
    @AppStorage("calc_printer_value")      private var printerValue:       Double = 820.47 // €
    @AppStorage("calc_printer_lifetime_h") private var printerLifetimeH:   Double = 3500   // hours
    @AppStorage("calc_failure_rate")       private var failureRate:        Double = 2      // %
    @AppStorage("calc_consumables_ph")     private var consumablesPH:      Double = 0.125  // €/h (€10/mo ÷ 80h/mo)
    @AppStorage("calc_profit_margin")      private var profitMargin:       Double = 18     // % (true margin)

    // MARK: Monthly fixed overhead
    @AppStorage("calc_monthly_hours")      private var monthlyHours:       Double = 80     // h/mo printing
    @AppStorage("calc_rent")               private var rent:               Double = 400    // €/mo
    @AppStorage("calc_internet")           private var internet:           Double = 50     // €/mo
    @AppStorage("calc_accounting")         private var accounting:         Double = 50     // €/mo
    @AppStorage("calc_misc")               private var misc:               Double = 0      // €/mo

    // MARK: Per-calculation state
    @State private var hours:   Int = 0
    @State private var minutes: Int = 0
    @State private var slots: [FilamentSlot] = (0..<4).map { FilamentSlot(id: $0) }

    // Text-field mirrors for Double settings
    @State private var electricityRateText:  String = ""
    @State private var printerWattsText:     String = ""
    @State private var printerValueText:     String = ""
    @State private var printerLifetimeText:  String = ""
    @State private var failureRateText:      String = ""
    @State private var consumablesPHText:    String = ""
    @State private var profitMarginText:     String = ""
    @State private var monthlyHoursText:     String = ""
    @State private var rentText:             String = ""
    @State private var internetText:         String = ""
    @State private var accountingText:       String = ""
    @State private var miscText:             String = ""

    // MARK: Computed costs

    private var durationHours: Double {
        Double(hours) + Double(minutes) / 60.0
    }

    /// Raw filament cost, then inflated by the waste/failure rate
    private var filamentCost: Double {
        let raw = slots.reduce(0.0) { sum, slot in
            guard let fid = slot.filamentID,
                  let f = filaments.first(where: { $0.id == fid }),
                  f.totalWeightG > 0, slot.grams > 0
            else { return sum }
            return sum + (f.pricePaid / f.totalWeightG) * slot.grams
        }
        return raw * (1.0 + failureRate / 100.0)
    }

    private var electricityCost: Double {
        durationHours * (printerWatts / 1_000.0) * electricityRate
    }

    private var depreciation: Double {
        guard printerLifetimeH > 0 else { return 0 }
        return durationHours * (printerValue / printerLifetimeH)
    }

    private var consumablesCost: Double {
        durationHours * consumablesPH
    }

    private var fixedOverheadCost: Double {
        guard monthlyHours > 0 else { return 0 }
        let monthlyTotal = rent + internet + accounting + misc
        return durationHours * (monthlyTotal / monthlyHours)
    }

    /// All real costs combined
    private var totalCost: Double {
        filamentCost + electricityCost + depreciation + consumablesCost + fixedOverheadCost
    }

    /// True profit margin: price = cost ÷ (1 − margin%)
    /// At 18 % margin → price = cost ÷ 0.82 ≈ cost × 1.219
    private var sellingPrice: Double {
        guard profitMargin < 100 else { return totalCost }
        return totalCost / (1.0 - profitMargin / 100.0)
    }

    private var profitAmount: Double { sellingPrice - totalCost }

    // MARK: Body
    var body: some View {
        NavigationStack {
            Form {
                filamentSection
                durationSection
                costSettingsSection
                monthlyOverheadSection
                breakdownSection
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Cost Calculator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: resetCalculation) {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil)
                    }
                }
            }
            .onAppear { syncSettingsTexts() }
        }
    }

    // MARK: - Filament Section

    private var filamentSection: some View {
        Section {
            ForEach($slots) { $slot in
                SlotRow(slot: $slot, filaments: filaments, slotIndex: slot.id)
            }
        } header: {
            Text("Filament")
        } footer: {
            Text("Select filaments and enter the grams used. A \(Int(failureRate))% waste buffer is applied automatically.")
        }
    }

    // MARK: - Duration Section

    private var durationSection: some View {
        Section {
            Stepper(value: $hours, in: 0...48) {
                HStack {
                    Text("Hours")
                    Spacer()
                    Text("\(hours) h")
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
            }
            Stepper(value: $minutes, in: 0...59) {
                HStack {
                    Text("Minutes")
                    Spacer()
                    Text(String(format: "%02d", minutes) + " min")
                        .monospacedDigit()
                        .foregroundColor(.secondary)
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
        if hours == 0  { return "\(minutes) min" }
        if minutes == 0 { return "\(hours) h" }
        return "\(hours) h \(minutes) min"
    }

    // MARK: - Cost Settings Section

    private var costSettingsSection: some View {
        Section {
            SettingRow(
                label: "Electricity Rate", unit: "€/kWh",
                info: "Your energy rate per kWh. Current: 0.11 €/kWh.",
                text: $electricityRateText
            ) { if let v = Double(electricityRateText) { electricityRate = v } }

            SettingRow(
                label: "Printer Power", unit: "W",
                info: "Average draw while printing. Your P2S averages ~190 W.",
                text: $printerWattsText
            ) { if let v = Double(printerWattsText) { printerWatts = v } }

            SettingRow(
                label: "Printer Value", unit: "€",
                info: "Purchase price used for depreciation. Your printer: €820.47.",
                text: $printerValueText
            ) { if let v = Double(printerValueText) { printerValue = v } }

            SettingRow(
                label: "Printer Lifetime", unit: "h",
                info: "Expected total print hours before replacement/overhaul.",
                text: $printerLifetimeText
            ) { if let v = Double(printerLifetimeText) { printerLifetimeH = v } }

            SettingRow(
                label: "Waste / Failure Rate", unit: "%",
                info: "Filament wasted on failed prints. Your estimate: 2%.",
                text: $failureRateText
            ) { if let v = Double(failureRateText) { failureRate = max(0, v) } }

            SettingRow(
                label: "Consumables", unit: "€/h",
                info: "Nozzles, build plates, maintenance per hour. Calculated from your ~€10/mo ÷ 80 h/mo = 0.125 €/h.",
                text: $consumablesPHText
            ) { if let v = Double(consumablesPHText) { consumablesPH = max(0, v) } }

            SettingRow(
                label: "Profit Margin", unit: "%",
                info: "True margin (% of selling price). At 18%: selling price = cost ÷ 0.82.",
                text: $profitMarginText
            ) { if let v = Double(profitMarginText) { profitMargin = min(max(0, v), 99) } }
        } header: {
            Text("Business Settings")
        } footer: {
            Text("All settings are saved automatically. Adjust consumables if your monthly spend changes.")
        }
    }

    // MARK: - Monthly Overhead Section

    private var monthlyOverheadSection: some View {
        Section {
            SettingRow(
                label: "Rent", unit: "€/mo",
                info: "Monthly rent or workspace cost.",
                text: $rentText
            ) { if let v = Double(rentText) { rent = max(0, v) } }

            SettingRow(
                label: "Internet", unit: "€/mo",
                info: "Monthly internet/connectivity cost.",
                text: $internetText
            ) { if let v = Double(internetText) { internet = max(0, v) } }

            SettingRow(
                label: "Accounting", unit: "€/mo",
                info: "Monthly accountant or bookkeeping cost.",
                text: $accountingText
            ) { if let v = Double(accountingText) { accounting = max(0, v) } }

            SettingRow(
                label: "Misc", unit: "€/mo",
                info: "Any other monthly business expense.",
                text: $miscText
            ) { if let v = Double(miscText) { misc = max(0, v) } }

            SettingRow(
                label: "Monthly Print Hours", unit: "h/mo",
                info: "How many hours per month the printer runs. Used to split fixed costs across prints.",
                text: $monthlyHoursText
            ) { if let v = Double(monthlyHoursText), v > 0 { monthlyHours = v } }
        } header: {
            Text("Monthly Overhead")
        } footer: {
            let total = rent + internet + accounting + misc
            let perHour = monthlyHours > 0 ? total / monthlyHours : 0
            Text("Total €\(euDecimal(total, decimals: 0))/mo ÷ \(Int(monthlyHours)) h/mo = \(euDecimal(perHour, decimals: 2)) €/h added to each print.")
        }
    }

    // MARK: - Breakdown Section

    private var breakdownSection: some View {
        Section {
            BreakdownRow(label: "Filament (incl. \(Int(failureRate))% waste)",
                         value: filamentCost, color: .orange)
            BreakdownRow(label: "Electricity",
                         value: electricityCost, color: .yellow)
            BreakdownRow(label: "Printer Wear",
                         value: depreciation, color: .blue)
            BreakdownRow(label: "Consumables",
                         value: consumablesCost, color: .purple)
            BreakdownRow(label: "Fixed Overhead",
                         value: fixedOverheadCost, color: .teal)

            BreakdownRow(label: "Total Cost", value: totalCost, color: .primary)
                .padding(.top, 4)
            BreakdownRow(
                label: "Profit (\(formattedPercent)% margin)",
                value: profitAmount, color: .green
            )

            // Selling price — the number to quote the customer
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Selling Price")
                        .font(.title2).fontWeight(.black)
                    Text("Quote this to the customer")
                        .font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
                Text(euroFormatted(sellingPrice))
                    .font(.title2).fontWeight(.black)
                    .foregroundColor(.orange)
            }
            .padding(.vertical, 6)
        } header: {
            Text("Breakdown")
        } footer: {
            if sellingPrice == 0 {
                Text("Enter print duration and at least one filament to see the cost breakdown.")
            } else {
                Text("Cost: \(euroFormatted(totalCost))  ·  Profit: \(euroFormatted(profitAmount))  ·  Margin: \(formattedPercent)%")
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private var formattedPercent: String {
        profitMargin.truncatingRemainder(dividingBy: 1) == 0
            ? euDecimal(profitMargin, decimals: 0)
            : euDecimal(profitMargin, decimals: 1)
    }

    private func euroFormatted(_ value: Double) -> String {
        euEuro(value)
    }

    private func syncSettingsTexts() {
        func fmt(_ v: Double) -> String {
            v.truncatingRemainder(dividingBy: 1) == 0
                ? euDecimal(v, decimals: 0)
                : euDecimal(v, decimals: 3).replacingOccurrences(of: #"[,]?0+$"#, with: "",
                                                                   options: .regularExpression)
        }
        electricityRateText = fmt(electricityRate)
        printerWattsText    = fmt(printerWatts)
        printerValueText    = fmt(printerValue)
        printerLifetimeText = fmt(printerLifetimeH)
        failureRateText     = fmt(failureRate)
        consumablesPHText   = fmt(consumablesPH)
        profitMarginText    = fmt(profitMargin)
        monthlyHoursText    = fmt(monthlyHours)
        rentText            = fmt(rent)
        internetText        = fmt(internet)
        accountingText      = fmt(accounting)
        miscText            = fmt(misc)
    }

    private func resetCalculation() {
        hours   = 0
        minutes = 0
        slots   = (0..<4).map { FilamentSlot(id: $0) }
    }
}

// MARK: - Slot Row

private struct SlotRow: View {
    @Binding var slot: FilamentSlot
    let filaments: [Filament]
    let slotIndex: Int

    @State private var isExpanded = false

    private var selectedFilament: Filament? {
        guard let fid = slot.filamentID else { return nil }
        return filaments.first(where: { $0.id == fid })
    }

    private var isActive: Bool { slot.filamentID != nil || !slot.gramsText.isEmpty }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Filament", selection: $slot.filamentID) {
                    Text("None").tag(String?.none)
                    ForEach(filaments) { f in
                        FilamentPickerLabel(filament: f).tag(String?.some(f.id))
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    Text("Grams used")
                        .font(.subheadline).foregroundColor(.secondary)
                    Spacer()
                    TextField("0", text: $slot.gramsText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("g").foregroundColor(.secondary)
                }
            }
            .padding(.top, 4)
        } label: {
            HStack(spacing: 10) {
                Text("\(slotIndex + 1)")
                    .font(.caption).fontWeight(.bold).foregroundColor(.white)
                    .frame(width: 22, height: 22)
                    .background(isActive ? Color.orange : Color.secondary)
                    .clipShape(Circle())

                if let f = selectedFilament {
                    Circle()
                        .fill(f.color.color)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 0.5))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(f.brand).font(.subheadline).fontWeight(.medium).lineLimit(1)
                        Text(f.type.rawValue).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    if slot.grams > 0 {
                        Text(euGrams(slot.grams))
                            .font(.caption).foregroundColor(.secondary)
                    }
                } else {
                    Text("Slot \(slotIndex + 1) — None")
                        .font(.subheadline).foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Filament Picker Label

private struct FilamentPickerLabel: View {
    let filament: Filament
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(filament.color.color).frame(width: 12, height: 12)
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
                    .onChange(of: text) { _ in onCommit() }
                Text(unit)
                    .foregroundColor(.secondary)
                    .frame(minWidth: 36, alignment: .leading)
            }
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.caption2).foregroundColor(.secondary)
                Text(info)
                    .font(.caption2).foregroundColor(.secondary)
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
            Spacer()
            Text(euEuro(value))
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
