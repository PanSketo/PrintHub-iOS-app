import SwiftUI
import AVKit
import Photos

// MARK: - Timelapse Card
// Shows timelapse .mp4 files stored on the Bambu printer's SD card.
// Tap a row to play full-screen; long-press or use the cloud button to save to Photos.

struct TimelapseCard: View {
    @EnvironmentObject var nasService: NASService
    var printerConfig: PrinterConfig?

    @State private var timelapses: [TimelapseFile] = []
    @State private var isLoading = false
    @State private var error: String? = nil
    @State private var playerItem: TimelapseFile? = nil
    @State private var savingPath: String? = nil
    @State private var toast = ""

    private let pageSize = 10
    @State private var displayedCount = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label("Timelapses", systemImage: "video.fill")
                    .font(.headline)
                Spacer()
                if isLoading {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Button(action: load) {
                        Image(systemName: "arrow.clockwise")
                            .font(.subheadline)
                    }
                }
            }

            if let err = error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if timelapses.isEmpty && !isLoading {
                HStack(spacing: 8) {
                    Image(systemName: "video.slash").foregroundColor(.secondary)
                    Text("No timelapse recordings found")
                        .font(.caption).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(timelapses.prefix(displayedCount)) { file in
                    TimelapseRow(
                        file: file,
                        isSaving: savingPath == file.path,
                        onPlay: { playerItem = file },
                        onSave: { Task { await saveToPhotos(file) } },
                        onDelete: { Task { await deleteTimelapse(file) } }
                    )
                }
                if timelapses.count > displayedCount {
                    Button {
                        displayedCount += pageSize
                    } label: {
                        Text("Load More (\(timelapses.count - displayedCount) remaining)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                }
            }

            // Toast
            if !toast.isEmpty {
                Text(toast)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .glassInnerCard(cornerRadius: 10)
                    .transition(.opacity)
            }
        }
        .padding()
        .glassCard()
        .animation(.easeInOut(duration: 0.2), value: toast)
        .onAppear(perform: load)
        .fullScreenCover(item: $playerItem) { file in
            TimelapsePlayerSheet(
                file: file,
                streamURL: nasService.timelapseStreamURL(path: file.path, using: printerConfig),
                onSave: { Task { await saveToPhotos(file) } }
            )
        }
    }

    // MARK: - Load

    func load() {
        isLoading = true
        error = nil
        displayedCount = pageSize
        Task {
            do {
                let result = try await nasService.fetchTimelapses(using: printerConfig)
                await MainActor.run {
                    timelapses = result
                    isLoading  = false
                }
            } catch {
                await MainActor.run {
                    self.error   = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    // MARK: - Save to Photos

    @MainActor
    func saveToPhotos(_ file: TimelapseFile) async {
        savingPath = file.path
        do {
            // 1. Download to temp dir via NAS backend proxy
            let localURL = try await nasService.downloadTimelapse(path: file.path, using: printerConfig)

            // 2. Request photo library access
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                throw NSError(domain: "Photos", code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "Photo library access denied"])
            }

            // 3. Save video asset
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: localURL)
            }

            await showToast("✅ Saved to Photos!")
        } catch {
            await showToast("❌ \(error.localizedDescription)")
        }
        savingPath = nil
    }

    // MARK: - Delete

    @MainActor
    func deleteTimelapse(_ file: TimelapseFile) async {
        do {
            try await nasService.deleteTimelapse(path: file.path, using: printerConfig)
            withAnimation { timelapses.removeAll { $0.id == file.id } }
            await showToast("🗑️ Deleted")
        } catch {
            await showToast("❌ \(error.localizedDescription)")
        }
    }

    @MainActor
    func showToast(_ message: String) async {
        withAnimation { toast = message }
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        withAnimation { toast = "" }
    }
}

// MARK: - Timelapse Row

struct TimelapseRow: View {
    let file: TimelapseFile
    let isSaving: Bool
    let onPlay: () -> Void
    let onSave: () -> Void
    let onDelete: () -> Void

    @State private var offset: CGFloat = 0
    private let deleteWidth: CGFloat = 76

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {

                // ── Main row content ──────────────────────────────────────
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(.tertiarySystemBackground))
                            .frame(width: 64, height: 40)
                        Image(systemName: "film.fill")
                            .foregroundColor(.orange)
                            .font(.title3)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(file.displayName)
                            .font(.caption).fontWeight(.semibold).foregroundColor(.primary)
                            .lineLimit(2)
                        if let size = file.displaySize {
                            Text(size).font(.caption2).foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Button(action: onSave) {
                        if isSaving {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.down.circle")
                                .font(.title3).foregroundColor(.blue)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(width: 32)

                    Button(action: onPlay) {
                        Image(systemName: "play.circle.fill")
                            .font(.title2).foregroundColor(.orange)
                    }
                    .buttonStyle(.plain)
                }
                .frame(width: geo.size.width)   // exactly fills the visible area
                .contentShape(Rectangle())
                .onTapGesture {
                    if offset != 0 {
                        withAnimation(.spring()) { offset = 0 }
                    } else {
                        onPlay()
                    }
                }

                // ── Delete button (off-screen to the right by default) ────
                Button {
                    withAnimation(.spring()) { offset = 0 }
                    onDelete()
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "trash.fill").font(.subheadline)
                        Text("Delete").font(.caption2)
                    }
                    .foregroundColor(.white)
                    .frame(width: deleteWidth)
                    .frame(maxHeight: .infinity)
                    .background(Color.red)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .offset(x: offset)
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        guard value.translation.width < 0 else {
                            if offset < 0 { withAnimation(.spring()) { offset = 0 } }
                            return
                        }
                        offset = max(value.translation.width, -deleteWidth)
                    }
                    .onEnded { value in
                        withAnimation(.spring()) {
                            offset = value.translation.width < -(deleteWidth / 2) ? -deleteWidth : 0
                        }
                    }
            )
        }
        .frame(height: 54)
        .clipped()
    }
}

// MARK: - Timelapse Player Sheet

struct TimelapsePlayerSheet: View {
    let file: TimelapseFile
    let streamURL: URL?
    let onSave: () -> Void
    @Environment(\.dismiss) var dismiss

    // Hold the player in state so it isn't recreated on every body evaluation
    @State private var player: AVPlayer?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            if let p = player {
                VideoPlayer(player: p)
                    .ignoresSafeArea()
            } else if streamURL != nil {
                ProgressView().tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle).foregroundColor(.orange)
                    Text("Could not build stream URL")
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Controls overlay
            VStack {
                HStack {
                    Button(action: {
                        player?.pause()
                        dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white.opacity(0.85))
                            .shadow(radius: 4)
                    }
                    .padding()

                    Spacer()

                    Button(action: onSave) {
                        Image(systemName: "arrow.down.to.line.circle.fill")
                            .font(.title)
                            .foregroundColor(.white.opacity(0.85))
                            .shadow(radius: 4)
                    }
                    .padding()
                }
                Spacer()
            }
        }
        .onAppear {
            if let url = streamURL {
                let p = AVPlayer(url: url)
                player = p
                p.play()
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}
