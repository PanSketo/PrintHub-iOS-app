import SwiftUI

// MARK: - Print Files View
// Browses the Bambu printer's internal (/sdcard) and USB (/usb) storage
// via the NAS backend's FTPS proxy, and can start a print with one tap.

struct PrintFilesView: View {
    @EnvironmentObject var nasService: NASService
    let printerConfig: PrinterConfig?

    @State private var files: [PrinterFile] = []
    @State private var navStack: [(name: String, path: String)] = [("Print Files", "/")]
    @State private var isLoading = false
    @State private var error: String? = nil
    @State private var confirmFile: PrinterFile? = nil
    @State private var printingPath: String? = nil
    @State private var toast = ""

    var currentPath: String { navStack.last?.path ?? "/" }
    var currentTitle: String { navStack.last?.name ?? "Print Files" }
    var isAtRoot: Bool { navStack.count == 1 }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && files.isEmpty {
                    loadingView
                } else if let err = error {
                    errorView(err)
                } else if files.isEmpty && !isLoading {
                    emptyView
                } else {
                    fileList
                }
            }
            .navigationTitle(currentTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !isAtRoot {
                        Button(action: goBack) {
                            HStack(spacing: 3) {
                                Image(systemName: "chevron.left")
                                Text(navStack.dropLast().last?.name ?? "Back")
                                    .lineLimit(1)
                            }
                            .foregroundColor(.orange)
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isLoading {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Button(action: load) {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .onAppear(perform: load)
            .confirmationDialog(
                "Start Print?",
                isPresented: Binding(
                    get: { confirmFile != nil },
                    set: { if !$0 { confirmFile = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let file = confirmFile {
                    Button("Print \"\(file.name)\"") {
                        Task { await sendPrint(file) }
                    }
                    Button("Cancel", role: .cancel) { confirmFile = nil }
                }
            } message: {
                if let file = confirmFile {
                    Text(file.displaySize.map { "\(file.name)  ·  \($0)" } ?? file.name)
                }
            }
            .overlay(alignment: .bottom) {
                if !toast.isEmpty {
                    Text(toast)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.bottom, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3), value: toast)
        }
    }

    // MARK: - Sub-views

    var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading files…").font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func errorView(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle).foregroundColor(.orange)
            Text(message)
                .font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Retry", action: load).foregroundColor(.orange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder").font(.largeTitle).foregroundColor(.secondary)
            Text("No files found").foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var fileList: some View {
        List {
            ForEach(files) { file in
                PrintFileRow(
                    file: file,
                    isPrintingThis: printingPath == file.path
                ) {
                    if file.isDirectory {
                        navStack.append((file.friendlyName, file.path))
                        load()
                    } else if file.isPrintable {
                        confirmFile = file
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { load() }
    }

    // MARK: - Actions

    func goBack() {
        guard navStack.count > 1 else { return }
        navStack.removeLast()
        load()
    }

    func load() {
        isLoading = true
        error = nil
        Task {
            do {
                let result = try await nasService.fetchPrinterFiles(
                    path: currentPath, using: printerConfig)
                await MainActor.run {
                    files = result
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    func sendPrint(_ file: PrinterFile) async {
        printingPath = file.path
        confirmFile = nil
        do {
            try await nasService.startPrint(filePath: file.path, using: printerConfig)
            await showToast("✅ Print started!")
        } catch {
            await showToast("❌ \(error.localizedDescription)")
        }
        printingPath = nil
    }

    @MainActor
    func showToast(_ message: String) async {
        withAnimation { toast = message }
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        withAnimation { toast = "" }
    }
}

// MARK: - File Row

struct PrintFileRow: View {
    let file: PrinterFile
    let isPrintingThis: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: file.isDirectory ? "folder.fill" : fileIcon)
                    .font(.title3)
                    .foregroundColor(file.isDirectory ? .orange : .blue)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(file.friendlyName)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    if let size = file.displaySize {
                        Text(size)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if file.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.caption).foregroundColor(.secondary)
                } else if file.isPrintable {
                    if isPrintingThis {
                        ProgressView().scaleEffect(0.85)
                    } else {
                        Image(systemName: "play.circle.fill")
                            .font(.title2).foregroundColor(.orange)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    var fileIcon: String {
        let n = file.name.lowercased()
        if n.hasSuffix(".3mf") || n.hasSuffix(".gcode.3mf") { return "cube.fill" }
        if n.hasSuffix(".gcode")                             { return "doc.text.fill" }
        return "doc.fill"
    }
}
