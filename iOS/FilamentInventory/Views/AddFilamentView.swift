import SwiftUI
import AVFoundation

struct AddFilamentView: View {
    @EnvironmentObject var store: InventoryStore
    @FocusState private var focusedField: FormField?

    // Single sheet controller — iOS only supports one .sheet per view
    enum ActiveSheet: Identifiable {
        case scanner
        case restock(Filament)
        var id: String {
            switch self {
            case .scanner: return "scanner"
            case .restock(let f): return "restock_\(f.id)"
            }
        }
    }
    @State private var activeSheet: ActiveSheet? = nil

    @State private var isLookingUp = false
    @State private var isFetchingImage = false
    @State private var lookupResult: FilamentLookupResult? = nil
    @State private var fetchedImagePreview: UIImage? = nil

    // Form fields
    @State private var brand = ""
    @State private var sku = ""
    @State private var barcode = ""
    @State private var selectedType: FilamentType = .pla
    @State private var colorName = ""
    @State private var colorHex = "#FF6600"
    @State private var totalWeight: Double = 1000
    @State private var remainingWeight: Double = 1000
    @State private var pricePaid: String = ""
    @State private var notes = ""
    @State private var imageURL = ""
    @State private var showSuccess = false
    @State private var savedBrand = ""
    @State private var savedType = ""
    @State private var savedColor = ""
    @State private var errorMessage: String?

    enum FormField { case brand, sku, colorName, price, notes, imageURL }

    var canFetchImage: Bool { !brand.isEmpty && !colorName.isEmpty }

