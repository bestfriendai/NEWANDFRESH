/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
An object that retrieves camera and microphone devices.
*/

import AVFoundation
import Combine
import os

/// An object that retrieves camera and microphone devices.
final class DeviceLookup {
    private let logger = Logger(subsystem: "com.apple.avcam", category: "DeviceLookup")
    
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
        frontCameraDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInUltraWideCamera, .builtInTrueDepthCamera, .builtInWideAngleCamera],
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
            logger.error("No camera devices are found on this system.")
            // Return empty array instead of crashing - let UI handle gracefully
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
                .builtInUltraWideCamera,  // Add ultra-wide for front camera 0.5x
                .builtInWideAngleCamera,
                .builtInTrueDepthCamera
            ],
            mediaType: .video,
            position: .unspecified
        )

        // Get the SUPPORTED multi-cam device sets from Apple
        let supportedDeviceSets = discoverySession.supportedMultiCamDeviceSets

        logger.info("Found \(supportedDeviceSets.count) supported multi-cam device sets")
        for (index, deviceSet) in supportedDeviceSets.enumerated() {
            let deviceNames = deviceSet.map { "\($0.localizedName) (\($0.position.rawValue))" }.joined(separator: ", ")
            logger.debug("Set \(index): [\(deviceNames)]")
        }

        // Find a set with one back camera and one front camera
        // Prefer ultra-wide front camera for 0.5x wide view
        for deviceSet in supportedDeviceSets {
            let backDevices = deviceSet.filter { $0.position == .back }
            let frontDevices = deviceSet.filter { $0.position == .front }

            if let backCamera = backDevices.first,
               !frontDevices.isEmpty {
                // Prefer ultra-wide front camera for 0.5x view
                let frontCamera = frontDevices.first(where: { $0.deviceType == .builtInUltraWideCamera })
                                ?? frontDevices.first!

                logger.info("✨ Selected multi-cam pair: \(backCamera.localizedName) + \(frontCamera.localizedName)")
                if frontCamera.deviceType == .builtInUltraWideCamera {
                    logger.info("📐 Front camera: Ultra-Wide (0.5x) for wide view")
                }

                // Cache the result
                let pair = (back: backCamera, front: frontCamera)
                cachedMultiCamDevicePair = pair
                return pair
            }
        }

        logger.error("No back+front combination found in supported multi-cam device sets")
        return nil
    }

    // Cache for format selection to avoid repeated iterations
    private var formatCache: [String: AVCaptureDevice.Format] = [:]
    
    /// Selects optimal format for multi-cam capture with caching for performance
    /// For front camera, prioritizes widest field of view (FOV)
    func selectMultiCamFormat(for device: AVCaptureDevice, targetFPS: Int = 30) -> AVCaptureDevice.Format? {
        let cacheKey = "\(device.uniqueID)_\(targetFPS)"

        // Return cached format if available
        if let cached = formatCache[cacheKey] {
            return cached
        }

        let formats = device.formats.filter { $0.isMultiCamSupported }

        var selectedFormat: AVCaptureDevice.Format?

        // Special handling for front camera: prioritize widest FOV
        if device.position == .front {
            selectedFormat = selectWidestFOVFormat(from: formats, targetFPS: targetFPS)
            if selectedFormat != nil {
                logger.info("📐 Front camera: Selected widest FOV format")
            }
        }

        // If no format selected yet (back camera or front camera fallback)
        if selectedFormat == nil {
            // Per WWDC 2019: Prefer binned formats for lowest power consumption
            // Try to find binned 1280x720 @ 30fps first (best balance)

            // Priority 1: Binned 720p (lowest power, good quality)
            // Per WWDC 2019: Binned formats have lower resolution but much better power efficiency
            if let binned720p = formats.first(where: { format in
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                // Prefer 720p as it's commonly binned and good balance
                return dimensions.width == 1280 && dimensions.height == 720 &&
                       format.videoSupportedFrameRateRanges.contains { range in
                           range.maxFrameRate >= Double(targetFPS) && range.minFrameRate <= Double(targetFPS)
                       }
            }) {
                selectedFormat = binned720p
            }
            // Priority 2: Any binned format up to 1080p
            else if let binned = formats.first(where: { format in
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                return dimensions.width <= 1920 && dimensions.height <= 1080 &&
                       format.videoSupportedFrameRateRanges.contains { range in
                           range.maxFrameRate >= Double(targetFPS) && range.minFrameRate <= Double(targetFPS)
                       }
            }) {
                selectedFormat = binned
            }
            // Priority 3: Fallback to any format up to 1440p (for photo mode)
            else {
                selectedFormat = formats.first { format in
                    let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                    return dimensions.width <= 1920 && dimensions.height <= 1440 &&
                           format.videoSupportedFrameRateRanges.contains { range in
                               range.maxFrameRate >= Double(targetFPS) && range.minFrameRate <= Double(targetFPS)
                           }
                }
            }
        }

        // Cache the result
        if let format = selectedFormat {
            formatCache[cacheKey] = format
        }

        return selectedFormat
    }

    /// Selects the format with the widest field of view for front camera
    /// Prioritizes ultra-wide formats and larger sensor areas
    private func selectWidestFOVFormat(from formats: [AVCaptureDevice.Format], targetFPS: Int) -> AVCaptureDevice.Format? {
        // Filter formats that support the target FPS
        let validFormats = formats.filter { format in
            format.videoSupportedFrameRateRanges.contains { range in
                range.maxFrameRate >= Double(targetFPS) && range.minFrameRate <= Double(targetFPS)
            }
        }

        guard !validFormats.isEmpty else { return nil }

        // Sort by field of view (larger is wider)
        // videoFieldOfView is in degrees - higher value = wider FOV
        let sortedByFOV = validFormats.sorted { format1, format2 in
            format1.videoFieldOfView > format2.videoFieldOfView
        }

        // Log the widest FOV found
        if let widest = sortedByFOV.first {
            let dimensions = CMVideoFormatDescriptionGetDimensions(widest.formatDescription)
            logger.info("📐 Widest FOV: \(widest.videoFieldOfView)° at \(dimensions.width)x\(dimensions.height)")
        }

        return sortedByFOV.first
    }
}
