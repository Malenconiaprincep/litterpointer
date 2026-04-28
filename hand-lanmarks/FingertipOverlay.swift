import SwiftUI
import AVFoundation

/// 把 Vision 归一化坐标映射到预览区域上的覆盖层。
struct FingertipOverlay: View {
    let fingertipSets: [[[String: CGFloat]]]
    let cameraPosition: AVCaptureDevice.Position
    /// 优先用预览层做坐标变换（含镜像、裁剪与宽高比）；为 nil 时退回纯数学映射。
    var previewLayer: AVCaptureVideoPreviewLayer?

    var body: some View {
        Canvas { context, size in
            for (handIndex, tips) in fingertipSets.enumerated() {
                for tip in tips {
                    guard
                        let nx = tip["x"],
                        let ny = tip["y"]
                    else { continue }

                    let p = CameraPreviewGeometry.viewPoint(
                        normalizedVision: CGPoint(x: nx, y: ny),
                        viewSize: size,
                        cameraPosition: cameraPosition,
                        previewLayer: previewLayer
                    )
                    let radius: CGFloat = 10 + CGFloat(handIndex) * 2

                    context.fill(
                        Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)),
                        with: .color(Color.green.opacity(0.85))
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
}
