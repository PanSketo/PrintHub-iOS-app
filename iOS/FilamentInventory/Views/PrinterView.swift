import SwiftUI

// MARK: - Printer Tab View
struct PrinterView: View {
    @EnvironmentObject var nasService: NASService
    @StateObject private var printerManager = PrinterManager.shared
    @State private var selectedSection = 0

    var body: some View {
        VStack(spacing: 0) {
            // ── Printer selector (only shown when more than one printer is configured) ──
            if printerManager.printers.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(printerManager.printers) { printer in
                            let isActive = printer.id == printerManager.activePrinterId
                            Button {
                                printerManager.setActive(id: printer.id)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "printer.fill")
                                        .font(.caption)
                                    Text(printer.name)
                                        .font(.caption)
                                        .fontWeight(isActive ? .semibold : .regular)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(isActive ? Color.orange : Color(.tertiarySystemBackground))
                                .foregroundColor(isActive ? .white : .primary)
                                .cornerRadius(20)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 6)
                .background(Color(.systemBackground))
                Divider()
            }

            // Segmented control at the top — cleaner than nested TabView
            Picker("Section", selection: $selectedSection) {
                Text("Live Status").tag(0)
                Text("Print Log").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .background(Color(.systemBackground))

            Divider()

            // Content
            if selectedSection == 0 {
                PrinterStatusView(printerConfig: printerManager.activePrinter)
            } else {
                PrintLogView()
            }
        }
    }
}

// MARK: - Printer Status View (formerly PrinterView body)
struct PrinterStatusView: View {
    @EnvironmentObject var store: InventoryStore
    @EnvironmentObject var nasService: NASService

    /// When non-nil, all API calls use this printer's credentials instead of the global NAS.
    let printerConfig: PrinterConfig?

    @State private var printerState: PrinterState? = nil
    @State private var amsMappings: [String: String] = [:]
    @State private var isLoading = true
    @State private var error: String? = nil
    @State private var pollingTimer: Timer? = nil

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {

                    if isLoading && printerState == nil {
                        ProgressView("Connecting to printer...")
                            .padding(.top, 40)
                    } else {
                        // ── Connection banner (always shown once loaded) ──
                        connectionBanner

                        // ── Auth / fetch error banner ─────────────────────
                        if let msg = error {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text(msg)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(12)
                        }

                        // ── Live printer state (if bridge is running) ─────
                        if let state = printerState?.live {
                            if state.isPrinting || state.isPaused {
                                PrintProgressCard(state: state, onCommand: sendCommand)
                                TemperatureCard(state: state, onCommand: sendCommand)
                            } else {
                                idleCard(state: state)
                            }
                            AMSStatusCard(
                                state: state,
                                mappings: amsMappings,
                                filaments: store.filaments
                            )
                        } else {
                            // Bridge not running or printer not connected yet
                            bridgeSetupCard
                        }

                        // ── AMS Mapping (always shown so user can configure) ──
                        AMSMappingCard(
                            mappings: $amsMappings,
                            filaments: store.filaments,
                            printerConfig: printerConfig
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("Printer")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: refresh) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onAppear {
                refresh()
                startPolling()
            }
            .onDisappear {
                stopPolling()
            }
        }
    }

