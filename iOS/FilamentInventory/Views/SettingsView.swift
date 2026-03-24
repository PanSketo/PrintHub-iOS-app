import SwiftUI
import UniformTypeIdentifiers

// MARK: - Settings View
struct SettingsView: View {
    @EnvironmentObject var nasService: NASService
    @EnvironmentObject var store: InventoryStore
    @StateObject private var printerManager = PrinterManager.shared
    @StateObject private var cloudBackup = CloudBackupService.shared
    @State private var nasURL: String = ""
    @State private var apiKey: String = ""
    @State private var connectionStatus: String = ""
    @State private var isTesting = false
    @State private var lowStockThreshold: Double = 200
    @State private var showResetAlert = false
    @State private var showCharts = false
    @State private var showShopping = false
    @State private var showAddPrinter = false
    @State private var exportFileURL: URL?
    @State private var showShareSheet = false
    @State private var showFileImporter = false
    @State private var isRestoring = false
    @State private var importError: String?
    @FocusState private var focusedField: SettingsField?
    @AppStorage("app_color_scheme") private var colorSchemePreference: String = "system"

    enum SettingsField { case nasURL, apiKey }

    var body: some View {
        NavigationView {
            Form {
                // Tools — formerly standalone tabs
                Section {
                    Button(action: { showCharts = true }) {
                        HStack {
                            Label("Statistics & Charts", systemImage: "chart.pie.fill")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button(action: { showShopping = true }) {
                        HStack {
                            Label("Shopping List", systemImage: "cart.fill")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Tools")
                }

                // Appearance
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("App Theme")
                            .font(.subheadline)
                        // Three tappable cards — reliable in any navigation context
                        HStack(spacing: 10) {
                            ThemeOptionButton(
                                label: "System",
                                icon: "circle.lefthalf.filled",
                                tag: "system",
                                selected: colorSchemePreference
                            ) { colorSchemePreference = "system" }

                            ThemeOptionButton(
                                label: "Light",
                                icon: "sun.max.fill",
                                tag: "light",
                                selected: colorSchemePreference
                            ) { colorSchemePreference = "light" }

                            ThemeOptionButton(
                                label: "Dark",
                                icon: "moon.fill",
                                tag: "dark",
                                selected: colorSchemePreference
                            ) { colorSchemePreference = "dark" }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Appearance")
                }

                // NAS Connection
                Section {
                    HStack {
                        Text("NAS URL")
                        Spacer()
                        TextField("http://REDACTED-PRINTER-IP0:3456", text: $nasURL)
                            .multilineTextAlignment(.trailing)
                            .autocapitalization(.none)
                            .keyboardType(.URL)
                            .focused($focusedField, equals: .nasURL)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .apiKey }
                    }
                    HStack {
                        Text("API Key")
                        Spacer()
                        SecureField("Your API key", text: $apiKey)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .apiKey)
                            .submitLabel(.done)
                            .onSubmit { focusedField = nil }
                    }
                    Button(action: testConnection) {
                        HStack {
                            if isTesting {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Image(systemName: "network")
                            }
                            Text("Test Connection")
                        }
                    }
                    if !connectionStatus.isEmpty {
                        Text(connectionStatus)
                            .font(.caption)
                            .foregroundColor(connectionStatus.contains("✅") ? .green : .red)
                    }
                    Button("Save & Connect") {
                        nasService.baseURL = nasURL
                        nasService.apiKey = apiKey
                        connectionStatus = ""
                        isTesting = true
                        Task {
                            await nasService.autoConnect()
                            await MainActor.run {
                                isTesting = false
                                connectionStatus = nasService.isConnected
                                    ? "✅ Connected and synced!"
                                    : "❌ Saved but could not connect. Check URL and key."
                            }
                        }
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)
                } header: {
                    Text("NAS Connection")
                } footer: {
                    Text("Local: http://REDACTED-PRINTER-IP0:3456\nRemote: http://REDACTED-DDNS:3456")
                        .font(.caption)
                }

                // Alerts
                Section {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Low Stock Threshold")
                            Spacer()
                            Text("\(Int(lowStockThreshold))g")
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)
                        }
                        Slider(value: $lowStockThreshold, in: 50...500, step: 25)
                            .accentColor(.orange)
                            .onChange(of: lowStockThreshold) { val in
                                store.lowStockThreshold = val
                                UserDefaults.standard.set(val, forKey: "low_stock_threshold")
                            }
                    }
                } header: {
                    Text("Alerts")
                } footer: {
                    Text("You'll be notified when a spool drops below this weight")
                }

                // Stats
                Section {
                    HStack {
                        Text("Total Spools")
                        Spacer()
                        Text("\(store.totalFilaments)").foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Total Spend")
                        Spacer()
                        Text(String(format: "€%.2f", store.totalSpend)).foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Print Jobs Logged")
                        Spacer()
                        Text("\(store.printJobs.count)").foregroundColor(.secondary)
                    }
                } header: {
                    Text("Statistics")
                }

                // About
                Section {
                    // Developer card
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(
                                    colors: [Color.orange, Color.orange.opacity(0.6)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 48, height: 48)
                            Text("PT")
                                .font(.system(.subheadline, design: .rounded))
                                .fontWeight(.black)
                                .foregroundColor(.white)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pantelis Tzelesis")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("Developer & Designer")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)

                    HStack {
                        Text("App Version")
                        Spacer()
                        Text("1.0.0").foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Build")
                        Spacer()
                        Text("1").foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Bundle ID")
                        Spacer()
                        Text("com.pansketo.filamentinventory")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("© 2025 Pantelis Tzelesis")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } header: {
                    Text("About Filament Inventory")
                }

                // Printers
                Section {
                    ForEach(printerManager.printers) { printer in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(printer.name)
                                    .font(.subheadline)
                                    .fontWeight(printer.id == printerManager.activePrinterId ? .semibold : .regular)
                                Text(printer.nasURL)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if printer.id == printerManager.activePrinterId {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.orange)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { printerManager.setActive(id: printer.id) }
                    }
                    .onDelete { indices in
                        indices.forEach { printerManager.removePrinter(id: printerManager.printers[$0].id) }
                    }
                    Button(action: { showAddPrinter = true }) {
                        Label("Add Printer", systemImage: "plus")
                    }
                    .foregroundColor(.orange)
                } header: {
                    Text("Printers")
                } footer: {
                    Text("Each printer can point to a different NAS backend. Tap a printer to set it as active.")
                }

                // Backup & Restore
                Section {
                    Button(action: triggerExport) {
                        Label("Export Inventory", systemImage: "square.and.arrow.up")
                    }
                    .foregroundColor(.blue)

                    Button(action: { showFileImporter = true }) {
                        HStack {
                            if isRestoring { ProgressView().scaleEffect(0.8) }
                            Label(isRestoring ? "Importing…" : "Import Backup",
                                  systemImage: "square.and.arrow.down")
                        }
                    }
                    .disabled(isRestoring)
                    .foregroundColor(.blue)

                    if let lastExport = cloudBackup.lastBackupDate {
                        HStack {
                            Text("Last Export")
                            Spacer()
                            Text(lastExport, style: .relative)
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                    if !cloudBackup.statusMessage.isEmpty {
                        Text(cloudBackup.statusMessage)
                            .font(.caption)
                            .foregroundColor(cloudBackup.statusMessage.contains("✅") ? .green : .orange)
                    }
                    if let err = importError {
                        Text(err).font(.caption).foregroundColor(.red)
                    }
                } header: {
                    Text("Backup & Restore")
                } footer: {
                    Text("Export your inventory as a JSON file to share or save anywhere. Import a previously exported file to restore your data.")
                }

                // Danger Zone
                Section {
                    Button("Force Sync from NAS") {
                        store.errorMessage = nil
                        store.syncFromNAS()
                    }
                    .foregroundColor(.blue)
                    if let err = store.errorMessage {
                        Text("❌ \(err)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    Button("Reset All Settings", role: .destructive) {
                        showResetAlert = true
                    }
                } header: {
                    Text("Data")
                }
            }
            .navigationTitle("Settings")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if focusedField != nil {
                        Button(action: { focusedField = nil }) {
                            Image(systemName: "keyboard.chevron.compact.down")
                        }
                    }
                }
            }
            .onAppear {
                nasURL = nasService.baseURL
                apiKey = nasService.apiKey
                lowStockThreshold = UserDefaults.standard.double(forKey: "low_stock_threshold").nonZero ?? 200
            }
            .alert("Reset All Settings?", isPresented: $showResetAlert) {
                Button("Reset", role: .destructive) {
                    UserDefaults.standard.removeObject(forKey: "nas_base_url")
                    UserDefaults.standard.removeObject(forKey: "nas_api_key")
                    nasService.baseURL = ""
                    nasURL = ""
                    apiKey = ""
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will clear your NAS URL, API key, and all connection settings. Your inventory data on the NAS will not be affected.")
            }
            .sheet(isPresented: $showCharts) {
                NavigationView {
                    ChartsView()
                        .environmentObject(store)
                        .navigationTitle("Statistics")
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button("Done") { showCharts = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $showShopping) {
                NavigationView {
                    ShoppingListView()
                        .environmentObject(store)
                        .navigationTitle("Shopping List")
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button("Done") { showShopping = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $showAddPrinter) {
                AddPrinterSheet(printerManager: printerManager)
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = exportFileURL {
                    ActivityViewController(activityItems: [url])
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    triggerImport(from: url)
                case .failure(let error):
                    importError = error.localizedDescription
                }
            }
        }
    }

    func testConnection() {
        isTesting = true
        connectionStatus = ""
        Task {
            let ok = await nasService.testConnection()
            await MainActor.run {
                isTesting = false
                connectionStatus = ok ? "✅ Connected successfully!" : "❌ Could not connect. Check URL and API key."
            }
        }
    }

    func triggerExport() {
        exportFileURL = cloudBackup.exportURL(filaments: store.filaments, jobs: store.printJobs)
        if exportFileURL != nil { showShareSheet = true }
    }

    func triggerImport(from url: URL) {
        isRestoring = true
        importError = nil
        Task {
            do {
                let (filaments, jobs) = try cloudBackup.restore(from: url)
                await MainActor.run {
                    store.filaments = filaments
                    store.printJobs = jobs
                    isRestoring = false
                }
            } catch {
                await MainActor.run {
                    importError = error.localizedDescription
                    isRestoring = false
                }
            }
        }
    }
}

// MARK: - Add Printer Sheet
struct AddPrinterSheet: View {
    @ObservedObject var printerManager: PrinterManager
    @Environment(\.dismiss) var dismiss

    @State private var name = ""
    @State private var nasURL = ""
    @State private var apiKey = ""
    @State private var notes = ""

    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack {
                        Text("Name")
                        Spacer()
                        TextField("e.g. Bambu P2S", text: $name)
                            .multilineTextAlignment(.trailing)
                    }
                } header: { Text("Printer") }

                Section {
                    HStack {
                        Text("NAS URL")
                        Spacer()
                        TextField("http://REDACTED-PRINTER-IP0:3456", text: $nasURL)
                            .multilineTextAlignment(.trailing)
                            .autocapitalization(.none)
                            .keyboardType(.URL)
                    }
                    HStack {
                        Text("API Key")
                        Spacer()
                        SecureField("API key", text: $apiKey)
                            .multilineTextAlignment(.trailing)
                    }
                } header: { Text("Connection") }

                Section {
                    TextField("Optional notes…", text: $notes, axis: .vertical)
                        .lineLimit(3)
                } header: { Text("Notes") }
            }
            .navigationTitle("Add Printer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        let config = PrinterConfig(name: name.isEmpty ? "Printer" : name, nasURL: nasURL, apiKey: apiKey, notes: notes)
                        printerManager.addPrinter(config)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(nasURL.isEmpty)
                }
            }
        }
    }
}

// MARK: - NAS Setup View (first launch)
struct NASSetupView: View {
    @EnvironmentObject var nasService: NASService
    @State private var nasURL = "http://REDACTED-PRINTER-IP0:3456"
    @State private var apiKey = ""
    @State private var isTesting = false
    @State private var statusMessage = ""
    @State private var isConnected = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "cylinder.split.1x2.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.orange)
                Text("Filament Inventory")
                    .font(.largeTitle)
                    .fontWeight(.black)
                Text("Connect to your Synology NAS to get started")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("NAS URL").font(.caption).foregroundColor(.secondary)
                    TextField("http://REDACTED-PRINTER-IP0:3456", text: $nasURL)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                    Text("Or use DDNS: http://REDACTED-DDNS:3456")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("API Key").font(.caption).foregroundColor(.secondary)
                    SecureField("Enter your API key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(.horizontal, 32)

            VStack(spacing: 12) {
                Button(action: testConnection) {
                    HStack {
                        if isTesting {
                            ProgressView().scaleEffect(0.8).tint(.white)
                        } else {
                            Image(systemName: "network")
                        }
                        Text(isTesting ? "Testing..." : "Test Connection")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(14)
                    .fontWeight(.semibold)
                }
                .disabled(isTesting)

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.subheadline)
                        .foregroundColor(isConnected ? .green : .red)
                        .multilineTextAlignment(.center)
                }

                if isConnected {
                    Button("Continue →") {
                        nasService.baseURL = nasURL
                        nasService.apiKey = apiKey
                        Task { await nasService.autoConnect() }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(14)
                    .fontWeight(.semibold)
                }
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }

    func testConnection() {
        isTesting = true
        nasService.baseURL = nasURL
        nasService.apiKey = apiKey
        Task {
            let ok = await nasService.testConnection()
            await MainActor.run {
                isTesting = false
                isConnected = ok
                statusMessage = ok
                    ? "✅ Connected to your NAS successfully!"
                    : "❌ Connection failed. Make sure the backend is running on your NAS."
            }
        }
    }
}

extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}

// MARK: - Activity View Controller (Share Sheet)
struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Theme Option Button
struct ThemeOptionButton: View {
    let label: String
    let icon: String
    let tag: String
    let selected: String
    let action: () -> Void

    var isSelected: Bool { selected == tag }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? .white : .primary)
                Text(label)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(isSelected ? .white : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? Color.orange : Color(.tertiarySystemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.orange : Color(.systemGray4), lineWidth: 1.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
