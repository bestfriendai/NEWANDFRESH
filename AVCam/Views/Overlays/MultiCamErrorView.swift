import SwiftUI

struct MultiCamErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.yellow)

            Text("Multi-Camera Not Available")
                .font(.headline)
                .foregroundStyle(.white)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Switch to Single Camera") {
                retry()
            }
            .buttonStyle(.borderedProminent)
            .glassEffect(.regular, in: .capsule)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.8))
    }
}

#Preview {
    MultiCamErrorView(message: "This device does not support multi-camera capture. Requires iPhone XS or later.") {
        print("Retry tapped")
    }
}
