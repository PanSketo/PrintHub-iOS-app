import SwiftUI
import Foundation

// MARK: - MJPEG Streamer

/// Connects to the NAS /api/camera/stream endpoint and decodes the MJPEG
/// multipart response into individual UIImage frames for display.
final class MJPEGStreamer: NSObject, ObservableObject, URLSessionDataDelegate {
    @Published var currentFrame: UIImage?
    @Published var isStreaming = false
    @Published var errorMessage: String?

    private var streamSession: URLSession?
    private var buffer = Data()
    private var pendingErrorRead = false  // true when we're reading a 503 JSON body

    deinit { stop() }

    // MARK: - Public API

    func start(baseURL: String, apiKey: String) {
        guard !baseURL.isEmpty else {
            DispatchQueue.main.async { self.errorMessage = "NAS not configured" }
            return
        }
        guard let url = URL(string: "\(baseURL)/api/camera/stream") else {
            DispatchQueue.main.async { self.errorMessage = "Invalid NAS URL" }
            return
        }

        // Cancel any existing stream first
        streamSession?.invalidateAndCancel()

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 3600  // allow up to 1-hour streams
        streamSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        DispatchQueue.main.async {
            self.isStreaming = true
            self.errorMessage = nil
            self.currentFrame = nil
        }
        buffer = Data()
        pendingErrorRead = false
        streamSession?.dataTask(with: request).resume()
    }

    func stop() {
        streamSession?.invalidateAndCancel()
        streamSession = nil
        buffer = Data()
        DispatchQueue.main.async {
            self.isStreaming = false
            self.currentFrame = nil
        }
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.allow)
            return
        }
        switch http.statusCode {
        case 200:
            completionHandler(.allow)
        case 401:
            DispatchQueue.main.async {
                self.isStreaming = false
                self.errorMessage = "API key incorrect — check Settings"
            }
            completionHandler(.cancel)
        case 503:
            // Server now sends a JSON body explaining why ffmpeg failed — collect it
            pendingErrorRead = true
            completionHandler(.allow)
        default:
            DispatchQueue.main.async {
                self.isStreaming = false
                self.errorMessage = "Camera stream error (HTTP \(http.statusCode))"
            }
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive data: Data) {
        if pendingErrorRead {
            buffer.append(data)   // accumulate 503 JSON body
        } else {
            buffer.append(data)
            extractFrames()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        DispatchQueue.main.async {
            self.isStreaming = false
            if self.pendingErrorRead {
                // Parse the 503 JSON body for the server's specific error message
                let msg = (try? JSONSerialization.jsonObject(with: self.buffer) as? [String: Any])
                    .flatMap { $0["error"] as? String }
                    ?? "Camera unavailable — check NAS logs for ffmpeg errors"
                self.errorMessage = msg
            } else if let err = error as NSError?, err.code != NSURLErrorCancelled {
                self.errorMessage = err.localizedDescription
            } else if error == nil && self.currentFrame == nil {
                self.errorMessage = "Camera offline — printer may be off or unreachable from NAS"
            }
        }
    }

    // MARK: - JPEG Frame Extraction

    private func extractFrames() {
        let soi = Data([0xFF, 0xD8])   // JPEG Start-Of-Image marker
        let eoi = Data([0xFF, 0xD9])   // JPEG End-Of-Image marker

        while buffer.count >= 4 {
            guard let startRange = buffer.range(of: soi) else {
                buffer = Data()
                return
            }
            guard let endRange = buffer.range(of: eoi, in: startRange.upperBound..<buffer.endIndex) else {
                // No complete frame yet — trim any garbage before SOI
                if startRange.lowerBound > 0 {
                    buffer = Data(buffer[startRange.lowerBound...])
                }
                return
            }

            // endRange.upperBound is past the last byte of EOI — exactly what we need
            let frameData = Data(buffer[startRange.lowerBound..<endRange.upperBound])
            if let image = UIImage(data: frameData) {
                DispatchQueue.main.async { self.currentFrame = image }
            }
            buffer = Data(buffer[endRange.upperBound...])
        }
    }
}

// MARK: - Camera Feed Card

