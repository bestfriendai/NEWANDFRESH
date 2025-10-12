/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A view that the app presents to indicate that Live Photo capture is active.
*/

import SwiftUI

/// A view that the app presents to indicate that Live Photo capture is active.
struct LiveBadge: View {
    var body: some View {
        Text("LIVE")
            .padding(6)
            .foregroundColor(.white)
            .font(.subheadline.bold())
            // Apply Liquid Glass effect (iOS 26 placeholder)
            .glassEffect(.regular, in: .rect(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.accentColor, lineWidth: 2)
            )
    }
}

#Preview {
    LiveBadge()
        .padding()
        .background(.black)
}

