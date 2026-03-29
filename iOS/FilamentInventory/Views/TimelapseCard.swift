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
                ForEach(timelapses) { file in
                    TimelapseRow(
                        file: file,
                        isSaving: savingPath == file.path,
                        onPlay: { playerItem = file },
                        onSave: { Task { await saveToPhotos(file) } }
                    )
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

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail placeholder
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
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                if let size = file.displaySize {
                    Text(size)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Save button
            Button(action: onSave) {
                if isSaving {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Image(systemName: "arrow.down.circle")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
            }
            .buttonStyle(.plain)
            .frame(width: 32)

            // Play button
            Button(action: onPlay) {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onPlay)
    }
}

// MARK: - Timelapse Player Sheet

struct TimelapsePlayerSheet: View {
    let file: TimelapseFile
    let streamURL: URL?
    let onSave: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            if let url = streamURL {
                VideoPlayer(player: AVPlayer(url: url))
                    .ignoresSafeArea()
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
                    Button(action: { dismiss() }) {
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
    }
}