struct CameraFeedCard: View {
    @EnvironmentObject var nasService: NASService
    @StateObject private var streamer = MJPEGStreamer()
    @State private var lightOn: Bool = false
    @State private var lightKnown: Bool = false
    @State private var lightBusy: Bool = false
    @State private var showFullscreen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            feedArea
            controlBar
        }
        .glassCard()
        .onAppear {
            streamer.start(baseURL: nasService.baseURL, apiKey: nasService.apiKey)
            Task { await refreshLightState() }
        }
        .onDisappear { streamer.stop() }
        .onChange(of: nasService.isConnected) { connected in
            if connected && !streamer.isStreaming {
                streamer.start(baseURL: nasService.baseURL, apiKey: nasService.apiKey)
            }
            if connected { Task { await refreshLightState() } }
        }
        .fullScreenCover(isPresented: $showFullscreen) {
            CameraFullscreenView()
                .environmentObject(nasService)
        }
        .onChange(of: showFullscreen) { showing in
            if !showing {
                // Revoke landscape permission first so requestGeometryUpdate
                // below has a valid portrait-only target (no more crash).
                OrientationManager.shared.allowed = .portrait
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    guard let scene = UIApplication.shared.connectedScenes
                        .compactMap({ $0 as? UIWindowScene }).first else { return }
                    scene.requestGeometryUpdate(
                        .iOS(interfaceOrientations: .portrait)
                    ) { _ in }
                }
            }
        }
    }

    private func refreshLightState() async {
        if let on = await nasService.fetchLightState() {
            lightOn = on
            lightKnown = true
        }
    }

    private func toggleLight() {
        guard !lightBusy else { return }
        let newState = !lightOn
        lightOn = newState   // optimistic
        lightBusy = true
        Task {
            do {
                try await nasService.setLight(on: newState)
            } catch {
                lightOn = !newState  // revert on failure
            }
            lightBusy = false
        }
    }

    // MARK: - Sub-views

    private var headerRow: some View {
        HStack {
            Label("Printer Camera", systemImage: "camera.fill")
                .font(.headline)
            Spacer()
            if streamer.isStreaming {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text("LIVE")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                }
            }
        }
        .padding([.horizontal, .top])
        .padding(.bottom, 10)
    }

    private var feedArea: some View {
        ZStack {
            Color.black
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            if let frame = streamer.currentFrame {
                Image(uiImage: frame)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))

            } else if streamer.isStreaming {
                VStack(spacing: 8) {
                    ProgressView().tint(.white)
                    Text("Connecting…")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }

            } else if let error = streamer.errorMessage {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }

            } else {
                VStack(spacing: 12) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 42))
                        .foregroundColor(.white.opacity(0.25))
                    Text("Tap Play to start live feed")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.4))
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { showFullscreen = true } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(7)
                    .background(.black.opacity(0.5))
                    .clipShape(Circle())
            }
            .padding(10)
        }
        .padding(.horizontal)
    }

    private var controlBar: some View {
        HStack(spacing: 10) {
            // Play / Stop
            if streamer.isStreaming {
                Button { streamer.stop() } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color.red.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            } else {
                Button { streamer.start(baseURL: nasService.baseURL, apiKey: nasService.apiKey) } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }

            // Chamber light toggle
            Button { toggleLight() } label: {
                ZStack {
                    if lightBusy {
                        ProgressView().tint(lightOn ? .yellow : .primary)
                    } else {
                        Image(systemName: lightOn ? "lightbulb.fill" : "lightbulb")
                            .font(.title3)
                            .foregroundColor(lightOn ? .yellow : .primary)
                    }
                }
                .frame(width: 44, height: 44)
                .background(lightOn ? Color.yellow.opacity(0.20) : Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .disabled(lightBusy || !nasService.isConnected)
        }
        .padding()
    }
}

// MARK: - Fullscreen Camera View

struct CameraFullscreenView: View {
    @EnvironmentObject var nasService: NASService
    @StateObject private var streamer = MJPEGStreamer()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let frame = streamer.currentFrame {
                Image(uiImage: frame)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea()
            } else if streamer.isStreaming {
                VStack(spacing: 8) {
                    ProgressView().tint(.white)
                    Text("Connecting…")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            } else if let error = streamer.errorMessage {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }

            // HUD overlay: live badge (top-left) + close button (top-right)
            VStack {
                HStack(alignment: .top) {
                    if streamer.isStreaming {
                        HStack(spacing: 5) {
                            Circle().fill(.red).frame(width: 8, height: 8)
                            Text("LIVE")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.red)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.45))
                        .clipShape(Capsule())
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white, .black.opacity(0.5))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                Spacer()
            }
        }
        .onAppear {
            streamer.start(baseURL: nasService.baseURL, apiKey: nasService.apiKey)
            // Grant landscape permission FIRST, then request the rotation.
            OrientationManager.shared.allowed = .landscape
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first else { return }
            scene.requestGeometryUpdate(
                .iOS(interfaceOrientations: .landscapeRight)
            ) { _ in }
        }
        .onDisappear {
            streamer.stop()
        }
}
