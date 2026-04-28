import AVFoundation
import Combine
import CoreGraphics
import CoreImage
import UIKit
import Vision

/// 将 Vision 的食指指尖从 `CMSampleBuffer` 中解析出来，供界面叠加绘制和点读命中。
final class HandPoseProcessor: NSObject, ObservableObject {
    /// 当前用于点读的食指指尖点。
    @Published private(set) var fingertipSets: [[[String: CGFloat]]] = []
    @Published private(set) var pointReadingText: String?
    @Published private(set) var recognizedTextPreview: String?
    @Published private(set) var aiState: PointReadingAIState = .idle
    /// 页面扫描得到的文字区块（与 `scannedBlocksSnapshot` 同步）。
    @Published private(set) var scannedTextBlocks: [ScannedTextBlock] = []
    /// 食指当前落入的热区（扫描区块）；未扫描时为 nil。
    @Published private(set) var activeHotZoneBlockID: UUID?

    private let sequenceRequest = VNSequenceRequestHandler()
    private let processingQueue = DispatchQueue(label: "hand.pose.vision", qos: .userInitiated)
    private let imageContext = CIContext()
    private var frameCount = 0
    private var lastIndexTip: CGPoint?
    private var stableIndexTipFrameCount = 0
    private var requestInFlight = false
    private var lastRequestTime: Date?
    /// 在后台队列读取，避免与 UI 更新竞态。
    private var scannedBlocksSnapshot: [ScannedTextBlock] = []

    private let stableMovementThreshold: CGFloat = 0.018
    private let stableFrameThreshold = 10
    private let requestCooldown: TimeInterval = 1.6

    func applyScannedBlocks(_ blocks: [ScannedTextBlock]) {
        processingQueue.sync {
            self.scannedBlocksSnapshot = blocks
        }
        scannedTextBlocks = blocks
        pointReadingText = nil
        activeHotZoneBlockID = nil
    }

    func clearScannedPage() {
        processingQueue.sync {
            self.scannedBlocksSnapshot = []
        }
        scannedTextBlocks = []
        pointReadingText = nil
        activeHotZoneBlockID = nil
    }

    func process(
        sampleBuffer: CMSampleBuffer,
        orientation: CGImagePropertyOrientation
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        processingQueue.async { [weak self] in
            guard let self else { return }

            let handRequest = VNDetectHumanHandPoseRequest()
            handRequest.maximumHandCount = 2
            self.frameCount += 1

            do {
                try self.sequenceRequest.perform([handRequest], on: pixelBuffer, orientation: orientation)

                let observations = handRequest.results ?? []
                var strongestIndexTip: (point: CGPoint, confidence: Float)?

                for observation in observations {
                    guard observation.confidence > 0.35 else { continue }

                    let points = try observation.recognizedPoints(.all)

                    if let indexTip = points[.indexTip], indexTip.confidence > 0.25 {
                        if strongestIndexTip == nil || indexTip.confidence > strongestIndexTip!.confidence {
                            strongestIndexTip = (indexTip.location, indexTip.confidence)
                        }
                    }
                }

                let indexTip = strongestIndexTip?.point
                let indexTipSet = indexTip.map {
                    [[
                        "x": CGFloat($0.x),
                        "y": CGFloat($0.y),
                        "c": CGFloat(strongestIndexTip?.confidence ?? 0),
                    ]]
                } ?? []

                DispatchQueue.main.async {
                    self.fingertipSets = indexTipSet.isEmpty ? [] : [indexTipSet]
                }

                self.updatePointReadingIfNeeded(
                    indexTip: indexTip,
                    pixelBuffer: pixelBuffer,
                    orientation: orientation
                )
            } catch {
                DispatchQueue.main.async {
                    self.fingertipSets = []
                    self.aiState = .failed("手势识别失败")
                }
            }
        }
    }