    var body: some View {
        NavigationView {
            Form {
                // Barcode Section
                Section {
                    Button {
                        focusedField = nil
                        activeSheet = .scanner
                    } label: {
                        HStack {
                            Image(systemName: "barcode.viewfinder")
                                .font(.title2)
                                .foregroundColor(.orange)
                            VStack(alignment: .leading) {
                                Text("Scan Barcode")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                Text("Auto-fill filament info from barcode")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if isLookingUp {
                                ProgressView()
                            } else if lookupResult != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)

                    if !barcode.isEmpty {
                        HStack {
                            Text("Barcode:")
                                .foregroundColor(.secondary)
                            Text(barcode)
                                .fontWeight(.medium)
                            Spacer()
                            Button("Clear") {
                                barcode = ""
                                lookupResult = nil
                            }
                            .foregroundColor(.red)
                            .font(.caption)
                        }
                    }
                } header: {
                    Text("Quick Scan")
                }

                // Brand & Product Info
                Section {
                    HStack {
                        Text("Brand")
                        Spacer()
                        TextField("e.g. Bambu Lab", text: $brand)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .brand)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .sku }
                    }
                    HStack {
                        Text("SKU")
                        Spacer()
                        TextField("Product SKU", text: $sku)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .sku)
                            .submitLabel(.next)
                            .onSubmit {
                                if let match = findExistingFilament(barcode: nil, sku: sku) {
                                    activeSheet = .restock(match)
                                } else {
                                    focusedField = colorName.isEmpty ? .colorName : nil
                                }
                            }
                            .onChange(of: sku) { newSKU in
                                if newSKU.count >= 4,
                                   let match = findExistingFilament(barcode: nil, sku: newSKU) {
                                    activeSheet = .restock(match)
                                }
                            }
                    }
                    HStack {
                        Text("Type")
                        Spacer()
                        Menu {
                            ForEach(FilamentType.allCases, id: \.self) { type in
                                Button(type.rawValue) { selectedType = type }
                            }
                        } label: {
                            Text(selectedType.rawValue)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Product Info")
                }

                // Color
                Section {
                    HStack {
                        Text("Color Name")
                        Spacer()
                        TextField("e.g. Galaxy Black", text: $colorName)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .colorName)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .price }
                    }
                    HStack {
                        Text("Color")
                        Spacer()
                        ColorSwatchPicker(hexCode: $colorHex)
                    }
                } header: {
                    Text("Color")
                }

                // Weight
                Section {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Spool Weight")
                            Spacer()
                            Text("\(Int(totalWeight))g")
                                .fontWeight(.semibold)
                        }
                        Slider(value: $totalWeight, in: 100...5000, step: 50)
                            .accentColor(.orange)
                            .onChange(of: totalWeight) { newVal in
                                if remainingWeight > newVal { remainingWeight = newVal }
                            }
                    }
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Remaining Weight")
                            Spacer()
                            Text("\(Int(remainingWeight))g")
                                .fontWeight(.semibold)
                        }
                        Slider(value: $remainingWeight, in: 0...totalWeight, step: 10)
                            .accentColor(.blue)
                    }
                } header: {
                    Text("Weight")
                }

                // Price
                Section {
                    HStack {
                        Text("Price Paid (€)")
                        Spacer()
                        TextField("0.00", text: $pricePaid)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .price)
                    }
                } header: {
                    Text("Purchase")
                }

                // Spool Image
                Section {
                    if let img = fetchedImagePreview {
                        HStack {
                            Spacer()
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 120)
                                .cornerRadius(10)
                            Spacer()
                        }
                        Button("Fetch Different Image") {
                            fetchedImagePreview = nil
                            imageURL = ""
                            fetchSpoolImage()
                        }
                        .foregroundColor(.orange)
                    } else {
                        Button(action: fetchSpoolImage) {
                            HStack {
                                Image(systemName: "photo.badge.magnifyingglass")
                                    .foregroundColor(.orange)
                                VStack(alignment: .leading) {
                                    Text("Fetch Spool Image")
                                        .fontWeight(.semibold)
                                    Text(canFetchImage
                                         ? "Search online for \(brand) \(colorName) \(selectedType.rawValue)"
                                         : "Enter brand and color name first")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if isFetchingImage { ProgressView() }
                            }
                        }
                        .disabled(!canFetchImage || isFetchingImage)
                    }

                    HStack {
                        Text("Image URL")
                        Spacer()
                        TextField("Auto-filled or paste URL", text: $imageURL)
                            .multilineTextAlignment(.trailing)
                            .font(.caption)
                            .focused($focusedField, equals: .imageURL)
                    }
                    TextField("Notes...", text: $notes, axis: .vertical)
                        .lineLimit(3)
                        .focused($focusedField, equals: .notes)
                } header: {
                    Text("Image & Notes")
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Add Filament")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    // Keyboard dismiss button — always visible when keyboard is up
                    if focusedField != nil {
                        Button(action: { focusedField = nil }) {
                            Image(systemName: "keyboard.chevron.compact.down")
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { saveFilament() }
                        .fontWeight(.semibold)
                        .disabled(brand.isEmpty || colorName.isEmpty)
                }
            }
            .simultaneousGesture(TapGesture().onEnded { focusedField = nil })
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .scanner:
                    BarcodeScannerView { scannedCode in
                        barcode = scannedCode
                        activeSheet = nil
                        // Check for existing match first, then fall back to online lookup
                        if let match = findExistingFilament(barcode: scannedCode, sku: nil) {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                activeSheet = .restock(match)
                            }
                        } else {
                            lookupBarcode(scannedCode)
                        }
                    }
                case .restock(let candidate):
                    RestockView(matchedFilament: candidate)
                        .environmentObject(store)
                }
            }
            .alert("Filament Added! 🎉", isPresented: $showSuccess) {
                Button("Add Another") { resetForm() }
                Button("Done") { resetForm() }
            } message: {
                Text("\(savedBrand) \(savedType) in \(savedColor) has been added to your inventory.")
            }
        }
    }

    // MARK: - Existing Filament Detection
    // Returns the matched Filament if found, nil otherwise.
    func findExistingFilament(barcode: String?, sku: String?) -> Filament? {
        store.filaments.first { f in
            if let b = barcode, !b.isEmpty, !f.barcode.isEmpty {
                return f.barcode == b
            }
            if let s = sku, !s.isEmpty, !f.sku.isEmpty {
                return f.sku.lowercased() == s.lowercased()
            }
            return false
        }
    }

    // MARK: - Barcode Lookup
    func lookupBarcode(_ code: String) {
        isLookingUp = true
        Task {
            let result = await FilamentLookupService.shared.lookupByBarcode(code)
            await MainActor.run {
                isLookingUp = false
                if let r = result {
                    lookupResult = r
                    if brand.isEmpty { brand = r.brand }
                    if imageURL.isEmpty { imageURL = r.imageURL ?? "" }
                    // Auto-fetch preview if we got a URL
                    if let urlStr = r.imageURL, let url = URL(string: urlStr) {
                        Task {
                            if let (data, _) = try? await URLSession.shared.data(from: url),
                               let img = UIImage(data: data) {
                                await MainActor.run { fetchedImagePreview = img }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Fetch Spool Image
    func fetchSpoolImage() {
        guard canFetchImage else { return }
        focusedField = nil
        isFetchingImage = true
        Task {
            let result = await FilamentLookupService.shared.searchFilamentImage(
                brand: brand,
                color: colorName,
                type: selectedType.rawValue
            )
            await MainActor.run {
                isFetchingImage = false
                if let urlStr = result {
                    imageURL = urlStr
                    // Load preview
                    if let url = URL(string: urlStr) {
                        Task {
                            if let (data, _) = try? await URLSession.shared.data(from: url),
                               let img = UIImage(data: data) {
                                await MainActor.run { fetchedImagePreview = img }
                            }
                        }
                    }
                } else {
                    errorMessage = "No image found. Try a different brand or color name."
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        errorMessage = nil
                    }
                }
            }
        }
    }

    // MARK: - Save
    func saveFilament() {
        // Dismiss keyboard first
        focusedField = nil

        let price = Double(pricePaid.replacingOccurrences(of: ",", with: ".")) ?? 0
        let color = FilamentColor(name: colorName, hexCode: colorHex)
        let status = StockStatus.from(remaining: remainingWeight, total: totalWeight)

        // Snapshot values for the alert message before resetting
        savedBrand = brand
        savedType = selectedType.rawValue
        savedColor = colorName

        var filament = Filament(
            brand: brand,
            sku: sku,
            barcode: barcode,
            type: selectedType,
            color: color,
            totalWeightG: totalWeight,
            remainingWeightG: remainingWeight,
            pricePaid: price,
            purchaseDate: Date(),
            imageURL: imageURL.isEmpty ? nil : imageURL,
            stockStatus: status
        )

        Task {
            // Fetch brand logo
            let logoURL = await FilamentLookupService.shared.fetchBrandLogo(brand: brand)
            // If no image yet, try one more search
            var finalImageURL = imageURL.isEmpty ? nil : imageURL
            if finalImageURL == nil {
                finalImageURL = await FilamentLookupService.shared.searchFilamentImage(
                    brand: brand, color: colorName, type: selectedType.rawValue
                )
            }
            await MainActor.run {
                filament.brandLogoURL = logoURL
                if let imgURL = finalImageURL { filament.imageURL = imgURL }
                store.addFilament(filament)
                showSuccess = true
            }
        }
    }

    // MARK: - Reset
    func resetForm() {
        brand = ""; sku = ""; barcode = ""; colorName = ""; imageURL = ""
        totalWeight = 1000; remainingWeight = 1000; pricePaid = ""; notes = ""
        selectedType = .pla; colorHex = "#FF6600"
        lookupResult = nil; fetchedImagePreview = nil
        errorMessage = nil; focusedField = nil
    }
}

// MARK: - Color Swatch Picker
// Shows preset swatches + a custom colour button that opens the full iOS colour wheel
struct ColorSwatchPicker: View {
    @Binding var hexCode: String
    @State private var showColorWheel = false
    @State private var pickedColor: Color = .orange

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Row 1: preset swatches + custom wheel button
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(FilamentColor.commonColors, id: \.hexCode) { c in
                        Circle()
                            .fill(c.color)
                            .frame(width: 32, height: 32)
                            .shadow(color: c.color.opacity(0.4), radius: 3)
                            .overlay(
                                Circle()
                                    .stroke(hexCode == c.hexCode ? Color.orange : Color.clear, lineWidth: 2.5)
                            )
                            .onTapGesture {
                                hexCode = c.hexCode
                                pickedColor = c.color
                            }
                    }

                    // Custom colour wheel button
                    Button(action: { showColorWheel = true }) {
                        ZStack {
                            Circle()
                                .fill(
                                    AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                                                    center: .center)
                                )
                                .frame(width: 32, height: 32)
                                .shadow(radius: 2)
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            // Current colour preview strip
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: hexCode) ?? .orange)
                    .frame(height: 36)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )

                Text(hexCode.uppercased())
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 72)
            }
        }
        .sheet(isPresented: $showColorWheel) {
            ColorWheelPickerSheet(hexCode: $hexCode, pickedColor: $pickedColor)
        }
        .onAppear {
            pickedColor = Color(hex: hexCode) ?? .orange
        }
    }
}

