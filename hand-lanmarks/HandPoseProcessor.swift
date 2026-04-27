import AVFoundation
import Combine
import CoreGraphics
import UIKit
import Vision

/// 将 Vision 的手部关节（含五指指尖）从 `CMSampleBuffer` 中解析出来，供界面叠加绘制。
final class HandPoseProcessor: NSObject, ObservableObject {
    /// 每只手一组点，顺序：拇指、食指、中指、无名指、小指指尖。
    @Published private(set) var fingertipSets: [[[String: CGFloat]]] = []

    private let sequenceRequest = VNSequenceRequestHandler()
    private let processingQueue = DispatchQueue(label: "hand.pose.vision", qos: .userInitiated)

    private static let tipJoints: [VNHumanHandPoseObservation.JointName] = [
        .thumbTip,
        .indexTip,
        .middleTip,
        .ringTip,
        .littleTip,
    ]

    func process(sampleBuffer: CMSampleBuffer, orientation: CGImagePropertyOrientation) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 2

        processingQueue.async { [weak self] in
            guard let self else { return }

            do {
                try self.sequenceRequest.perform([request], on: pixelBuffer, orientation: orientation)

                guard let observations = request.results, !observations.isEmpty else {
                    DispatchQueue.main.async {
                        self.fingertipSets = []
                    }
                    return
                }

                var sets: [[[String: CGFloat]]] = []

                for observation in observations {
                    guard observation.confidence > 0.35 else { continue }

                    let points = try observation.recognizedPoints(.all)
                    var tips: [[String: CGFloat]] = []

                    for joint in Self.tipJoints {
                        guard let p = points[joint], p.confidence > 0.25 else { continue }
                        tips.append([
                            "x": CGFloat(p.location.x),
                            "y": CGFloat(p.location.y),
                            "c": CGFloat(p.confidence),
                        ])
                    }

                    if !tips.isEmpty {
                        sets.append(tips)
                    }
                }

                DispatchQueue.main.async {
                    self.fingertipSets = sets
                }
            } catch {
                DispatchQueue.main.async {
                    self.fingertipSets = []
                }
            }
        }
    }
}
