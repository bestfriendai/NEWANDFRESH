/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
A UIKit view that displays dual camera preview layers for simultaneous front and back camera capture.
*/

import UIKit
import AVFoundation

/// Container view for dual camera preview layers in split-screen mode
///
/// **Design Note:** This implementation uses a 50/50 vertical split-screen layout
/// rather than Picture-in-Picture (PiP). This design choice provides equal visual
/// weight to both camera feeds and is well-suited for dual recording scenarios where
/// both perspectives are equally important (e.g., reaction videos, interviews, etc.).
///
/// The split-screen approach offers:
/// - Equal prominence for both camera feeds
/// - No obscured content (unlike PiP overlay)
/// - Clear visual separation between feeds
/// - Simpler layout calculations and rotation handling
///
/// A PiP layout can be implemented by modifying the frame calculations in
/// `layoutSubviews()` to position one preview layer as a smaller overlay in a corner.
class DualCameraPreviewView: UIView {

    // MARK: - Properties

    /// Front camera preview layer (top half)
    let frontPreviewLayer: AVCaptureVideoPreviewLayer

    /// Back camera preview layer (bottom half)
    let backPreviewLayer: AVCaptureVideoPreviewLayer

    /// Divider line between cameras
    private let dividerLine = CALayer()

    // MARK: - Initialization

    init() {
        // Create front camera preview (top half)
        frontPreviewLayer = AVCaptureVideoPreviewLayer()
        frontPreviewLayer.videoGravity = .resizeAspectFill

        // Create back camera preview (bottom half)
        backPreviewLayer = AVCaptureVideoPreviewLayer()
        backPreviewLayer.videoGravity = .resizeAspectFill

        super.init(frame: .zero)

        // Add layers in order: back, front, divider
        layer.addSublayer(backPreviewLayer)
        layer.addSublayer(frontPreviewLayer)
        layer.addSublayer(dividerLine)

        // Configure divider
        dividerLine.backgroundColor = UIColor.white.cgColor

        // Session will be set with manual connections in setupConnections()

        // Configure accessibility
        setupAccessibility()
    }

    private func setupAccessibility() {
        self.isAccessibilityElement = true
        self.accessibilityLabel = "Dual camera preview"
        self.accessibilityHint = "Shows front and back camera feeds simultaneously in split-screen"
        self.accessibilityTraits = .image
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()

        let midY = bounds.height / 2

        // Front camera takes top half
        frontPreviewLayer.frame = CGRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: midY
        )

        // Back camera takes bottom half
        backPreviewLayer.frame = CGRect(
            x: 0,
            y: midY,
            width: bounds.width,
            height: midY
        )

        // Divider line between them
        dividerLine.frame = CGRect(
            x: 0,
            y: midY - 1,
            width: bounds.width,
            height: 2
        )
    }

    // MARK: - Layers

    /// Get the back preview layer (used by CaptureService to setup connections)
    var getBackLayer: AVCaptureVideoPreviewLayer {
        return backPreviewLayer
    }

    /// Get the front preview layer (used by CaptureService to setup connections)
    var getFrontLayer: AVCaptureVideoPreviewLayer {
        return frontPreviewLayer
    }

}
