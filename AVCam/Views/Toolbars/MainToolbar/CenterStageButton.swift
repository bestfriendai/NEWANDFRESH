/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
A button that toggles Center Stage on/off for the front camera.
*/

import SwiftUI

struct CenterStageButton<CameraModel: Camera>: View {
    
    @State var camera: CameraModel
    
    var body: some View {
        Button {
            Task {
                await camera.toggleCenterStage()
            }
        } label: {
            Image(systemName: camera.isCenterStageEnabled ? "person.crop.rectangle.fill" : "person.crop.rectangle")
                .font(.title2)
                .foregroundStyle(camera.isCenterStageEnabled ? .blue : .white)
        }
        .buttonStyle(.plain)
        .disabled(!camera.isCenterStageSupported || !camera.isMultiCamMode)
        .opacity(camera.isCenterStageSupported && camera.isMultiCamMode ? 1.0 : 0.3)
        .accessibilityLabel("Center Stage")
        .accessibilityHint(camera.isCenterStageEnabled ? "Tap to disable Center Stage" : "Tap to enable Center Stage")
        .accessibilityAddTraits(.isButton)
    }
}

