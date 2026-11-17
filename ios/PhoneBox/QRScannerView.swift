import AVFoundation
import SwiftUI
import UIKit

/// Camera preview that reads QR codes. `onCode` returns true when the text was accepted (scanning then stops);
/// false shows a short "not a PhoneBox code" hint and keeps scanning.
struct QRScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Bool

    func makeUIViewController(context: Context) -> QRScannerViewController { QRScannerViewController(onCode: onCode) }
    func updateUIViewController(_ controller: QRScannerViewController, context: Context) { controller.onCode = onCode }
}

final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: (String) -> Bool
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "vn.xox.phonebox.qr")
    private let preview = AVCaptureVideoPreviewLayer()
    private let message = UILabel()
    private let settingsButton = UIButton(type: .system)
    private var finished = false
    private var hintResetTask: DispatchWorkItem?
    private static let idleHint = "Quét mã QR trong Cài đặt PhoneBox trên máy tính"

    init(onCode: @escaping (String) -> Bool) {
        self.onCode = onCode
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        message.textColor = .white
        message.numberOfLines = 0
        message.textAlignment = .center
        message.font = .preferredFont(forTextStyle: .body)
        message.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        message.text = Self.idleHint
        settingsButton.setTitle("Mở Cài đặt", for: .normal)
        settingsButton.isHidden = true
        settingsButton.addAction(UIAction { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        }, for: .touchUpInside)
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        view.addSubview(message)
        view.addSubview(settingsButton)
        requestAccessThenConfigure()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview.frame = view.bounds
        let inset = view.safeAreaInsets
        let width = view.bounds.width - 32
        let height = message.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height + 16
        message.frame = CGRect(x: 16, y: view.bounds.height - inset.bottom - height - 24, width: width, height: height)
        settingsButton.frame = CGRect(x: 16, y: message.frame.minY - 48, width: width, height: 40)
        updatePreviewOrientation()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        let session = self.session
        sessionQueue.async { if session.isRunning { session.stopRunning() } }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !finished, session.inputs.isEmpty == false else { return }
        let session = self.session
        sessionQueue.async { if !session.isRunning { session.startRunning() } }
    }

    // MARK: setup

    private func requestAccessThenConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async { granted ? self?.configure() : self?.showDenied() }
            }
        default: showDenied()
        }
    }

    private func showDenied() {
        show("PhoneBox cần quyền camera để quét mã QR. Hãy bật trong Cài đặt.")
        settingsButton.isHidden = false
    }

    private func configure() {
        guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            show("Thiết bị này không có camera dùng được. Hãy mở liên kết phonebox:// từ trang ghép nối.")
            return
        }
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { show("Không khởi động được camera."); return }
        session.addInput(input)
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = output.availableMetadataObjectTypes.contains(.qr) ? [.qr] : []
        preview.session = session
        updatePreviewOrientation()
        let session = self.session
        sessionQueue.async { session.startRunning() }
    }

    private func updatePreviewOrientation() {
        guard let connection = preview.connection, let scene = view.window?.windowScene else { return }
        let angle: CGFloat
        switch scene.interfaceOrientation {
        case .landscapeLeft: angle = 180
        case .landscapeRight: angle = 0
        case .portraitUpsideDown: angle = 270
        default: angle = 90
        }
        if #available(iOS 17.0, *) {
            if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
        } else if connection.isVideoOrientationSupported {
            // raw values of UIInterfaceOrientation and AVCaptureVideoOrientation are the same
            connection.videoOrientation = AVCaptureVideoOrientation(rawValue: scene.interfaceOrientation.rawValue) ?? .portrait
        }
    }

    // MARK: results

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !finished, let text = objects.compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }).first else { return }
        if onCode(text) {
            finished = true
            let session = self.session
            sessionQueue.async { session.stopRunning() }
        } else {
            show("Không phải mã ghép nối của PhoneBox.")
            hintResetTask?.cancel()
            let reset = DispatchWorkItem { [weak self] in self?.show(Self.idleHint) }
            hintResetTask = reset
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: reset)
        }
    }

    private func show(_ text: String) {
        message.text = text
        view.setNeedsLayout()
    }
}
