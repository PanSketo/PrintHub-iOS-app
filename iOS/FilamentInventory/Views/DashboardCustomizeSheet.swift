import SwiftUI

struct DashboardCustomizeSheet: View {
    @ObservedObject var layout: DashboardLayoutStore
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach($layout.cards, id: \.id) { $config in
                        if let card = DashboardCard(rawValue: config.id) {
                            HStack(spacing: 14) {
                                Image(systemName: card.icon)
                                    .font(.body)
                                    .foregroundColor(config.isVisible ? .accentColor : .secondary)
                                    .frame(width: 26)

                                Text(card.title)
                                    .foregroundColor(config.isVisible ? .primary : .secondary)

                                Spacer()

                                Toggle("", isOn: $config.isVisible)
                                    .labelsHidden()
                                    .onChange(of: config.isVisible) { _, _ in layout.save() }
                            }
                        }
                    }
                    .onMove { from, to in
                        layout.cards.move(fromOffsets: from, toOffset: to)
                        layout.save()
                    }
                } header: {
                    Text("Drag to reorder · Toggle to show or hide")
                        .textCase(nil)
                        .font(.caption)
                }

                Section {
                    Button(role: .destructive) {
                        layout.cards = DashboardCard.allCases.map {
                            DashboardLayoutStore.CardConfig(id: $0.rawValue, isVisible: true)
                        }
                        layout.save()
                    } label: {
                        Label("Reset to Default", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Customize Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}
