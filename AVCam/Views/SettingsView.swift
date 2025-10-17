/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
A settings view with Liquid Glass UI for camera configuration.
*/

import SwiftUI

/// Settings view with Liquid Glass design for camera configuration
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var camera: CameraModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Photo Quality Section
                    if camera.captureMode == .photo {
                        photoQualitySection
                    }

                    // Video Features Section
                    if camera.captureMode == .video {
                        videoFeaturesSection
                    }

                    // Advanced Features Section
                    advancedFeaturesSection
                }
                .padding()
            }
            .background(.ultraThinMaterial.opacity(0.5))
            .navigationTitle("Camera Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .glassEffect()
                }
            }
        }
    }

    // MARK: - Photo Quality Section

    private var photoQualitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Photo Quality")
                .font(.headline)
                .foregroundStyle(.primary)

            Picker("Quality Prioritization", selection: $camera.qualityPrioritization) {
                Text("Speed").tag(QualityPrioritization.speed)
                Text("Balanced").tag(QualityPrioritization.balanced)
                Text("Quality").tag(QualityPrioritization.quality)
            }
            .pickerStyle(.segmented)
            .glassEffect()

            Text("Speed: Fastest capture, lower quality\nBalanced: Good mix of speed and quality\nQuality: Best image quality, slower capture")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Live Photos", isOn: $camera.isLivePhotoEnabled)
                .disabled(camera.isMultiCamMode)
                .glassEffect()

            if camera.isMultiCamMode {
                Text("Live Photos disabled in dual camera mode to reduce bandwidth")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .glassEffect()
    }

    // MARK: - Video Features Section

    private var videoFeaturesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Video Features")
                .font(.headline)
                .foregroundStyle(.primary)

            if camera.isHDRVideoSupported {
                Toggle("HDR Video", isOn: $camera.isHDRVideoEnabled)
                    .glassEffect()

                Text("Capture video with enhanced dynamic range")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if camera.isCinematicVideoSupported {
                HStack {
                    Toggle("Cinematic Mode", isOn: Binding(
                        get: { camera.isCinematicVideoEnabled },
                        set: { _ in
                            Task {
                                await camera.toggleCinematicVideo()
                            }
                        }
                    ))
                    .glassEffect()

                    if #available(iOS 26.0, *) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                    }
                }

                Text("Add depth-of-field effects during recording")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if #available(iOS 26.0, *) {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("Cinematic mode not available on this device")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
        }
        .padding()
        .background(.ultraThinMaterial.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .glassEffect()
    }

    // MARK: - Advanced Features Section

    private var advancedFeaturesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Advanced")
                .font(.headline)
                .foregroundStyle(.primary)

            // Performance Info
            if camera.captureCapabilities.isResponsiveCaptureSupported {
                HStack {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(.yellow)
                    Text("Fast Capture Enabled")
                        .font(.subheadline)
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .padding(.vertical, 8)
            }

            // Multi-camera info
            if camera.isMultiCamMode {
                HStack {
                    Image(systemName: "video.badge.plus")
                        .foregroundStyle(.blue)
                    Text("Dual Camera Active")
                        .font(.subheadline)
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .padding(.vertical, 8)
            }

            // Device capabilities
            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Device Capabilities")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                capabilityRow(
                    icon: "photo",
                    text: "Live Photos",
                    isSupported: camera.captureCapabilities.isLivePhotoCaptureSupported
                )

                capabilityRow(
                    icon: "video",
                    text: "HDR Video",
                    isSupported: camera.captureCapabilities.isHDRSupported
                )

                capabilityRow(
                    icon: "bolt",
                    text: "Responsive Capture",
                    isSupported: camera.captureCapabilities.isResponsiveCaptureSupported
                )

                if #available(iOS 26.0, *) {
                    capabilityRow(
                        icon: "sparkles",
                        text: "Cinematic Video",
                        isSupported: camera.captureCapabilities.isCinematicVideoSupported
                    )
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .glassEffect()
    }

    // MARK: - Helper Views

    private func capabilityRow(icon: String, text: String, isSupported: Bool) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(isSupported ? .green : .secondary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: isSupported ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(isSupported ? .green : .secondary)
        }
    }
}

#Preview {
    SettingsView(camera: PreviewCameraModel())
}
