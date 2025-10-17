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

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var setupTask: Task<Void, Never>?

        func cancelSetup() {
            setupTask?.cancel()
            setupTask = nil
        }
    }

    func makeUIView(context: Context) -> DualCameraPreviewView {
        let view = DualCameraPreviewView()

        // Setup connections with error handling
        // Store task in coordinator for proper cleanup
        context.coordinator.setupTask = Task { @MainActor in
            await camera.setupDualPreviewConnections(
                backLayer: view.getBackLayer,
                frontLayer: view.getFrontLayer
            )
            // Error handling is done in setupDualPreviewConnections
            // which sets camera.error and triggers fallback if needed
        }

        return view
    }

    func updateUIView(_ uiView: DualCameraPreviewView, context: Context) {
        // No updates needed - connections are set once
        // Error state is handled by CameraView through camera.error
    }

    static func dismantleUIView(_ uiView: DualCameraPreviewView, coordinator: Coordinator) {
        // Cancel any pending setup task when view is deallocated
        coordinator.cancelSetup()
    }
}
