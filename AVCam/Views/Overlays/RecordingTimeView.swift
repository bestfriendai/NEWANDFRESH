/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A view that displays the current recording time.
*/

import SwiftUI

/// A view that displays the current recording time.
struct RecordingTimeView: PlatformView {

    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    let time: TimeInterval
    
    var body: some View {
        HStack(spacing: 8) {
            // Recording indicator dot
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)

            Text(time.formatted)
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, isRegularSize ? 8 : 6)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recording time: \(time.formatted)")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

extension TimeInterval {
    var formatted: String {
        let time = Int(self)
        let seconds = time % 60
        let minutes = (time / 60) % 60
        let hours = (time / 3600)
        let formatString = "%0.2d:%0.2d:%0.2d"
        return String(format: formatString, hours, minutes, seconds)
    }
}

#Preview {
    RecordingTimeView(time: TimeInterval(floatLiteral: 500))
        .background(Image("video_mode"))
}
