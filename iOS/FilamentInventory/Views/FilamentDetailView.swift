import SwiftUI

struct FilamentDetailView: View {
    @EnvironmentObject var store: InventoryStore
    var filament: Filament
    @State private var currentFilament: Filament
    @State private var showEditSheet = false
    @State private var showLogPrint = false
    @State private var showDeleteAlert = false
    @Environment(\.dismiss) var dismiss

    init(filament: Filament) {
        self.filament = filament
        _currentFilament = State(initialValue: filament)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Hero Color Card
                HeroColorCard(filament: currentFilament)

                // Print Spec Info (if available)
                if currentFilament.printTempMin != nil {
                    PrintSpecCard(filament: currentFilament)
                }

                // Weight Management
                WeightManagementCard(filament: $currentFilament)

                // Print Jobs History
                if !currentFilament.printJobs.isEmpty {
                    PrintHistoryCard(printJobs: currentFilament.printJobs)
                }

                // Cost Info
                CostInfoCard(filament: currentFilament)

                // Notes
                if !currentFilament.notes.isEmpty {
                    NotesCard(notes: currentFilament.notes)
                }

                // Price History
                PriceHistoryView(filament: currentFilament, currentFilament: $currentFilament)
                    .environmentObject(store)

                // Delete
                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    Label("Delete Spool", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .padding(.horizontal)
            }
            .padding(.bottom, 40)
        }
        .navigationTitle("\(currentFilament.brand) \(currentFilament.type.rawValue)")
        .navigationBarTitleDisplayMode(.inline)
        .background(SwipeBackEnabler())   // re-enables swipe-back when toolbar buttons are present
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button("Log Print") { showLogPrint = true }
                    .foregroundColor(.orange)
                Button(action: { showEditSheet = true }) {
                    Image(systemName: "pencil")
                }
            }
        }
        .sheet(isPresented: $showLogPrint) {
            LogPrintView(filament: currentFilament) { job in
                store.logPrintJob(job)
                currentFilament.remainingWeightG = max(0, currentFilament.remainingWeightG - job.weightUsedG)
                currentFilament.stockStatus = StockStatus.from(remaining: currentFilament.remainingWeightG, total: currentFilament.totalWeightG)
                currentFilament.printJobs.append(job)
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditFilamentView(filament: $currentFilament) { updated in
                store.updateFilament(updated)
            }
        }
        .alert("Delete Spool?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                store.deleteFilament(id: currentFilament.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove \(currentFilament.brand) \(currentFilament.color.name) from your inventory.")
        }
    }
}

// MARK: - Hero Color Card
struct HeroColorCard: View {
    let filament: Filament
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [filament.color.color, filament.color.color.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 200)

            // Filament image or logo overlay
            if let img = image {
                HStack {
                    Spacer()
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                        .shadow(radius: 8)
                        .padding()
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(filament.brand)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)

                Text(filament.type.rawValue)
                    .font(.largeTitle)
                    .fontWeight(.black)
                    .foregroundColor(.white)

                Text(filament.color.name)
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.9))

                HStack {
                    Image(systemName: filament.stockStatus.icon)
                    Text(filament.stockStatus.rawValue)
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(filament.stockStatus.color)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial)
                .cornerRadius(8)
            }
            .padding()
        }
        .padding(.horizontal)
        .onAppear { loadImage() }
    }

    func loadImage() {
        let urlStr = filament.imageURL ?? filament.brandLogoURL
        guard let str = urlStr, let url = URL(string: str) else { return }
        Task {
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let img = UIImage(data: data) {
                await MainActor.run { self.image = img }
            }
        }
    }
}

// MARK: - Print Spec Card
struct PrintSpecCard: View {
    let filament: Filament

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Print Settings", systemImage: "thermometer")
                .font(.headline)

            HStack(spacing: 16) {
                if let min = filament.printTempMin, let max = filament.printTempMax {
                    SpecItem(label: "Nozzle", value: "\(min)–\(max)°C", icon: "flame.fill", color: .orange)
                }
                if let min = filament.bedTempMin, let max = filament.bedTempMax {
                    SpecItem(label: "Bed", value: "\(min)–\(max)°C", icon: "square.fill", color: .blue)
                }
                SpecItem(label: "Diameter", value: "\(filament.diameter)mm", icon: "circle", color: .purple)
            }
        }
        .padding()
        .glassCard()
        .padding(.horizontal)
    }
}

