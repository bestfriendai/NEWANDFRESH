/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
A button to open camera settings with Liquid Glass UI.
*/

import SwiftUI

/// Settings button with Liquid Glass design
struct SettingsButton: View {
    @State private var showSettings = false

    var body: some View {
        Button {
            showSettings = true
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial.opacity(0.8))
                .clipShape(Circle())
                .glassEffect()
        }
        .accessibilityLabel("Settings")
        .accessibilityHint("Open camera settings")
        .sheet(isPresented: $showSettings) {
            // Settings view will be presented here
            // Note: Need to pass camera model from parent
            Text("Settings")
        }
    }
}

#Preview {
    ZStack {
        Color.black
            .ignoresSafeArea()

        SettingsButton()
            .padding()
    }
}
