import SwiftUI
import AVFoundation

struct BarcodeScannerView: UIViewControllerRepresentable {
    var onScanned: (String) -> Void

    func makeUIViewController(context: Context) -> BarcodeScannerViewController {
        let vc = BarcodeScannerViewController()
        vc.onScanned = onScanned
        return vc
    }

    func updateUIViewController(_ uiViewController: BarcodeScannerViewController, context: Context) {}
}

class BarcodeScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScanned: ((String) -> Void)?
    var captureSession: AVCaptureSession!
    var previewLayer: AVCaptureVideoPreviewLayer!
    var overlayView: UIView!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
        setupOverlay()
    }

    func setupCamera() {
        captureSession = AVCaptureSession()
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            showNoCameraAlert()
            return
        }

        captureSession.addInput(input)

        let output = AVCaptureMetadataOutput()
        captureSession.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [
            .ean13, .ean8, .upce, .code128, .code39, .qr, .dataMatrix
        ]

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.layer.bounds
        view.layer.addSublayer(previewLayer)

        DispatchQueue.global(qos: .background).async {
            self.captureSession.startRunning()
        }
    }

    func setupOverlay() {
        // Scanning frame overlay
        overlayView = UIView()
        overlayView.frame = view.bounds
        overlayView.backgroundColor = .clear
        view.addSubview(overlayView)

        // Dimmed area
        let path = UIBezierPath(rect: view.bounds)
        let scanRect = CGRect(
            x: view.bounds.width * 0.1,
            y: view.bounds.height * 0.3,
            width: view.bounds.width * 0.8,
            height: view.bounds.height * 0.2
        )
        path.append(UIBezierPath(roundedRect: scanRect, cornerRadius: 12).reversing())

        let dimLayer = CAShapeLayer()
        dimLayer.path = path.cgPath
        dimLayer.fillColor = UIColor.black.withAlphaComponent(0.5).cgColor
        overlayView.layer.addSublayer(dimLayer)

        // Green border on scan box
        let borderLayer = CAShapeLayer()
        borderLayer.path = UIBezierPath(roundedRect: scanRect, cornerRadius: 12).cgPath
        borderLayer.strokeColor = UIColor.systemOrange.cgColor
        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.lineWidth = 3
        overlayView.layer.addSublayer(borderLayer)

        // Label
        let label = UILabel()
        label.text = "Align barcode within the frame"
        label.textColor = .white
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textAlignment = .center
        label.frame = CGRect(x: 0, y: scanRect.maxY + 20, width: view.bounds.width, height: 30)
        overlayView.addSubview(label)

        // Cancel button
        let cancelBtn = UIButton(type: .system)
        cancelBtn.setTitle("Cancel", for: .normal)
        cancelBtn.titleLabel?.font = .systemFont(ofSize: 18, weight: .medium)
        cancelBtn.tintColor = .white
        cancelBtn.frame = CGRect(x: 0, y: view.bounds.height - 80, width: view.bounds.width, height: 50)
        cancelBtn.addTarget(self, action: #selector(cancel), for: .touchUpInside)
        overlayView.addSubview(cancelBtn)

        // Torch button
        let torchBtn = UIButton(type: .system)
        torchBtn.setImage(UIImage(systemName: "flashlight.off.fill"), for: .normal)
        torchBtn.tintColor = .white
        torchBtn.frame = CGRect(x: view.bounds.width - 60, y: 20, width: 44, height: 44)
        torchBtn.addTarget(self, action: #selector(toggleTorch), for: .touchUpInside)
        overlayView.addSubview(torchBtn)
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let obj = objects.first as? AVMetadataMachineReadableCodeObject,
              let code = obj.stringValue else { return }
        captureSession.stopRunning()
        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
        onScanned?(code)
    }

    @objc func cancel() {
        captureSession?.stopRunning()
        dismiss(animated: true)
    }

    @objc func toggleTorch() {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        try? device.lockForConfiguration()
        device.torchMode = device.torchMode == .on ? .off : .on
        device.unlockForConfiguration()
    }

    func showNoCameraAlert() {
        let alert = UIAlertController(title: "No Camera", message: "Camera access is required for scanning.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in self.dismiss(animated: true) })
        present(alert, animated: true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession?.stopRunning()
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
}
