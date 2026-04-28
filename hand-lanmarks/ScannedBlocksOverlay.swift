import AVFoundation
import SwiftUI

/// 扫描后叠加在预览上的文字区块（热区轮廓）。
struct ScannedBlocksOverlay: View {
    let blocks: [ScannedTextBlock]
    let activeBlockID: UUID?
    let cameraPosition: AVCaptureDevice.Position
    var previewLayer: AVCaptureVideoPreviewLayer?

    var body: some View {
        Canvas { context, size in
            for block in blocks {
                let rect = CameraPreviewGeometry.viewRect(
                    visionBoundingBox: block.boundingBox,
                    viewSize: size,
                    cameraPosition: cameraPosition,
                    previewLayer: previewLayer
                )
                guard rect.width > 1, rect.height > 1 else { continue }

                let rounded = Path(roundedRect: rect, cornerRadius: 6)
                let isHot = block.id == activeBlockID
                context.fill(rounded, with: .color(isHot ? Color.blue.opacity(0.22) : Color.cyan.opacity(0.12)))
                context.stroke(
                    rounded,
                    with: .color(isHot ? Color.blue.opacity(0.95) : Color.cyan.opacity(0.75)),
                    lineWidth: isHot ? 3 : 1.5
                )
            }
        }
        .allowsHitTesting(false)
    }
}