    private func updatePointReadingIfNeeded(
        indexTip: CGPoint?,
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    ) {
        if let indexTip {
            if scannedBlocksSnapshot.isEmpty {
                DispatchQueue.main.async {
                    self.activeHotZoneBlockID = nil
                }
            } else if let block = bestBlockContaining(indexTip: indexTip) {
                DispatchQueue.main.async {
                    self.activeHotZoneBlockID = block.id
                }
            } else {
                DispatchQueue.main.async {
                    self.activeHotZoneBlockID = nil
                }
            }
        } else {
            DispatchQueue.main.async {
                self.activeHotZoneBlockID = nil
            }
        }

        guard let indexTip else {
            lastIndexTip = nil
            stableIndexTipFrameCount = 0
            return
        }

        if !scannedBlocksSnapshot.isEmpty {
            updateBlockReadingIfNeeded(indexTip: indexTip)
            return
        }

        if let lastIndexTip, hypot(indexTip.x - lastIndexTip.x, indexTip.y - lastIndexTip.y) < stableMovementThreshold {
            stableIndexTipFrameCount += 1
        } else {
            stableIndexTipFrameCount = 1
        }
        lastIndexTip = indexTip

        guard stableIndexTipFrameCount >= stableFrameThreshold else { return }
        guard !requestInFlight else { return }

        if let lastRequestTime, Date().timeIntervalSince(lastRequestTime) < requestCooldown {
            return
        }

        guard let imageData = pointReadingImageData(
            from: pixelBuffer,
            orientation: orientation,
            indexTip: indexTip
        ) else {
            DispatchQueue.main.async {
                self.aiState = .failed("截图失败")
            }
            return
        }

        requestInFlight = true
        lastRequestTime = Date()
        DispatchQueue.main.async {
            self.aiState = .recognizing
            self.recognizedTextPreview = nil
        }

        Task {
            do {
                let text = try await PointReadingAIService.shared.recognize(
                    request: PointReadingAIRequest(imageData: imageData)
                )
                await MainActor.run {
                    self.pointReadingText = text
                    self.aiState = .idle
                }
            } catch {
                await MainActor.run {
                    if (error as? LocalizedError)?.errorDescription == "未配置 AI Key" {
                        self.aiState = .missingAPIKey
                    } else {
                        self.aiState = .failed((error as? LocalizedError)?.errorDescription ?? "AI 识别失败")
                    }
                }
            }
            self.processingQueue.async {
                self.requestInFlight = false
            }
        }
    }

    /// 扫描模式下：食指落在某一区块内且稳定后，直接读出该区块 OCR 文字。
    private func updateBlockReadingIfNeeded(indexTip: CGPoint) {
        guard let block = bestBlockContaining(indexTip: indexTip) else {
            lastIndexTip = nil
            stableIndexTipFrameCount = 0
            return
        }

        if let lastIndexTip, hypot(indexTip.x - lastIndexTip.x, indexTip.y - lastIndexTip.y) < stableMovementThreshold {
            stableIndexTipFrameCount += 1
        } else {
            stableIndexTipFrameCount = 1
        }
        lastIndexTip = indexTip

        guard stableIndexTipFrameCount >= stableFrameThreshold else { return }

        DispatchQueue.main.async {
            self.pointReadingText = block.text
            self.aiState = .idle
        }
    }

    private func bestBlockContaining(indexTip: CGPoint) -> ScannedTextBlock? {
        let hits = scannedBlocksSnapshot.filter { $0.boundingBox.contains(indexTip) }
        return hits.min {
            $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
        }
    }

    private func pointReadingImageData(
        from pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        indexTip: CGPoint
    ) -> Data? {
        let orientedImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
        guard let fullImage = imageContext.createCGImage(orientedImage, from: orientedImage.extent) else {
            return nil
        }

        let width = CGFloat(fullImage.width)
        let height = CGFloat(fullImage.height)
        let target = CGPoint(x: indexTip.x * width, y: (1 - indexTip.y) * height)
        let cropSide = min(max(min(width, height) * 0.68, 560), 980)
        let cropRect = CGRect(
            x: min(max(target.x - cropSide * 0.5, 0), max(width - cropSide, 0)),
            y: min(max(target.y - cropSide * 0.45, 0), max(height - cropSide, 0)),
            width: min(cropSide, width),
            height: min(cropSide, height)
        ).integral

        guard let cropped = fullImage.cropping(to: cropRect) else {
            return nil
        }

        let maxOutputSide: CGFloat = 900
        let scale = min(1, maxOutputSide / max(CGFloat(cropped.width), CGFloat(cropped.height)))
        let outputSize = CGSize(width: CGFloat(cropped.width) * scale, height: CGFloat(cropped.height) * scale)
        let markerCenter = CGPoint(
            x: (target.x - cropRect.minX) * scale,
            y: (target.y - cropRect.minY) * scale
        )

        let renderer = UIGraphicsImageRenderer(size: outputSize)
        let markedImage = renderer.image { context in
            UIImage(cgImage: cropped).draw(in: CGRect(origin: .zero, size: outputSize))

            let radius = max(11, min(outputSize.width, outputSize.height) * 0.026)
            let markerRect = CGRect(
                x: markerCenter.x - radius,
                y: markerCenter.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            UIColor.white.setStroke()
            context.cgContext.setLineWidth(max(3, radius * 0.25))
            context.cgContext.strokeEllipse(in: markerRect)
            UIColor.systemGreen.withAlphaComponent(0.82).setFill()
            context.cgContext.fillEllipse(in: markerRect.insetBy(dx: 2, dy: 2))
        }

        return markedImage.jpegData(compressionQuality: 0.74)
    }
}
