import SwiftUI

struct MultiCamBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "camera.fill")
                .font(.caption2)
            Image(systemName: "camera.fill")
                .font(.caption2)
            Text("DUAL")
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .glassEffect(.regular, in: .capsule)
    }
}

#Preview {
    ZStack {
        Color.blue
        MultiCamBadge()
    }
}
