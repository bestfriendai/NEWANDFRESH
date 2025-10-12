/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
An object that retrieves camera and microphone devices.
*/

import AVFoundation
import Combine

/// An object that retrieves camera and microphone devices.
final class DeviceLookup {
    
    // Discovery sessions to find the front and back cameras, and external cameras in iPadOS.
    private let frontCameraDiscoverySession: AVCaptureDevice.DiscoverySession
    private let backCameraDiscoverySession: AVCaptureDevice.DiscoverySession
    private let externalCameraDiscoverSession: AVCaptureDevice.DiscoverySession

    // Cache the multi-cam device pair to avoid repeated queries
    private var cachedMultiCamDevicePair: (back: AVCaptureDevice, front: AVCaptureDevice)?

    init() {
        backCameraDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInDualCamera, .builtInWideAngleCamera],
                                                                      mediaType: .video,
                                                                      position: .back)
        frontCameraDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInTrueDepthCamera, .builtInWideAngleCamera],
                                                                       mediaType: .video,
                                                                       position: .front)
        externalCameraDiscoverSession = AVCaptureDevice.DiscoverySession(deviceTypes: [.external],
                                                                         mediaType: .video,
                                                                         position: .unspecified)
        
        // If the host doesn't currently define a system-preferred camera device, set the user's preferred selection to the back camera.
        if AVCaptureDevice.systemPreferredCamera == nil {
            AVCaptureDevice.userPreferredCamera = backCameraDiscoverySession.devices.first
        }
    }
    
    /// Returns the system-preferred camera for the host system.
    var defaultCamera: AVCaptureDevice {
        get throws {
            guard let videoDevice = AVCaptureDevice.systemPreferredCamera else {
                throw CameraError.videoDeviceUnavailable
            }
            return videoDevice
        }
    }
    
    /// Returns the default microphone for the device on which the app runs.
    var defaultMic: AVCaptureDevice {
        get throws {
            guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
                throw CameraError.audioDeviceUnavailable
            }
            return audioDevice
        }
    }
    
    var cameras: [AVCaptureDevice] {
        // Populate the cameras array with the available cameras.
        var cameras: [AVCaptureDevice] = []
        if let backCamera = backCameraDiscoverySession.devices.first {
            cameras.append(backCamera)
        }
        if let frontCamera = frontCameraDiscoverySession.devices.first {
            cameras.append(frontCamera)
        }
        // iPadOS supports connecting external cameras.
        if let externalCamera = externalCameraDiscoverSession.devices.first {
            cameras.append(externalCamera)
        }

#if !targetEnvironment(simulator)
        if cameras.isEmpty {
            fatalError("No camera devices are found on this system.")
        }
#endif
        return cameras
    }

    /// Returns a pair of cameras suitable for multi-cam capture (back + front)
    var multiCamDevicePair: (back: AVCaptureDevice, front: AVCaptureDevice)? {
        // Return cached pair if available
        if let cached = cachedMultiCamDevicePair {
            return cached
        }

        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            return nil
        }

        // Use the discovery session to get supported multi-cam device sets
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInTripleCamera,
                .builtInDualWideCamera,
                .builtInDualCamera,
                .builtInWideAngleCamera,
                .builtInTrueDepthCamera
            ],
            mediaType: .video,
            position: .unspecified
        )

        // Get the SUPPORTED multi-cam device sets from Apple
        let supportedDeviceSets = discoverySession.supportedMultiCamDeviceSets

        print("📱 Found \(supportedDeviceSets.count) supported multi-cam device sets")
        for (index, deviceSet) in supportedDeviceSets.enumerated() {
            let deviceNames = deviceSet.map { "\($0.localizedName) (\($0.position.rawValue))" }.joined(separator: ", ")
            print("  Set \(index): [\(deviceNames)]")
        }

        // Find a set with one back camera and one front camera
        for deviceSet in supportedDeviceSets {
            let backDevices = deviceSet.filter { $0.position == .back }
            let frontDevices = deviceSet.filter { $0.position == .front }

            if let backCamera = backDevices.first,
               let frontCamera = frontDevices.first {
                print("✅ Selected: \(backCamera.localizedName) + \(frontCamera.localizedName)")
                // Cache the result
                let pair = (back: backCamera, front: frontCamera)
                cachedMultiCamDevicePair = pair
                return pair
            }
        }

        print("❌ No back+front combination found in supported sets")
        return nil
    }

    /// Selects optimal format for multi-cam capture
    func selectMultiCamFormat(for device: AVCaptureDevice, targetFPS: Int = 30) -> AVCaptureDevice.Format? {
        let formats = device.formats.filter { $0.isMultiCamSupported }

        // Try to find 1280x720 @ 30fps (good balance of quality and performance)
        if let preferred = formats.first(where: { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return dimensions.width == 1280 && dimensions.height == 720 &&
                   format.videoSupportedFrameRateRanges.contains { range in
                       range.maxFrameRate >= Double(targetFPS) && range.minFrameRate <= Double(targetFPS)
                   }
        }) {
            return preferred
        }

        // Fallback: any format up to 1080p at target FPS
        return formats.first { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return dimensions.width <= 1920 && dimensions.height <= 1440 &&
                   format.videoSupportedFrameRateRanges.contains { range in
                       range.maxFrameRate >= Double(targetFPS) && range.minFrameRate <= Double(targetFPS)
                   }
        }
    }
}
