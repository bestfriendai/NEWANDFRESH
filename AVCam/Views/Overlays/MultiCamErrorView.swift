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

// MARK: - Thermal Warning View

/// A view that warns the user about thermal pressure
struct ThermalWarningView: View {
    let level: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "thermometer.sun.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            Text("Device Temperature High")
                .font(.headline)
                .foregroundStyle(.white)

            Text(warningMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .shadow(color: .black.opacity(0.3), radius: 10)
    }

    var warningMessage: String {
        switch level {
        case "serious":
            return "Performance has been reduced to cool down the device. Consider reducing usage or moving to a cooler environment."
        case "critical":
            return "Device is critically hot. Recording performance significantly reduced. Please stop and allow device to cool."
        case "shutdown":
            return "Device temperature too high. Recording has been stopped to prevent damage."
        default:
            return "Device temperature elevated."
        }
    }
}
