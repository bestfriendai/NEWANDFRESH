import SwiftUI

struct PerformanceOverlay: View {
    let hardwareCost: Float
    let systemPressure: String

    var body: some View {
        #if DEBUG
        VStack(alignment: .leading, spacing: 4) {
            Text("Hardware Cost: \(String(format: "%.2f", hardwareCost))")
                .foregroundStyle(hardwareCost < 0.8 ? .green : hardwareCost < 1.0 ? .yellow : .red)
            Text("System Pressure: \(systemPressure)")
                .foregroundStyle(systemPressure == "nominal" ? .green : systemPressure == "fair" ? .yellow : .red)
        }
        .font(.caption2.monospaced())
        .foregroundStyle(.white)
        .padding(8)
        .glassEffect(.regular, in: .rect(cornerRadius: 8))
        .padding()
        #endif
    }
}

#Preview {
    ZStack {
        Color.black
        VStack {
            PerformanceOverlay(hardwareCost: 0.65, systemPressure: "nominal")
            PerformanceOverlay(hardwareCost: 0.95, systemPressure: "fair")
            PerformanceOverlay(hardwareCost: 1.2, systemPressure: "serious")
        }
    }
}
