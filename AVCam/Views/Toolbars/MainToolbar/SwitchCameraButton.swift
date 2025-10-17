/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A view that displays a button to switch between available cameras.
*/

import SwiftUI

/// A view that displays a button to switch between available cameras.
struct SwitchCameraButton<CameraModel: Camera>: View {
    
    @State var camera: CameraModel
    
    var body: some View {
        Button {
            Task {
                await camera.switchVideoDevices()
            }
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
        }
        .buttonStyle(DefaultButtonStyle(size: .large))
        .frame(width: largeButtonSize.width, height: largeButtonSize.height)
        .glassEffect(.regular, in: .circle)
        .disabled(camera.captureActivity.isRecording || camera.isMultiCamMode)
        .allowsHitTesting(!camera.isSwitchingVideoDevices && !camera.isMultiCamMode)
        .opacity(camera.isMultiCamMode ? 0.5 : 1.0)
    }
}
