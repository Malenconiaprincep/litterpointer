import AVFoundation
import CoreGraphics
import SwiftUI

/// Vision 归一化坐标与预览层显示区域的转换（与 `FingertipOverlay` 食指映射一致）。
enum CameraPreviewGeometry {
    /// 单点：Vision 归一化（左下原点）→ 与视频 metadata 一致的归一化，再交给预览层。
    static func visionNormalizedToMetadata(_ point: CGPoint, isBackCamera: Bool) -> CGPoint {
        let nx = isBackCamera ? 1 - point.x : point.x
        let metadataY = isBackCamera ? point.y : 1 - point.y
        return CGPoint(x: nx, y: metadataY)
    }

    static func viewPoint(
        normalizedVision: CGPoint,
        viewSize: CGSize,
        cameraPosition: AVCaptureDevice.Position,
        previewLayer: AVCaptureVideoPreviewLayer?
    ) -> CGPoint {
        let isBack = cameraPosition == .back
        let p = visionNormalizedToMetadata(normalizedVision, isBackCamera: isBack)
        guard let layer = previewLayer else {
            return CGPoint(x: p.x * viewSize.width, y: p.y * viewSize.height)
        }
        let metadataRect = CGRect(x: p.x, y: p.y, width: 0.002, height: 0.002)
        let rectInLayer = layer.layerRectConverted(fromMetadataOutputRect: metadataRect)
        return CGPoint(x: rectInLayer.midX, y: rectInLayer.midY)
    }

    /// 文字框：Vision `boundingBox` → 预览视图中的像素矩形。
    static func viewRect(
        visionBoundingBox box: CGRect,
        viewSize: CGSize,
        cameraPosition: AVCaptureDevice.Position,
        previewLayer: AVCaptureVideoPreviewLayer?
    ) -> CGRect {
        let isBack = cameraPosition == .back
        let corners = [
            CGPoint(x: box.minX, y: box.minY),
            CGPoint(x: box.maxX, y: box.minY),
            CGPoint(x: box.minX, y: box.maxY),
            CGPoint(x: box.maxX, y: box.maxY),
        ]
        let metadataCorners = corners.map { visionNormalizedToMetadata($0, isBackCamera: isBack) }

        guard let layer = previewLayer else {
            let xs = metadataCorners.map(\.x)
            let ys = metadataCorners.map(\.y)
            guard let xMin = xs.min(), let xMax = xs.max(), let yMin = ys.min(), let yMax = ys.max() else {
                return .zero
            }
            return CGRect(
                x: xMin * viewSize.width,
                y: yMin * viewSize.height,
                width: (xMax - xMin) * viewSize.width,
                height: (yMax - yMin) * viewSize.height
            )
        }

        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude

        for p in metadataCorners {
            let mr = CGRect(x: p.x, y: p.y, width: 0.002, height: 0.002)
            let r = layer.layerRectConverted(fromMetadataOutputRect: mr)
            minX = min(minX, r.minX)
            minY = min(minY, r.minY)
            maxX = max(maxX, r.maxX)
            maxY = max(maxY, r.maxY)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
