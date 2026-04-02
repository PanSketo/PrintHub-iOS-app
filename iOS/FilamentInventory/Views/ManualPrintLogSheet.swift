import SwiftUI

struct ManualPrintLogSheet: View {
    @EnvironmentObject var store: InventoryStore
    @Environment(\.dismiss) private var dismiss

    let untracked: NASService.UntrackedPrint

    @State private var printName: String
    @State private var selectedFilamentId: String = ""
    @State private var weightText: String = ""
    @State private var success: Bool = true
    @State private var isSaving = false

    init(untracked: NASService.UntrackedPrint) {
        self.untracked = untracked
        _printName = State(initialValue: untracked.printName)
    }

    var selectedFilament: Filament? {
        store.filaments.first { $0.id == selectedFilamentId }
    }

    var weightG: Double? { Double(weightText) }

    var durationText: String? {
        guard let s = untracked.durationSeconds, s > 0 else { return nil }
        let h = Int(s) / 3600
        let m = (Int(s) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Print") {
                    HStack {
                        Text("Name")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(printName)
                            .multilineTextAlignment(.trailing)
                    }
                    if let dur = durationText {
                        HStack {
                            Text("Duration")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(dur)
                        }
                    }
                }

                Section("Filament Used") {
                    Picker("Filament", selection: $selectedFilamentId) {
                        Text("— Select —").tag("")
                        ForEach(store.filaments.sorted { "\($0.brand) \($0.color.name)" < "\($1.brand) \($1.color.name)" }) { f in
                            Text("\(f.brand) \(f.type.rawValue) \(f.color.name)")
                                .tag(f.id)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section("Weight Used") {
                    HStack {
                        TextField("e.g. 145", text: $weightText)
                            .keyboardType(.decimalPad)
                        Text("g")
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    Toggle("Print succeeded", isOn: $success)
                }
            }
            .navigationTitle("Log Print Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(selectedFilamentId.isEmpty || weightG == nil || weightG! <= 0 || isSaving)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func save() {
        guard let grams = weightG, grams > 0, !selectedFilamentId.isEmpty else { return }
        isSaving = true
        store.logUntrackedPrint(
            eventId: untracked.id,
            filamentId: selectedFilamentId,
            printName: printName,
            weightG: grams,
            durationSeconds: untracked.durationSeconds,
            success: success
        )
        dismiss()
    }
}
