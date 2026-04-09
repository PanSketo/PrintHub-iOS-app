import SwiftUI

// MARK: - Print Files View

struct PrintFilesView: View {
    @EnvironmentObject var nasService: NASService
    let printerConfig: PrinterConfig?

    @State private var files: [PrinterFile] = []
    @State private var navStack: [(name: String, path: String)] = [("Print Files", "/")]
    @State private var isLoading    = false
    @State private var error: String?
    @State private var confirmFile: PrinterFile?
    @State private var printingPath: String?
    @State private var toast = ""

    // Selection mode
    @State private var isSelecting  = false
    @State private var selected     = Set<String>()   // file paths
    @State private var showDeleteConfirm = false
    @State private var isDeleting   = false

    var currentPath:  String { navStack.last?.path ?? "/" }
    var currentTitle: String { navStack.last?.name ?? "Print Files" }
    var isAtRoot:     Bool   { navStack.count == 1 }

    var visibleFiles: [PrinterFile] {
        files.filter { $0.isDirectory || $0.name.lowercased().contains(".3mf") }
    }

    // Only non-folder files can be selected
    var selectableFiles: [PrinterFile] { visibleFiles.filter { !$0.isDirectory } }

    let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && files.isEmpty {
                    loadingView
                } else if let err = error {
                    errorView(err)
                } else if visibleFiles.isEmpty && !isLoading {
                    emptyView
                } else {
                    tileGrid
                }
            }
            .navigationTitle(isSelecting ? "\(selected.count) selected" : currentTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .onAppear(perform: load)
            // Print confirmation
            .confirmationDialog(
                "Start Print?",
                isPresented: Binding(get: { confirmFile != nil }, set: { if !$0 { confirmFile = nil } }),
                titleVisibility: .visible
            ) {
                if let file = confirmFile {
                    Button("Print \"\(file.friendlyName)\"") { Task { await sendPrint(file) } }
                    Button("Cancel", role: .cancel) { confirmFile = nil }
                }
            } message: {
                if let file = confirmFile {
                    Text(file.displaySize.map { "\(file.friendlyName)  ·  \($0)" } ?? file.friendlyName)
                }
            }
            // Delete confirmation
            .confirmationDialog(
                "Delete \(selected.count) file\(selected.count == 1 ? "" : "s")?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { Task { await deleteSelected() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently remove the selected files from the printer's SD card.")
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

    // MARK: - Toolbar

    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        // Leading
        ToolbarItem(placement: .navigationBarLeading) {
            if isSelecting {
                Button("Cancel") { exitSelection() }
                    .foregroundColor(.orange)
            } else if !isAtRoot {
                Button(action: goBack) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                        Text(navStack.dropLast().last?.name ?? "Back").lineLimit(1)
                    }
                    .foregroundColor(.orange)
                }
            }
        }

        // Trailing
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            if isSelecting {
                // Select all toggle
                Button(selected.count == selectableFiles.count ? "None" : "All") {
                    if selected.count == selectableFiles.count {
                        selected.removeAll()
                    } else {
                        selected = Set(selectableFiles.map(\.path))
                    }
                }
                .foregroundColor(.orange)

                // Delete button
                Button {
                    if !selected.isEmpty { showDeleteConfirm = true }
                } label: {
                    if isDeleting {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Image(systemName: "trash")
                            .foregroundColor(selected.isEmpty ? .secondary : .red)
                    }
                }
                .disabled(selected.isEmpty || isDeleting)
            } else {
                if isLoading {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Button(action: load) { Image(systemName: "arrow.clockwise") }
                }
            }
        }
    }

    // MARK: - Tile grid

    var tileGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(visibleFiles) { file in
                    PrintFileTile(
                        file: file,
                        thumbnailURL: file.isDirectory ? nil : nasService.thumbnailURL(forFile: file.path, using: printerConfig),
                        isPrinting: printingPath == file.path,
                        isSelecting: isSelecting,
                        isSelected: selected.contains(file.path)
                    ) {
                        handleTap(file)
                    } onLongPress: {
                        handleLongPress(file)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .refreshable { load() }
    }

    // MARK: - Tap / long-press handling

    func handleTap(_ file: PrinterFile) {
        if isSelecting {
            if file.isDirectory { return }     // folders not selectable
            if selected.contains(file.path) {
                selected.remove(file.path)
            } else {
                selected.insert(file.path)
            }
        } else {
            if file.isDirectory {
                navStack.append((file.friendlyName, file.path))
                load()
            } else {
                confirmFile = file
            }
        }
    }

    func handleLongPress(_ file: PrinterFile) {
        if file.isDirectory { return }
        if !isSelecting {
            isSelecting = true
            selected = [file.path]
        }
    }

    func exitSelection() {
        isSelecting = false
        selected.removeAll()
    }

    // MARK: - Delete

    func deleteSelected() async {
        guard !selected.isEmpty else { return }
        isDeleting = true
        var failed = 0
        for path in selected {
            do {
                try await nasService.deletePrinterFile(path: path, using: printerConfig)
            } catch {
                failed += 1
            }
        }
        await MainActor.run {
            let removed = selected.count - failed
            files.removeAll { selected.contains($0.path) }
            exitSelection()
            isDeleting = false
        }
        if failed == 0 {
            await showToast("🗑️ Deleted \(selected.count > 1 ? "\(selected.count) files" : "file")")
        } else {
            await showToast("⚠️ \(failed) file\(failed == 1 ? "" : "s") failed to delete")
        }
    }

    // MARK: - State views

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
                .multilineTextAlignment(.center).padding(.horizontal)
            Button("Retry", action: load).foregroundColor(.orange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder").font(.largeTitle).foregroundColor(.secondary)
            Text("No .3mf files found").foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    func goBack() {
        guard navStack.count > 1 else { return }
        navStack.removeLast()
        exitSelection()
        load()
    }

    func load() {
        isLoading = true
        error = nil
        Task {
            do {
                let result = try await nasService.fetchPrinterFiles(path: currentPath, using: printerConfig)
                await MainActor.run { files = result; isLoading = false }
            } catch {
                await MainActor.run { self.error = error.localizedDescription; isLoading = false }
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

    @MainActor func showToast(_ message: String) async {
        withAnimation { toast = message }
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        withAnimation { toast = "" }
    }
}

// MARK: - Tile

struct PrintFileTile: View {
    let file: PrinterFile
    let thumbnailURL: URL?
    let isPrinting: Bool
    let isSelecting: Bool
    let isSelected: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                // Thumbnail area
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        Color(.systemGray6)

                        if file.isDirectory {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 44))
                                .foregroundColor(.orange)
                        } else if let url = thumbnailURL {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image): image.resizable().scaledToFill()
                                case .failure:            fallbackIcon
                                default:                  ProgressView()
                                }
                            }
                            .clipped()
                        } else {
                            fallbackIcon
                        }

                        if isPrinting {
                            Color.black.opacity(0.45)
                            ProgressView().tint(.white).scaleEffect(1.3)
                        }

                        // Selection dimming
                        if isSelecting && !file.isDirectory {
                            Color.black.opacity(isSelected ? 0.35 : 0.0)
                        }
                    }
                    .frame(height: 130)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    // Checkmark badge
                    if isSelecting && !file.isDirectory {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundColor(isSelected ? .white : .white.opacity(0.7))
                            .shadow(radius: 2)
                            .padding(8)
                    }
                }

                // Metadata strip
                VStack(alignment: .leading, spacing: 3) {
                    Text(file.friendlyName)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if let size = file.displaySize {
                        Text(size).font(.caption2).foregroundColor(.secondary)
                    } else if file.isDirectory {
                        Text("Folder").font(.caption2).foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isSelected ? Color.red : Color.clear, lineWidth: 2)
                    )
            )
            .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in onLongPress() }
        )
    }

    var fallbackIcon: some View {
        Image(systemName: "cube.fill")
            .font(.system(size: 40))
            .foregroundColor(.secondary.opacity(0.5))
    }
}
