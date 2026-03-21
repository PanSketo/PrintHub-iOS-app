import SwiftUI

// MARK: - Settings View
struct SettingsView: View {
    @EnvironmentObject var nasService: NASService
    @EnvironmentObject var store: InventoryStore
    @State private var nasURL: String = ""
    @State private var apiKey: String = ""
    @State private var connectionStatus: String = ""
    @State private var isTesting = false
    @State private var lowStockThreshold: Double = 200
    @State private var showResetAlert = false
    @State private var showCharts = false
    @State private var showShopping = false
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
                        TextField("http://192.168.1.200:3456", text: $nasURL)
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
                    Text("Local: http://192.168.1.200:3456\nRemote: http://pansketo.arcdns.tech:3456")
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

                // Danger Zone
                Section {
                    Button("Force Sync from NAS") {
                        store.syncFromNAS()
                    }
                    .foregroundColor(.blue)

                    Button("Reset All Settings", role: .destructive) {
                        showResetAlert = true
                    }
                } header: {
                    Text("Data")
                }
            }
            .navigationTitle("Settings")
            .simultaneousGesture(TapGesture().onEnded { focusedField = nil })
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
            .alert("Reset Settings?", isPresented: $showResetAlert) {
                Button("Reset", role: .destructive) {
                    UserDefaults.standard.removeObject(forKey: "nas_base_url")
                    UserDefaults.standard.removeObject(forKey: "nas_api_key")
                    nasService.baseURL = ""
                    nasURL = ""
                    apiKey = ""
                }
                Button("Cancel", role: .cancel) {}
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
}

// MARK: - NAS Setup View (first launch)
struct NASSetupView: View {
    @EnvironmentObject var nasService: NASService
    @State private var nasURL = "http://192.168.1.200:3456"
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
                    TextField("http://192.168.1.200:3456", text: $nasURL)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                    Text("Or use DDNS: http://pansketo.arcdns.tech:3456")
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
