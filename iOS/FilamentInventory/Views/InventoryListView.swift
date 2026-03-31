import SwiftUI

struct InventoryListView: View {
    @EnvironmentObject var store: InventoryStore
    @State private var searchText = ""
    @State private var selectedType: FilamentType? = nil
    @State private var selectedStatus: StockStatus? = nil
    @AppStorage("inventory_view_mode") private var viewModeRaw: String = ViewMode.grid.rawValue

    enum ViewMode: String { case grid, list }

    var viewMode: ViewMode { ViewMode(rawValue: viewModeRaw) ?? .grid }

    var filtered: [Filament] {
        store.filteredFilaments(searchText: searchText, type: selectedType, status: selectedStatus)
    }

    @State private var showAddFilament = false

    var body: some View {
        NavigationStack {
            Group {
                if store.filaments.isEmpty && !store.isLoading {
                    EmptyInventoryView()
                } else {
                    VStack(spacing: 0) {
                        // Filter chips
                        FilterChipsView(selectedType: $selectedType, selectedStatus: $selectedStatus)
                            .padding(.horizontal)
                            .padding(.top, 8)

                        if viewMode == .grid {
                            GridInventoryView(filaments: filtered)
                        } else {
                            ListInventoryView(filaments: filtered)
                        }
                    }
                }
            }
            .navigationTitle("Inventory")
            .searchable(text: $searchText, prompt: "Search brand, color, type...")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { viewModeRaw = viewMode == .grid ? ViewMode.list.rawValue : ViewMode.grid.rawValue }) {
                        Image(systemName: viewMode == .grid ? "list.bullet" : "square.grid.2x2")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showAddFilament = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddFilament) {
                AddFilamentView()
                    .environmentObject(store)
            }
        }
    }
}

// MARK: - Filter Chips
struct FilterChipsView: View {
    @Binding var selectedType: FilamentType?
    @Binding var selectedStatus: StockStatus?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Clear all
                if selectedType != nil || selectedStatus != nil {
                    Button("Clear") {
                        selectedType = nil
                        selectedStatus = nil
                    }
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.1))
                    .foregroundColor(.red)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }

                ForEach(StockStatus.allCases, id: \.self) { status in
                    FilterChip(
                        label: status.rawValue,
                        icon: status.icon,
                        color: status.color,
                        isSelected: selectedStatus == status
                    ) {
                        selectedStatus = selectedStatus == status ? nil : status
                    }
                }

                Divider().frame(height: 20)

                ForEach(FilamentType.allCases, id: \.self) { type in
                    FilterChip(
                        label: type.rawValue,
                        icon: type.icon,
                        color: .orange,
                        isSelected: selectedType == type
                    ) {
                        selectedType = selectedType == type ? nil : type
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct FilterChip: View {
    let label: String
    let icon: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(label)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? color.opacity(0.2) : Color(.secondarySystemBackground))
            .foregroundColor(isSelected ? color : .secondary)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? color : Color.clear, lineWidth: 1.5)
            )
        }
    }
}

// MARK: - Grid View
struct GridInventoryView: View {
    @EnvironmentObject var store: InventoryStore
    let filaments: [Filament]
    let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(filaments) { filament in
                    NavigationLink(destination: FilamentDetailView(filament: filament)) {
                        FilamentGridCard(filament: filament)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .contextMenu {
                        Button { duplicateFilament(filament) } label: {
                            Label("Duplicate Spool", systemImage: "doc.on.doc")
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func duplicateFilament(_ filament: Filament) {
        var copy = filament
        copy.id = UUID().uuidString
        copy.remainingWeightG = filament.totalWeightG
        copy.printJobs = []
        copy.lastUpdated = Date()
        store.addFilament(copy)
    }
}

// MARK: - Grid Card
struct FilamentGridCard: View {
    let filament: Filament
    @State private var spoolImage: UIImage? = nil
    @State private var brandLogoImage: UIImage? = nil
    @State private var imageLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // ── Image area ──────────────────────────────────────────
            ZStack(alignment: .topTrailing) {
                // Background: filament colour tint
                RoundedRectangle(cornerRadius: 12)
                    .fill(filament.color.color.opacity(0.18))
                    .frame(height: 110)

                // Spool image (fills the card top)
                if let img = spoolImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            // Gradient scrim so text stays readable
                            LinearGradient(
                                colors: [.clear, Color.black.opacity(0.35)],
                                startPoint: .top, endPoint: .bottom
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        )
                } else if imageLoading {
                    // Shimmer placeholder
                    RoundedRectangle(cornerRadius: 12)
                        .fill(filament.color.color.opacity(0.25))
                        .frame(height: 110)
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(filament.color.color)
                        )
                } else {
                    // No image found — show colour swatch + spool icon
                    RoundedRectangle(cornerRadius: 12)
                        .fill(filament.color.color.opacity(0.85))
                        .frame(height: 110)
                        .overlay(
                            Image(systemName: "cylinder.split.1x2.fill")
                                .font(.system(size: 36))
                                .foregroundColor(.white.opacity(0.7))
                        )
                }

                // Brand logo badge (top-left)
                if let logo = brandLogoImage {
                    Image(uiImage: logo)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .background(Color(.systemBackground).opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Stock status badge (top-right)
                Image(systemName: filament.stockStatus.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(filament.stockStatus.color)
                    .padding(5)
                    .background(Color(.systemBackground).opacity(0.92))
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.12), radius: 3)
                    .padding(6)
            }

            // ── Info ────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 3) {
                Text(filament.brand)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text("\(filament.type.rawValue) • \(filament.color.name)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            // ── Weight progress bar ─────────────────────────────────
            VStack(alignment: .leading, spacing: 3) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(.systemFill))
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(filament.stockStatus.color)
                            .frame(width: geo.size.width * CGFloat(filament.percentageRemaining / 100), height: 6)
                    }
                }
                .frame(height: 6)

                Text("\(Int(filament.remainingWeightG))g / \(Int(filament.totalWeightG))g")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .glassCard()
        .shadow(color: Color.black.opacity(0.06), radius: 5, x: 0, y: 2)
        .onAppear { loadImages() }
    }

