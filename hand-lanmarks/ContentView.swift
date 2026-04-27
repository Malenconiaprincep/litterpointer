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
            CameraPreviewRepresentable(session: camera.session, previewLayerRef: $previewLayer)
                .ignoresSafeArea()

            GeometryReader { _ in
                FingertipOverlay(
                    fingertipSets: processor.fingertipSets,
                    previewLayer: previewLayer
                )
            }
            .ignoresSafeArea()

            VStack {
                Text("五指指尖识别（Vision）")
                    .font(.headline)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Capsule())
                Spacer()
                Text("将手掌朝向前置摄像头")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 24)
            }
            .padding(.top, 16)
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

#Preview {
    ContentView()
}
