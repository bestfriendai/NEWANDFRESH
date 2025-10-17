/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A view that presents the main camera user interface.
*/

import SwiftUI
import AVFoundation

/// A view that presents the main camera user interface.
struct CameraUI<CameraModel: Camera>: PlatformView {

    @State var camera: CameraModel
    @Binding var swipeDirection: SwipeDirection
    
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    var body: some View {
        Group {
            if isRegularSize {
                regularUI
            } else {
                compactUI
            }
        }
        .overlay(alignment: .top) {
            switch camera.captureMode {
            case .photo:
                LiveBadge()
                    .opacity(camera.captureActivity.isLivePhoto ? 1.0 : 0.0)
            case .video:
                // Show recording timer for both single-cam and multi-cam recording
                // Using explicit animation to reduce redraws
                if camera.captureActivity.isRecording || camera.isDualRecording {
                    RecordingTimeView(time: camera.captureActivity.currentTime)
                        .offset(y: isRegularSize ? 20 : 0)
                        .id("recordingTimer")
                }
            }
        }
        .overlay(alignment: .topLeading) {
            // Status badges showing active features
            StatusBadges(camera: camera)
                .padding(.top, isRegularSize ? 60 : 50)
                .padding(.leading, 16)
        }
        .overlay(alignment: .topTrailing) {
            // Settings button
            SettingsButton()
                .padding(.top, isRegularSize ? 60 : 50)
                .padding(.trailing, 16)
        }
        .overlay {
            StatusOverlayView(status: camera.status)
        }
        .overlay {
            // Deferred photo processing indicator
            if case .photoCapture(_, _, let isProcessing) = camera.captureActivity, isProcessing {
                VStack {
                    Spacer()
                    HStack {
                        ProgressView()
                            .tint(.white)
                        Text("Processing photo...")
                            .font(.caption)
                            .foregroundStyle(.white)
                    }
                    .padding()
                    .background(.ultraThinMaterial.opacity(0.8))
                    .clipShape(Capsule())
                    .glassEffect()
                    Spacer()
                }
            }
        }
    }
    
    /// This view arranges UI elements vertically.
    @ViewBuilder
    var compactUI: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                FeaturesToolbar(camera: camera)
                Spacer()
                CaptureModeView(camera: camera, direction: $swipeDirection)
                MainToolbar(camera: camera)
                    .padding(.bottom, bottomPadding(for: geometry.size))
            }
        }
    }
    
    /// This view arranges UI elements in a layered stack.
    @ViewBuilder
    var regularUI: some View {
        VStack {
            Spacer()
            ZStack {
                CaptureModeView(camera: camera, direction: $swipeDirection)
                    .offset(x: -250) // The vertical offset from center.
                MainToolbar(camera: camera)
                FeaturesToolbar(camera: camera)
                    .frame(width: 250)
                    .offset(x: 250) // The vertical offset from center.
            }
            .frame(width: 740)
            // Apply Liquid Glass effect (iOS 26 placeholder)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
            .padding(.bottom, 32)
        }
    }
    
    var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 50)
            .onEnded {
                // Capture the swipe direction.
                swipeDirection = $0.translation.width < 0 ? .left : .right
            }
    }
    
    func bottomPadding(for size: CGSize) -> CGFloat {
        // Dynamically calculate the offset for the bottom toolbar in iOS.
        let bounds = CGRect(origin: .zero, size: size)
        let rect = AVMakeRect(aspectRatio: movieAspectRatio, insideRect: bounds)
        return (rect.minY.rounded() / 2) + 12
    }
}

#Preview {
    CameraUI(camera: PreviewCameraModel(), swipeDirection: .constant(.left))
}
