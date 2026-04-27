import AVFoundation
import SwiftUI
import UIKit

/// 承载 `AVCaptureVideoPreviewLayer`，并把 sample buffer 交给手势处理。
final class CameraSessionController: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    let processor = HandPoseProcessor()

    private let sessionQueue = DispatchQueue(label: "camera.session")

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
            if let conn = self.output.connection(with: .video), conn.isVideoOrientationSupported {
                conn.videoOrientation = av
            }
        }
    }

    private func configureSession() {
        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return }

        session.addInput(input)

        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: sessionQueue)

        guard session.canAddOutput(output) else { return }
        session.addOutput(output)

        let av = Self.interfaceVideoOrientation()
        if let conn = output.connection(with: .video) {
            if conn.isVideoOrientationSupported {
                conn.videoOrientation = av
            }
            if conn.isVideoMirroringSupported {
                conn.automaticallyAdjustsVideoMirroring = false
                conn.isVideoMirrored = true
            }
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
            cameraPosition: .front
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
