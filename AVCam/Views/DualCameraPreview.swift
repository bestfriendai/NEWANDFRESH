/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
A SwiftUI wrapper for the dual camera preview UIKit view.
*/

import SwiftUI
import AVFoundation

/// SwiftUI wrapper for dual camera preview
struct DualCameraPreview<CameraModel: Camera>: UIViewRepresentable {
    let camera: CameraModel

    func makeUIView(context: Context) -> DualCameraPreviewView {
        let view = DualCameraPreviewView()

        // Setup connections asynchronously
        Task { @MainActor in
            await camera.setupDualPreviewConnections(
                backLayer: view.getBackLayer,
                frontLayer: view.getFrontLayer
            )
        }

        return view
    }

    func updateUIView(_ uiView: DualCameraPreviewView, context: Context) {
        // No updates needed - connections are set once
    }
}