    func loadImages() {
        Task {
            // Step 1: Try imageURL stored on the filament (set when spool was added)
            if let urlStr = filament.imageURL,
               let url = URL(string: urlStr),
               let img = await downloadImage(from: url) {
                await MainActor.run { self.spoolImage = img; self.imageLoading = false }

            // Step 2: brandLogoURL is a fallback but NOT a spool photo — skip it for main image
            // Step 3: Fetch live from the internet using brand + color + type
            } else {
                let fetchedURL = await FilamentLookupService.shared.searchFilamentImage(
                    brand: filament.brand,
                    color: filament.color.name,
                    type: filament.type.rawValue
                )
                if let urlStr = fetchedURL,
                   let url = URL(string: urlStr),
                   let img = await downloadImage(from: url) {
                    await MainActor.run { self.spoolImage = img; self.imageLoading = false }
                } else {
                    // Nothing found — show colour swatch fallback
                    await MainActor.run { self.imageLoading = false }
                }
            }

            // Brand logo badge (separate, always small top-left corner)
            if let urlStr = filament.brandLogoURL,
               let url = URL(string: urlStr),
               let img = await downloadImage(from: url) {
                await MainActor.run { self.brandLogoImage = img }
            }
        }
    }

    func downloadImage(from url: URL) async -> UIImage? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let img = UIImage(data: data) else { return nil }
        return img
    }

    // Keep old name for any legacy callsites
    func loadBrandLogo() { loadImages() }
}

// MARK: - List View
struct ListInventoryView: View {
    @EnvironmentObject var store: InventoryStore
    let filaments: [Filament]

    var body: some View {
        List {
            ForEach(filaments) { filament in
                NavigationLink(destination: FilamentDetailView(filament: filament)) {
                    FilamentListRow(filament: filament)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .leading) {
                    Button { duplicateFilament(filament) } label: {
                        Label("Duplicate", systemImage: "doc.on.doc")
                    }
                    .tint(.blue)
                }
                .contextMenu {
                    Button { duplicateFilament(filament) } label: {
                        Label("Duplicate Spool", systemImage: "doc.on.doc")
                    }
                }
            }
            .onDelete { indexSet in
                indexSet.forEach { idx in
                    store.deleteFilament(id: filaments[idx].id)
                }
            }
        }
    }

    private func duplicateFilament(_ filament: Filament) {
        var copy = filament
        copy.id = UUID().uuidString
        copy.remainingWeightG = filament.totalWeightG
        copy.printJobs = []
        copy.lastUpdated = Date()
        store.addFilament(copy)
    }
}

struct FilamentListRow: View {
    let filament: Filament

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(filament.color.color)
                .frame(width: 36, height: 36)
                .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                .shadow(radius: 2)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(filament.brand) \(filament.type.rawValue)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("\(filament.color.name) • \(filament.sku)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(Int(filament.remainingWeightG))g")
                    .font(.subheadline)
                    .fontWeight(.bold)
                Image(systemName: filament.stockStatus.icon)
                    .foregroundColor(filament.stockStatus.color)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Empty State
struct EmptyInventoryView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "shippingbox")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            Text("No Filaments Yet")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Tap the + button above to add your first filament spool")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
