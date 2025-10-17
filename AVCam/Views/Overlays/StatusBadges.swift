/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
Status badges with Liquid Glass UI for camera features.
*/

import SwiftUI

/// Status badges showing active camera features
struct StatusBadges: View {
    let camera: Camera

    var body: some View {
        HStack(spacing: 8) {
            // HDR Badge
            if camera.isHDRVideoEnabled && camera.captureMode == .video {
                StatusBadge(icon: "hdr", text: "HDR", color: .yellow)
            }

            // Cinematic Mode Badge
            if camera.isCinematicVideoEnabled && camera.captureMode == .video {
                StatusBadge(icon: "sparkles", text: "Cinematic", color: .purple)
            }

            // Fast Capture Badge (Zero Shutter Lag)
            if camera.captureCapabilities.isResponsiveCaptureSupported && camera.captureMode == .photo {
                StatusBadge(icon: "bolt.fill", text: nil, color: .yellow)
                    .help("Fast capture enabled")
            }

            // Dual Camera Badge
            if camera.isMultiCamMode {
                StatusBadge(icon: "video.badge.plus", text: "Dual", color: .blue)
            }
        }
    }
}

/// Individual status badge with Liquid Glass design
struct StatusBadge: View {
    let icon: String
    let text: String?
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)

            if let text = text {
                Text(text)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial.opacity(0.8))
        .clipShape(Capsule())
        .glassEffect()
    }
}

#Preview("All Badges") {
    ZStack {
        Color.black
            .ignoresSafeArea()

        StatusBadges(camera: PreviewCameraModel())
            .padding()
    }
}

#Preview("Single Badge") {
    ZStack {
        Color.black
            .ignoresSafeArea()

        VStack(spacing: 16) {
            StatusBadge(icon: "hdr", text: "HDR", color: .yellow)
            StatusBadge(icon: "sparkles", text: "Cinematic", color: .purple)
            StatusBadge(icon: "bolt.fill", text: nil, color: .yellow)
            StatusBadge(icon: "video.badge.plus", text: "Dual", color: .blue)
        }
        .padding()
    }
}
