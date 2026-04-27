import SwiftUI
import AVFoundation

/// 把 Vision 归一化坐标映射到预览区域上的覆盖层。
struct FingertipOverlay: View {
    let fingertipSets: [[[String: CGFloat]]]
    /// 优先用预览层做坐标变换（含镜像、裁剪与宽高比）；为 nil 时退回纯数学映射。
    var previewLayer: AVCaptureVideoPreviewLayer?

    private let colors: [Color] = [
        .red,
        .green,
        .blue,
        .orange,
        .purple,
    ]

    var body: some View {
        Canvas { context, size in
            for (handIndex, tips) in fingertipSets.enumerated() {
                for (i, tip) in tips.enumerated() {
                    guard
                        let nx = tip["x"],
                        let ny = tip["y"]
                    else { continue }

                    let p = viewPoint(
                        normalizedVision: CGPoint(x: nx, y: ny),
                        viewSize: size,
                        previewLayer: previewLayer
                    )
                    let radius: CGFloat = 10 + CGFloat(handIndex) * 2

                    context.fill(
                        Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)),
                        with: .color(colors[i % colors.count].opacity(0.85))
                    )
                    context.stroke(
                        Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)),
                        with: .color(.white),
                        lineWidth: 2
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Vision：归一化、原点在图像左下。Metadata / 预览层转换：原点在左上。
    private func viewPoint(
        normalizedVision: CGPoint,
        viewSize: CGSize,
        previewLayer: AVCaptureVideoPreviewLayer?
    ) -> CGPoint {
        guard let layer = previewLayer else {
            let x = normalizedVision.x * viewSize.width
            let y = (1 - normalizedVision.y) * viewSize.height
            return CGPoint(x: x, y: y)
        }

        let nx = normalizedVision.x
        let ny = normalizedVision.y
        let metadataRect = CGRect(
            x: nx,
            y: 1 - ny,
            width: 0.002,
            height: 0.002
        )
        let rectInLayer = layer.layerRectConverted(fromMetadataOutputRect: metadataRect)
        return CGPoint(x: rectInLayer.midX, y: rectInLayer.midY)
    }
}