// MARK: - Full Color Wheel Sheet
struct ColorWheelPickerSheet: View {
    @Binding var hexCode: String
    @Binding var pickedColor: Color
    @Environment(\.dismiss) var dismiss

    // UIColorPickerViewController wrapper
    var body: some View {
        NavigationView {
            ColorPickerWrapperView(hexCode: $hexCode, pickedColor: $pickedColor)
                .navigationTitle("Choose Colour")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { dismiss() }
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                    }
                }
        }
    }
}

// UIViewControllerRepresentable wrapping UIColorPickerViewController
struct ColorPickerWrapperView: UIViewControllerRepresentable {
    @Binding var hexCode: String
    @Binding var pickedColor: Color

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIColorPickerViewController {
        let picker = UIColorPickerViewController()
        picker.supportsAlpha = false
        picker.selectedColor = UIColor(Color(hex: hexCode) ?? .orange)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIColorPickerViewController, context: Context) {}

    class Coordinator: NSObject, UIColorPickerViewControllerDelegate {
        var parent: ColorPickerWrapperView
        init(_ parent: ColorPickerWrapperView) { self.parent = parent }

        func colorPickerViewControllerDidSelectColor(_ viewController: UIColorPickerViewController) {
            let uiColor = viewController.selectedColor
            parent.pickedColor = Color(uiColor)
            // Convert to hex
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
            parent.hexCode = String(format: "#%02X%02X%02X", Int(r*255), Int(g*255), Int(b*255))
        }

        func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
            let uiColor = viewController.selectedColor
            parent.pickedColor = Color(uiColor)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
            parent.hexCode = String(format: "#%02X%02X%02X", Int(r*255), Int(g*255), Int(b*255))
        }
    }
}
