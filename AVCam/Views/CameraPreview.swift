/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A view that presents a video preview of the captured content.
*/

import SwiftUI
@preconcurrency import AVFoundation

struct CameraPreview: UIViewRepresentable {
    
    private let source: PreviewSource
    
    init(source: PreviewSource) {
        self.source = source
    }
    
    func makeUIView(context: Context) -> PreviewView {
        let preview = PreviewView()
        // Connect the preview layer to the capture session.
        source.connect(to: preview)
        return preview
    }
    
    func updateUIView(_ previewView: PreviewView, context: Context) {
        // No-op.
    }
    
    /// A class that presents the captured content.
    ///
    /// This class owns the `AVCaptureVideoPreviewLayer` that presents the captured content.
    ///
    class PreviewView: UIView, PreviewTarget {
        
        init() {
            super.init(frame: .zero)
    #if targetEnvironment(simulator)
            // The capture APIs require running on a real device. If running
            // in Simulator, display a static image to represent the video feed.
            // Note: Using .zero frame initially; autoresizing will handle layout
            let imageView = UIImageView(frame: .zero)
            imageView.image = UIImage(named: "video_mode")
            imageView.contentMode = .scaleAspectFill
            imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(imageView)
    #endif
        }

        override func layoutSubviews() {
            super.layoutSubviews()
    #if targetEnvironment(simulator)
            // Update image view frame to match bounds
            subviews.first?.frame = bounds
    #endif
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        // Use the preview layer as the view's backing layer.
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }
        
        var previewLayer: AVCaptureVideoPreviewLayer? {
            layer as? AVCaptureVideoPreviewLayer
        }
        
        nonisolated func setSession(_ session: AVCaptureSession) {
            // Connects the session with the preview layer, which allows the layer
            // to provide a live view of the captured content.
            Task { @MainActor in
                guard let layer = previewLayer else {
                    print("Warning: Preview layer not available")
                    return
                }
                layer.session = session

                // Notify that a real preview layer has been attached so rotation coordinator can bind to it
                NotificationCenter.default.post(name: .previewLayerAttached, object: layer)
            }
        }
    }
}

/// A protocol that enables a preview source to connect to a preview target.
///
/// The app provides an instance of this type to the client tier so it can connect
/// the capture session to the `PreviewView` view. It uses these protocols
/// to prevent explicitly exposing the capture objects to the UI layer.
///
protocol PreviewSource: Sendable {
    // Connects a preview destination to this source.
    func connect(to target: PreviewTarget)
}

/// A protocol that passes the app's capture session to the `CameraPreview` view.
protocol PreviewTarget {
    // Sets the capture session on the destination.
    func setSession(_ session: AVCaptureSession)
}

/// The app's default `PreviewSource` implementation.
struct DefaultPreviewSource: PreviewSource {
    
    private let session: AVCaptureSession
    
    init(session: AVCaptureSession) {
        self.session = session
    }
    
    func connect(to target: PreviewTarget) {
        target.setSession(session)
    }
}

extension Notification.Name {
    static let previewLayerAttached = Notification.Name("PreviewLayerAttachedNotification")
}