struct SpecItem: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .glassInnerCard()
    }
}

// MARK: - Weight Management Card
struct WeightManagementCard: View {
    @EnvironmentObject var store: InventoryStore
    @Binding var filament: Filament
    @State private var manualWeight: String = ""
    @State private var isEditing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Weight", systemImage: "scalemass.fill")
                .font(.headline)

            // Progress ring
            HStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(Color(.systemFill), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: CGFloat(filament.percentageRemaining / 100))
                        .stroke(filament.stockStatus.color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack {
                        Text("\(Int(filament.percentageRemaining))%")
                            .font(.title2)
                            .fontWeight(.black)
                        Text("left")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 90, height: 90)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Remaining:").foregroundColor(.secondary).font(.subheadline)
                        Text("\(Int(filament.remainingWeightG))g").fontWeight(.bold)
                    }
                    HStack {
                        Text("Used:").foregroundColor(.secondary).font(.subheadline)
                        Text("\(Int(filament.usedWeightG))g").fontWeight(.bold)
                    }
                    HStack {
                        Text("Total:").foregroundColor(.secondary).font(.subheadline)
                        Text("\(Int(filament.totalWeightG))g").fontWeight(.bold)
                    }
                }
                Spacer()
            }

            // Manual weight update
            if isEditing {
                HStack {
                    TextField("Enter weight in grams", text: $manualWeight)
                        .keyboardType(.numberPad)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Button("Save") {
                        if let w = Double(manualWeight) {
                            filament.remainingWeightG = min(w, filament.totalWeightG)
                            filament.stockStatus = StockStatus.from(remaining: filament.remainingWeightG, total: filament.totalWeightG)
                            store.updateFilament(filament)
                            isEditing = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
            } else {
                Button("Update Remaining Weight") {
                    manualWeight = String(Int(filament.remainingWeightG))
                    isEditing = true
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .glassCard()
        .padding(.horizontal)
    }
}

// MARK: - Print History Card
struct PrintHistoryCard: View {
    let printJobs: [PrintJob]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Print History", systemImage: "printer.fill")
                .font(.headline)

            ForEach(printJobs.sorted(by: { $0.date > $1.date })) { job in
                HStack {
                    Image(systemName: job.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(job.success ? .green : .red)
                    VStack(alignment: .leading) {
                        Text(job.printName).font(.subheadline)
                        Text(job.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int(job.weightUsedG))g")
                            .font(.subheadline).fontWeight(.bold)
                        if let cost = job.costEUR {
                            Text(String(format: "€%.3f", cost))
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }
                Divider()
            }
        }
        .padding()
        .glassCard()
        .padding(.horizontal)
    }
}

// MARK: - Cost Info Card
struct CostInfoCard: View {
    let filament: Filament

    var costPerGram: Double {
        guard filament.totalWeightG > 0 else { return 0 }
        return filament.pricePaid / filament.totalWeightG
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 4) {
                Text(String(format: "€%.2f", filament.pricePaid))
                    .font(.title2).fontWeight(.black)
                Text("Paid").font(.caption).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 40)

            VStack(spacing: 4) {
                Text(String(format: "€%.4f", costPerGram))
                    .font(.title2).fontWeight(.black)
                Text("Per Gram").font(.caption).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 40)

            VStack(spacing: 4) {
                Text(filament.purchaseDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline).fontWeight(.bold)
                Text("Purchased").font(.caption).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .glassCard()
        .padding(.horizontal)
    }
}

// MARK: - Notes Card
struct NotesCard: View {
    let notes: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Notes", systemImage: "note.text")
                .font(.headline)
            Text(notes)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassCard()
        .padding(.horizontal)
    }
}

// MARK: - Swipe Back Enabler
// iOS disables the interactive pop gesture when custom toolbar buttons are present.
// This invisible UIViewControllerRepresentable re-enables it.
private struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        SwipeBackViewController()
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

private class SwipeBackViewController: UIViewController {
    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if let nav = navigationController {
            nav.interactivePopGestureRecognizer?.isEnabled = true
            nav.interactivePopGestureRecognizer?.delegate = nil
        }
    }
}
