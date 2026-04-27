import AVFoundation
import SwiftUI
import UIKit

/// 承载 `AVCaptureVideoPreviewLayer`，并把 sample buffer 交给手势处理。
final class CameraSessionController: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    @Published private(set) var cameraPosition: AVCaptureDevice.Position = .front
    let processor = HandPoseProcessor()

    private let sessionQueue = DispatchQueue(label: "camera.session")
    private var currentInput: AVCaptureDeviceInput?

    override init() {
        super.init()
        configureSession()
    }

    /// 与界面方向一致，避免 Vision 归一化坐标与预览「上下颠倒 / 反向移动」。
    static func interfaceVideoOrientation() -> AVCaptureVideoOrientation {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return .portrait
        }
        let ui = scene.interfaceOrientation
        switch ui {
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeRight
        case .landscapeRight:
            return .landscapeLeft
        default:
            return .portrait
        }
    }

    /// 根据当前界面方向更新视频输出；须与预览层一致，否则叠加层与画面会错位。
    func syncVideoOrientationWithInterface() {
        let av = Self.interfaceVideoOrientation()
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.applyConnectionSettings(
                videoOrientation: av,
                cameraPosition: self.currentInput?.device.position ?? self.cameraPosition
            )
        }
    }

    private func configureSession() {
        session.sessionPreset = .high

        guard let input = makeInput(for: .front), session.canAddInput(input) else { return }

        session.addInput(input)
        currentInput = input

        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: sessionQueue)

        guard session.canAddOutput(output) else { return }
        session.addOutput(output)

        applyConnectionSettings(videoOrientation: Self.interfaceVideoOrientation(), cameraPosition: .front)
    }

    var cameraInstruction: String {
        switch cameraPosition {
        case .front:
            return "将手掌朝向前置摄像头"
        case .back:
            return "将手掌放在后置摄像头视野内"
        default:
            return "将手掌放在摄像头视野内"
        }
    }

    var switchButtonTitle: String {
        cameraPosition == .front ? "后置" : "前置"
    }

    func switchCamera() {
        let target: AVCaptureDevice.Position = cameraPosition == .front ? .back : .front

        sessionQueue.async { [weak self] in
            guard let self, let nextInput = self.makeInput(for: target) else { return }

            self.session.beginConfiguration()
            if let currentInput = self.currentInput {
                self.session.removeInput(currentInput)
            }

            guard self.session.canAddInput(nextInput) else {
                if let currentInput = self.currentInput, self.session.canAddInput(currentInput) {
                    self.session.addInput(currentInput)
                    self.applyConnectionSettings(
                        videoOrientation: Self.interfaceVideoOrientation(),
                        cameraPosition: currentInput.device.position
                    )
                }
                self.session.commitConfiguration()
                return
            }

            self.session.addInput(nextInput)
            self.currentInput = nextInput
            self.applyConnectionSettings(videoOrientation: Self.interfaceVideoOrientation(), cameraPosition: target)
            self.session.commitConfiguration()

            DispatchQueue.main.async {
                self.cameraPosition = target
            }
        }
    }

    private func makeInput(for position: AVCaptureDevice.Position) -> AVCaptureDeviceInput? {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            return nil
        }
        return try? AVCaptureDeviceInput(device: device)
    }

    private func applyConnectionSettings(
        videoOrientation: AVCaptureVideoOrientation,
        cameraPosition: AVCaptureDevice.Position
    ) {
        guard let conn = output.connection(with: .video) else { return }

        if conn.isVideoOrientationSupported {
            conn.videoOrientation = videoOrientation
        }
        if conn.isVideoMirroringSupported {
            conn.automaticallyAdjustsVideoMirroring = false
            conn.isVideoMirrored = cameraPosition == .front
        }
    }

    func start() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        syncVideoOrientationWithInterface()
        sessionQueue.async { [weak self] in
            self?.session.startRunning()
        }
    }

    func stop() {
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }
}

extension CameraSessionController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let orientation = visionImageOrientation(
            videoOrientation: connection.videoOrientation,
            cameraPosition: currentInput?.device.position ?? cameraPosition
        )
        processor.process(sampleBuffer: sampleBuffer, orientation: orientation)
    }

    /// `videoOrientation` 与传给 Vision 的朝向一致时，归一化坐标才能和预览对齐。
    private func visionImageOrientation(
        videoOrientation: AVCaptureVideoOrientation,
        cameraPosition: AVCaptureDevice.Position
    ) -> CGImagePropertyOrientation {
        let front = cameraPosition == .front
        switch videoOrientation {
        case .portrait:
            return front ? .leftMirrored : .right
        case .portraitUpsideDown:
            return front ? .rightMirrored : .left
        case .landscapeLeft:
            return front ? .downMirrored : .up
        case .landscapeRight:
            return front ? .upMirrored : .down
        @unknown default:
            return front ? .leftMirrored : .right
        }
    }
}

struct CameraPreviewRepresentable: UIViewRepresentable {
    let session: AVCaptureSession
    @Binding var previewLayerRef: AVCaptureVideoPreviewLayer?

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.videoPreviewLayer.session = session
        v.videoPreviewLayer.videoGravity = .resizeAspectFill
        DispatchQueue.main.async {
            previewLayerRef = v.videoPreviewLayer
        }
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer.session = session
        previewLayerRef = uiView.videoPreviewLayer
        let av = CameraSessionController.interfaceVideoOrientation()
        if let c = uiView.videoPreviewLayer.connection, c.isVideoOrientationSupported {
            c.videoOrientation = av
        }
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}