    // MARK: - Connection Banner
    var connectionBanner: some View {
        let connected = printerState?.connected ?? false
        let printerName = printerConfig?.name ?? "P2S"
        // Build timestamp label safely — avoids optional chaining type ambiguity
        let tsLabel: String = {
            guard let ts = printerState?.live?.timestamp else { return "" }
            return formatTimestamp(ts) ?? ""
        }()
        return HStack(spacing: 10) {
            Circle()
                .fill(connected ? Color.green : Color.red)
                .frame(width: 10, height: 10)
                .shadow(color: connected ? .green : .red, radius: 4)

            Text(connected ? "\(printerName) Connected" : "\(printerName) Offline")
                .font(.subheadline).fontWeight(.semibold)

            Spacer()

            if isLoading {
                ProgressView().scaleEffect(0.7)
            } else {
                Text(tsLabel)
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(12)
        .glassTintCard(cornerRadius: 12, fallback: connected ? Color.green.opacity(0.1) : Color.red.opacity(0.08))
    }

    // MARK: - Idle Card
    func idleCard(state: PrinterLiveState) -> some View {
        HStack(spacing: 16) {
            Image(systemName: state.statusIcon)
                .font(.system(size: 36))
                .foregroundColor(state.statusColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(state.printStatus == "FINISH" ? "Last print finished" :
                     state.printStatus == "FAILED" ? "Last print failed" : "Ready to print")
                    .font(.headline)
                if !state.printName.isEmpty && state.printStatus != "IDLE" {
                    Text(state.printName)
                        .font(.subheadline).foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding()
        .glassCard()
    }

    // MARK: - Bridge Setup Card
    // Shown when the mqtt-bridge hasn't connected to the printer yet
    var bridgeSetupCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.title2)
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Printer bridge not connected")
                        .font(.headline)
                    Text("The mqtt-bridge container is running but hasn't received data from the printer yet.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            Text("Setup checklist:")
                .font(.subheadline).fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 10) {
                setupStep(n: "1", text: "Open Synology Container Manager — check both filament-backend and mqtt-bridge containers are green")
                setupStep(n: "2", text: "In docker-compose.yml confirm PRINTER_IP, PRINTER_SERIAL and PRINTER_ACCESS_CODE are set correctly")
                setupStep(n: "3", text: "Find Access Code on P2S touchscreen: Settings → Network → Access Code (8 characters)")
                setupStep(n: "4", text: "Make sure your P2S is on the same WiFi/LAN as your Synology NAS")
            }

            Button(action: refresh) {
                Label("Retry Connection", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(Color.orange.opacity(0.15))
                    .foregroundColor(.orange)
                    .cornerRadius(10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding()
        .glassCard()
    }

    func setupStep(n: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(n)
                .font(.caption).fontWeight(.black)
                .frame(width: 20, height: 20)
                .background(Color.orange)
                .foregroundColor(.white)
                .clipShape(Circle())
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Polling
    func startPolling() {
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { await fetchState() }
        }
    }

    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    func refresh() {
        Task {
            await fetchState()
            await fetchMappings()
        }
    }

    func fetchState() async {
        do {
            let state = try await nasService.fetchPrinterState(using: printerConfig)
            await MainActor.run {
                self.error = nil
                self.printerState = state
                self.isLoading = false
                self.error = nil
            }
        } catch {
            await MainActor.run {
                // Keep any previously loaded state — just mark as disconnected
                if self.printerState == nil {
                    // First load failed — show empty state with setup instructions
                    self.printerState = PrinterState(connected: false, live: nil)
                }
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
        // Check for new print events on every poll tick (NASService rate-limits to 20 s)
        await nasService.checkPrintEvents(using: printerConfig)
    }

    func fetchMappings() async {
        do {
            let mappings = try await nasService.fetchAMSMappings(using: printerConfig)
            await MainActor.run { self.amsMappings = mappings }
        } catch { }
    }

    func sendCommand(_ command: String, value: String?) async throws {
        try await nasService.sendPrinterCommand(command, value: value, using: printerConfig)
    }

    func formatTimestamp(_ ts: String) -> String? {
        let f = ISO8601DateFormatter()
        guard let date = f.date(from: ts) else { return nil }
        let r = RelativeDateTimeFormatter()
        r.unitsStyle = .abbreviated
        return r.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Print Progress Card
struct PrintProgressCard: View {
    let state: PrinterLiveState
    let onCommand: (String, String?) async throws -> Void

    @State private var showStopConfirm = false
    @State private var showSpeedPicker = false
    @State private var isBusy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Title row
            HStack {
                Image(systemName: state.statusIcon)
                    .foregroundColor(state.statusColor)
                Text(state.isPaused ? "Print Paused" : "Printing")
                    .font(.headline)
                Spacer()
                Text("\(state.progress)%")
                    .font(.system(.title2, design: .rounded))
                    .fontWeight(.black)
                    .foregroundColor(state.statusColor)
            }

            // File name
            if !state.printName.isEmpty {
                Text(state.printName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6).fill(Color(.systemFill))
                    RoundedRectangle(cornerRadius: 6)
                        .fill(LinearGradient(
                            colors: [state.statusColor.opacity(0.7), state.statusColor],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(state.progress) / 100)
                    if state.isPrinting {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 60)
                            .offset(x: geo.size.width * CGFloat(state.progress) / 100 - 30)
                            .animation(.easeInOut(duration: 1).repeatForever(), value: state.progress)
                    }
                }
            }
            .frame(height: 16)

            // Stats row — speed badge is tappable
            HStack {
                statBadge(icon: "clock", value: formatMinutes(state.remainingMinutes), label: "remaining")
                Spacer()
                statBadge(icon: "square.3.layers.3d", value: "\(state.layerCurrent)/\(state.layerTotal)", label: "layers")
                Spacer()
                Button { showSpeedPicker = true } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "speedometer").font(.caption).foregroundColor(.blue)
                        Text(state.speedLabel).font(.caption).fontWeight(.semibold).foregroundColor(.blue)
                        Text("speed").font(.caption2).foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.blue.opacity(0.08))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .confirmationDialog("Print Speed", isPresented: $showSpeedPicker, titleVisibility: .visible) {
                    Button("Silent")      { Task { try? await onCommand("set_speed", "1") } }
                    Button("Standard")   { Task { try? await onCommand("set_speed", "2") } }
                    Button("Sport")      { Task { try? await onCommand("set_speed", "3") } }
                    Button("Ludicrous")  { Task { try? await onCommand("set_speed", "4") } }
                    Button("Cancel", role: .cancel) {}
                }
            }

            Divider()

            // Control buttons
            HStack(spacing: 10) {
                Button {
                    Task {
                        isBusy = true
                        try? await onCommand(state.isPaused ? "resume" : "pause", nil)
                        isBusy = false
                    }
                } label: {
                    Label(state.isPaused ? "Resume" : "Pause",
                          systemImage: state.isPaused ? "play.fill" : "pause.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(state.isPaused ? .green : .orange)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background((state.isPaused ? Color.green : Color.orange).opacity(0.12))
                        .cornerRadius(10)
                }

                Button { showStopConfirm = true } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.12))
                        .cornerRadius(10)
                }
                .confirmationDialog("Stop Print?", isPresented: $showStopConfirm, titleVisibility: .visible) {
                    Button("Stop Print", role: .destructive) {
                        Task {
                            isBusy = true
                            try? await onCommand("stop", nil)
                            isBusy = false
                        }
                    }
                } message: { Text("This will cancel the current print.") }
            }
            .disabled(isBusy)
            .overlay(isBusy ? AnyView(ProgressView().frame(maxWidth: .infinity)) : AnyView(EmptyView()))
        }
        .padding()
        .glassCard()
    }

    func statBadge(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.caption).foregroundColor(.secondary)
            Text(value).font(.caption).fontWeight(.semibold)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
    }

    func formatMinutes(_ mins: Int) -> String {
        if mins < 60 { return "\(mins)m" }
        return "\(mins / 60)h \(mins % 60)m"
    }
}

// MARK: - Temperature Card
struct TemperatureCard: View {
    let state: PrinterLiveState
    let onCommand: (String, String?) async throws -> Void

    @State private var editingNozzle = false
    @State private var editingBed = false
    @State private var tempInput = ""

    var body: some View {
        HStack(spacing: 0) {
            Button {
                tempInput = "\(Int(state.nozzleTemp))"
                editingNozzle = true
            } label: {
                tempTile(label: "Nozzle", value: state.nozzleTemp, icon: "flame.fill", color: .orange, tappable: true)
            }
            .buttonStyle(.plain)

            Divider().frame(height: 44)

            Button {
                tempInput = "\(Int(state.bedTemp))"
                editingBed = true
            } label: {
                tempTile(label: "Bed", value: state.bedTemp, icon: "square.fill", color: .blue, tappable: true)
            }
            .buttonStyle(.plain)

            if state.chamberTemp > 0 {
                Divider().frame(height: 44)
                tempTile(label: "Chamber", value: state.chamberTemp, icon: "house.fill", color: .purple, tappable: false)
            }
        }
        .padding()
        .glassCard()
        .alert("Set Nozzle Temperature", isPresented: $editingNozzle) {
            TextField("°C", text: $tempInput).keyboardType(.numberPad)
            Button("Set") { Task { try? await onCommand("set_nozzle_temp", tempInput) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Current: \(Int(state.nozzleTemp))°C") }
        .alert("Set Bed Temperature", isPresented: $editingBed) {
            TextField("°C", text: $tempInput).keyboardType(.numberPad)
            Button("Set") { Task { try? await onCommand("set_bed_temp", tempInput) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Current: \(Int(state.bedTemp))°C") }
    }

    func tempTile(label: String, value: Double, icon: String, color: Color, tappable: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundColor(color).font(.subheadline)
            Text(String(format: "%.0f°C", value))
                .font(.system(.subheadline, design: .rounded)).fontWeight(.bold)
            Text(label).font(.caption2).foregroundColor(.secondary)
            if tappable {
                Image(systemName: "pencil").font(.system(size: 9)).foregroundColor(.secondary.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - AMS Status Card
struct AMSStatusCard: View {
    let state: PrinterLiveState
    let mappings: [String: String]
    let filaments: [Filament]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("AMS 2 Pro Slots", systemImage: "tray.2.fill")
                .font(.headline)

            if let slots = state.amsSlots, !slots.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(Array(slots.keys.sorted()), id: \.self) { key in
                        if let slot = slots[key] {
                            AMSSlotTile(
                                slotKey: key,
                                slot: slot,
                                mappedFilament: filaments.first(where: { $0.id == mappings[key] }),
                                isActive: state.activeAMSSlotIndex == (slot.amsIndex * 4 + slot.slotIndex)
                            )
                        }
                    }
                }
            } else {
                Text("No AMS data — printer may be idle or disconnected")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .padding()
        .glassCard()
    }
}

struct AMSSlotTile: View {
    let slotKey: String
    let slot: AMSSlotState
    let mappedFilament: Filament?
    let isActive: Bool

    var slotColor: Color {
        if !slot.trayColor.isEmpty {
            // Bambu sends 8-char RRGGBBAA hex — strip alpha to get 6-char RRGGBB
            var hex = slot.trayColor
            if hex.count == 8 { hex = String(hex.prefix(6)) }
            return Color(hex: "#\(hex)") ?? mappedFilament?.color.color ?? .gray
        }
        return mappedFilament?.color.color ?? .gray
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("AMS\(slot.amsIndex + 1) • S\(slot.slotIndex + 1)")
                    .font(.caption2).fontWeight(.bold).foregroundColor(.secondary)
                Spacer()
                if isActive {
                    Circle().fill(Color.green).frame(width: 8, height: 8)
                        .shadow(color: .green, radius: 3)
                }
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(slotColor)
                    .frame(width: 22, height: 22)
                    .shadow(color: slotColor.opacity(0.5), radius: 3)

                VStack(alignment: .leading, spacing: 1) {
                    if let f = mappedFilament {
                        Text(f.brand).font(.caption).fontWeight(.semibold).lineLimit(1)
                        Text("\(f.type.rawValue) \(f.color.name)").font(.caption2).foregroundColor(.secondary).lineLimit(1)
                    } else if !slot.trayType.isEmpty {
                        Text(slot.trayType).font(.caption).fontWeight(.semibold)
                        Text("Not mapped").font(.caption2).foregroundColor(.orange)
                    } else {
                        Text("Empty").font(.caption).foregroundColor(.secondary)
                    }
                }
            }

            // Remaining % if available
            if slot.remain >= 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(Color(.systemFill))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(slotColor)
                            .frame(width: geo.size.width * CGFloat(slot.remain) / 100)
                    }
                }
                .frame(height: 4)
                Text("\(slot.remain)%").font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(10)
        .glassTintCard(cornerRadius: 12, fallback: isActive ? Color.blue.opacity(0.08) : Color(.tertiarySystemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isActive ? Color.blue : Color.clear, lineWidth: 1.5)
        )
    }
}

// MARK: - AMS Mapping Card
struct AMSMappingCard: View {
    @Binding var mappings: [String: String]
    let filaments: [Filament]
    var printerConfig: PrinterConfig?
    @EnvironmentObject var nasService: NASService
    @State private var savedMessage = ""

    // P2S with AMS 2 Pro has up to 2 AMS units × 4 slots = 8 slots
    let allSlots: [(amsIndex: Int, slotIndex: Int)] = [
        (0,0),(0,1),(0,2),(0,3),
        (1,0),(1,1),(1,2),(1,3)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("AMS Slot Mapping", systemImage: "arrow.left.arrow.right")
                    .font(.headline)
                Spacer()
                if !savedMessage.isEmpty {
                    Text(savedMessage)
                        .font(.caption).foregroundColor(.green)
                }
            }

            Text("Map each AMS slot to a filament in your inventory so prints are auto-deducted.")
                .font(.caption).foregroundColor(.secondary)

            ForEach(0..<2, id: \.self) { amsIdx in
                VStack(alignment: .leading, spacing: 8) {
                    Text("AMS Unit \(amsIdx + 1)")
                        .font(.caption).fontWeight(.bold).foregroundColor(.secondary)

                    ForEach(0..<4, id: \.self) { slotIdx in
                        let key = "ams_\(amsIdx)_slot_\(slotIdx)"
                        AMSMappingRow(
                            slotKey: key,
                            label: "Slot \(slotIdx + 1)",
                            filaments: filaments,
                            selectedFilamentId: Binding(
                                get: { mappings[key] ?? "" },
                                set: { newId in
                                    mappings[key] = newId.isEmpty ? nil : newId
                                    saveMapping(key: key, filamentId: newId)
                                }
                            )
                        )
                    }
                }
                if amsIdx == 0 { Divider() }
            }
        }
        .padding()
        .glassCard()
    }

    func saveMapping(key: String, filamentId: String) {
        Task {
            do {
                if filamentId.isEmpty {
                    try await nasService.deleteAMSMapping(slotKey: key, using: printerConfig)
                } else {
                    try await nasService.saveAMSMapping(slotKey: key, filamentId: filamentId, using: printerConfig)
                }
                await MainActor.run {
                    savedMessage = "✅ Saved"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { savedMessage = "" }
                }
            } catch {
                await MainActor.run { savedMessage = "❌ Save failed" }
            }
        }
    }
}

struct AMSMappingRow: View {
    let slotKey: String
    let label: String
    let filaments: [Filament]
    @Binding var selectedFilamentId: String

    var selectedFilament: Filament? {
        filaments.first { $0.id == selectedFilamentId }
    }

    var body: some View {
        HStack(spacing: 10) {
            // Slot label
            Text(label)
                .font(.subheadline)
                .frame(width: 50, alignment: .leading)

            // Color preview
            if let f = selectedFilament {
                Circle()
                    .fill(f.color.color)
                    .frame(width: 18, height: 18)
                    .shadow(color: f.color.color.opacity(0.4), radius: 2)
            } else {
                Circle()
                    .stroke(Color(.systemGray4), lineWidth: 1.5)
                    .frame(width: 18, height: 18)
            }

            // Picker
            Picker("", selection: $selectedFilamentId) {
                Text("— Not mapped —").tag("")
                ForEach(filaments) { f in
                    Text("\(f.brand) \(f.type.rawValue) \(f.color.name)")
                        .tag(f.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .padding(.vertical, 2)
    }
}
