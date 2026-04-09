import SwiftUI

// MARK: - Per-filament entry

private struct FilamentEntry: Identifiable {
    let id = UUID()
    var filamentId: String = ""
    var weightText: String = ""
    var weightG: Double? { Double(weightText.replacingOccurrences(of: ",", with: ".")) }
    var isValid: Bool { !filamentId.isEmpty && (weightG ?? 0) > 0 }
}

// MARK: - Sheet

struct ManualPrintLogSheet: View {
    @EnvironmentObject var store: InventoryStore
    @Environment(\.dismiss) private var dismiss

    let untracked: NASService.UntrackedPrint

    @State private var printName: String
    @State private var entries: [FilamentEntry] = [FilamentEntry()]
    @State private var success: Bool = true
    @State private var isSaving = false

    init(untracked: NASService.UntrackedPrint) {
        self.untracked = untracked
        _printName = State(initialValue: untracked.printName)
    }

    var sortedFilaments: [Filament] {
        store.filaments.sorted { "\($0.brand) \($0.color.name)" < "\($1.brand) \($1.color.name)" }
    }

    var durationText: String? {
        guard let s = untracked.durationSeconds, s > 0 else { return nil }
        let h = Int(s) / 3600
        let m = (Int(s) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    var validEntries: [(filamentId: String, weightG: Double)] {
        entries.compactMap { e in
            guard e.isValid, let g = e.weightG else { return nil }
            return (e.filamentId, g)
        }
    }

    var canSave: Bool { !validEntries.isEmpty && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                // Print info
                Section("Print") {
                    HStack {
                        Text("Name").foregroundColor(.secondary)
                        Spacer()
                        Text(printName).multilineTextAlignment(.trailing)
                    }
                    if let dur = durationText {
                        HStack {
                            Text("Duration").foregroundColor(.secondary)
                            Spacer()
                            Text(dur)
                        }
                    }
                }

                // Filament entries
                Section {
                    ForEach($entries) { $entry in
                        VStack(spacing: 10) {
                            Picker("Filament", selection: $entry.filamentId) {
                                Text("— Select filament —").tag("")
                                ForEach(sortedFilaments) { f in
                                    Label {
                                        Text("\(f.brand) \(f.type.rawValue) — \(f.color.name)")
                                    } icon: {
                                        Circle().fill(f.color.color).frame(width: 12, height: 12)
                                    }
                                    .tag(f.id)
                                }
                            }
                            .pickerStyle(.menu)

                            HStack {
                                TextField("Weight used", text: $entry.weightText)
                                    .keyboardType(.decimalPad)
                                Text("g").foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { entries.remove(atOffsets: $0) }

                    Button {
                        entries.append(FilamentEntry())
                    } label: {
                        Label("Add Filament", systemImage: "plus.circle.fill")
                            .foregroundColor(.orange)
                    }
                } header: {
                    Text("Filaments Used")
                } footer: {
                    if entries.count > 1 {
                        Text("Swipe left on an entry to remove it.")
                            .font(.caption)
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
                        .disabled(!canSave)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        store.logUntrackedPrint(
            eventId: untracked.id,
            entries: validEntries,
            printName: printName,
            durationSeconds: untracked.durationSeconds,
            success: success
        )
        dismiss()
    }
}
