//
//  ContentView.swift
//  hand-lanmarks
//
//  Created by makuta on 2026/4/27.
//

import AVFoundation
import SwiftUI

struct ContentView: View {
    @StateObject private var camera = CameraSessionController()

    var body: some View {
        FingertipCameraRoot(camera: camera)
    }
}

/// 单独持有 `HandPoseProcessor` 的 `ObservedObject`，以便指尖坐标刷新界面。
private struct FingertipCameraRoot: View {
    @ObservedObject var camera: CameraSessionController
    @ObservedObject var processor: HandPoseProcessor
    @State private var previewLayer: AVCaptureVideoPreviewLayer?

    init(camera: CameraSessionController) {
        self.camera = camera
        _processor = ObservedObject(wrappedValue: camera.processor)
    }

    var body: some View {
        ZStack {
            CameraPreviewRepresentable(
                session: camera.session,
                previewLayerRef: $previewLayer
            )
                .ignoresSafeArea()

            GeometryReader { _ in
                ZStack {
                    ScannedBlocksOverlay(
                        blocks: processor.scannedTextBlocks,
                        activeBlockID: processor.activeHotZoneBlockID,
                        cameraPosition: camera.cameraPosition,
                        previewLayer: previewLayer
                    )
                    FingertipOverlay(
                        fingertipSets: processor.fingertipSets,
                        cameraPosition: camera.cameraPosition,
                        previewLayer: previewLayer
                    )
                }
            }
            .ignoresSafeArea()

            VStack {
                HStack(spacing: 8) {
                    Text("五指指尖识别（Vision）")
                        .font(.headline)
                        .padding(8)
                        .background(.ultraThinMaterial, in: Capsule())

                    Spacer(minLength: 8)

                    Button {
                        camera.requestPageScan()
                    } label: {
                        HStack(spacing: 6) {
                            if camera.isPageScanning {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "doc.text.viewfinder")
                            }
                            Text("扫描页面")
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .disabled(camera.isPageScanning)

                    if !processor.scannedTextBlocks.isEmpty {
                        Button {
                            camera.clearPageScan()
                        } label: {
                            Text("清除区块")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                    }

                    Button {
                        camera.switchCamera()
                    } label: {
                        Label(camera.switchButtonTitle, systemImage: "camera.rotate")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 10) {
                    if let banner = camera.pageScanBanner {
                        Text(banner)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }

                    PointReadingResultBlock(
                        pointReadingText: processor.pointReadingText,
                        aiState: processor.aiState,
                        recognizedTextPreview: processor.recognizedTextPreview,
                        hasScannedBlocks: !processor.scannedTextBlocks.isEmpty,
                        isPageScanning: camera.isPageScanning
                    )

                    Text(camera.cameraInstruction)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.bottom, 24)
            }
            .padding(.top, 16)
            .padding(.horizontal, 16)
        }
        .onAppear {
            camera.syncVideoOrientationWithInterface()
            camera.start()
        }
        .onDisappear {
            camera.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            camera.syncVideoOrientationWithInterface()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            camera.syncVideoOrientationWithInterface()
        }
    }
}

// MARK: - AI 点读结果区块

/// 将 AI 状态与识别文字放进独立卡片，便于区分「等待 / 识别中 / 成功 / 失败」。
private struct PointReadingResultBlock: View {
    var pointReadingText: String?
    var aiState: PointReadingAIState
    var recognizedTextPreview: String?
    var hasScannedBlocks: Bool
    var isPageScanning: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: headerIcon)
                    .font(.body.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(headerTint)
                Text(headerTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if case .recognizing = aiState {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Divider()
                .opacity(0.35)

            Group {
                if let text = pointReadingText, !text.isEmpty {
                    Text(text)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                        .lineLimit(8)
                        .minimumScaleFactor(0.7)
                } else if let message = aiState.message {
                    Text(message)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                } else if let preview = recognizedTextPreview, !preview.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("画面中的文字预览（移动食指做 AI 点读）")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(preview)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                            .minimumScaleFactor(0.8)
                    }
                } else {
                    Text(idleHint)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.22), lineWidth: 1)
        }
    }

    private var headerTitle: String {
        if let text = pointReadingText, !text.isEmpty {
            return "点读结果"
        }
        switch aiState {
        case .recognizing:
            return "AI 识别中"
        case .failed:
            return "识别未成功"
        case .missingAPIKey:
            return "需要配置 Key"
        case .idle:
            if recognizedTextPreview?.isEmpty == false {
                return "文字预览"
            }
            return "AI 点读"
        }
    }

    private var headerIcon: String {
        if let text = pointReadingText, !text.isEmpty {
            return "text.bubble.fill"
        }
        switch aiState {
        case .recognizing:
            return "sparkles"
        case .failed, .missingAPIKey:
            return "exclamationmark.triangle.fill"
        case .idle:
            if recognizedTextPreview?.isEmpty == false {
                return "doc.text.viewfinder"
            }
            return "hand.point.up.left.fill"
        }
    }

    private var headerTint: Color {
        switch aiState {
        case .failed, .missingAPIKey:
            return .orange
        case .recognizing:
            return .blue
        default:
            if pointReadingText.map({ !$0.isEmpty }) == true {
                return .green
            }
            return .primary
        }
    }

    private var idleHint: String {
        if isPageScanning {
            return "正在扫描当前画面中的文字…"
        }
        if hasScannedBlocks {
            return "食指点进青色区块即高亮热区；停留约 1 秒读出该段文字。"
        }
        return "先点「扫描页面」生成文字区块，再食指点选；未扫描时，食指停留可调 AI 点读。"
    }
}

#Preview {
    ContentView()
}
