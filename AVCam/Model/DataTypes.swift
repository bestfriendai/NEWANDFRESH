/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Supporting data types for the app.
*/

import AVFoundation

// MARK: - Supporting types

/// An enumeration that describes the current status of the camera.
enum CameraStatus {
    /// The initial status upon creation.
    case unknown
    /// A status that indicates a person disallows access to the camera or microphone.
    case unauthorized
    /// A status that indicates the camera failed to start.
    case failed
    /// A status that indicates the camera is successfully running.
    case running
    /// A status that indicates higher-priority media processing is interrupting the camera.
    case interrupted
}

/// An enumeration that defines the activity states the capture service supports.
///
/// This type provides feedback to the UI regarding the active status of the `CaptureService` actor.
enum CaptureActivity {
    case idle
    /// A status that indicates the capture service is performing photo capture.
    case photoCapture(willCapture: Bool = false, isLivePhoto: Bool = false, isProcessing: Bool = false)
    /// A status that indicates the capture service is performing movie capture.
    case movieCapture(duration: TimeInterval = 0.0)

    var isLivePhoto: Bool {
        if case .photoCapture(_, let isLivePhoto, _) = self {
            return isLivePhoto
        }
        return false
    }

    var willCapture: Bool {
        if case .photoCapture(let willCapture, _, _) = self {
            return willCapture
        }
        return false
    }

    var isProcessing: Bool {
        if case .photoCapture(_, _, let isProcessing) = self {
            return isProcessing
        }
        return false
    }

    var currentTime: TimeInterval {
        if case .movieCapture(let duration) = self {
            return duration
        }
        return .zero
    }

    var isRecording: Bool {
        if case .movieCapture(_) = self {
            return true
        }
        return false
    }
}

/// An enumeration of the capture modes that the camera supports.
enum CaptureMode: String, Identifiable, CaseIterable, Codable {
    var id: Self { self }
    /// A mode that enables photo capture.
    case photo
    /// A mode that enables video capture.
    case video
    
    var systemName: String {
        switch self {
        case .photo:
            "camera.fill"
        case .video:
            "video.fill"
        }
    }
}

/// A structure that represents a captured photo.
struct Photo: Sendable {
    let data: Data
    let isProxy: Bool
    let livePhotoMovieURL: URL?
    /// For dual camera: back camera photo data
    let backData: Data?
    /// For dual camera: front camera photo data
    let frontData: Data?
}

/// A structure that contains the uniform type identifier and movie URL.
struct Movie: Sendable {
    /// The temporary location of the file on disk.
    let url: URL
    /// For dual camera: back camera video URL
    let backURL: URL?
    /// For dual camera: front camera video URL
    let frontURL: URL?
}

struct PhotoFeatures {
    let isLivePhotoEnabled: Bool
    let qualityPrioritization: QualityPrioritization
}

/// A structure that represents the capture capabilities of `CaptureService` in
/// its current configuration.
struct CaptureCapabilities {

    let isLivePhotoCaptureSupported: Bool
    let isHDRSupported: Bool
    let isResponsiveCaptureSupported: Bool
    let isCinematicVideoSupported: Bool

    init(isLivePhotoCaptureSupported: Bool = false,
         isHDRSupported: Bool = false,
         isResponsiveCaptureSupported: Bool = false,
         isCinematicVideoSupported: Bool = false) {
        self.isLivePhotoCaptureSupported = isLivePhotoCaptureSupported
        self.isHDRSupported = isHDRSupported
        self.isResponsiveCaptureSupported = isResponsiveCaptureSupported
        self.isCinematicVideoSupported = isCinematicVideoSupported
    }

    static let unknown = CaptureCapabilities()
}

enum QualityPrioritization: Int, Identifiable, CaseIterable, CustomStringConvertible, Codable {
    var id: Self { self }
    case speed = 1
    case balanced
    case quality
    var description: String {
        switch self {
        case.speed:
            return "Speed"
        case .balanced:
            return "Balanced"
        case .quality:
            return "Quality"
        }
    }
}

enum CameraError: LocalizedError {
    case videoDeviceUnavailable
    case audioDeviceUnavailable
    case addInputFailed
    case addOutputFailed
    case setupFailed
    case deviceChangeFailed
    case multiCamNotSupported
    case hardwareCostExceeded(cost: Float)
    case connectionFailed
    case configurationFailed

    var errorDescription: String? {
        switch self {
        case .videoDeviceUnavailable:
            return "Camera Unavailable"
        case .audioDeviceUnavailable:
            return "Microphone Unavailable"
        case .addInputFailed:
            return "Failed to Add Camera Input"
        case .addOutputFailed:
            return "Failed to Configure Camera Output"
        case .setupFailed:
            return "Camera Setup Failed"
        case .deviceChangeFailed:
            return "Failed to Switch Camera"
        case .multiCamNotSupported:
            return "Dual Camera Not Supported"
        case .hardwareCostExceeded(let cost):
            return "Multi-Camera Requires Too Much Processing Power"
        case .connectionFailed:
            return "Failed to Connect Camera"
        case .configurationFailed:
            return "Camera Configuration Failed"
        }
    }

    var failureReason: String? {
        switch self {
        case .videoDeviceUnavailable:
            return "The camera device is not available or is being used by another app."
        case .audioDeviceUnavailable:
            return "The microphone is not available or is being used by another app."
        case .addInputFailed:
            return "The camera input could not be added to the capture session."
        case .addOutputFailed:
            return "The camera output could not be configured properly."
        case .setupFailed:
            return "The camera could not be initialized with the current settings."
        case .deviceChangeFailed:
            return "The camera device could not be switched at this time."
        case .multiCamNotSupported:
            return "Your device doesn't support dual camera capture. Requires iPhone XS or newer."
        case .hardwareCostExceeded(let cost):
            return "Dual camera requires hardware cost of \(String(format: "%.2f", cost)), which exceeds the 1.0 limit. The camera system cannot handle this configuration."
        case .connectionFailed:
            return "The camera connection could not be established."
        case .configurationFailed:
            return "The camera could not be configured with the requested settings."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .videoDeviceUnavailable:
            return "Close other apps using the camera and try again."
        case .audioDeviceUnavailable:
            return "Close other apps using the microphone and try again."
        case .addInputFailed, .addOutputFailed, .connectionFailed:
            return "Restart the app and try again."
        case .setupFailed, .configurationFailed:
            return "Try restarting the app or your device."
        case .deviceChangeFailed:
            return "Wait a moment and try switching cameras again."
        case .multiCamNotSupported:
            return "Use single camera mode on this device."
        case .hardwareCostExceeded:
            return "Try using lower resolution settings or single camera mode."
        }
    }
}

protocol OutputService {
    associatedtype Output: AVCaptureOutput
    var output: Output { get }
    var captureActivity: CaptureActivity { get }
    var capabilities: CaptureCapabilities { get }
    func updateConfiguration(for device: AVCaptureDevice)
    func setVideoRotationAngle(_ angle: CGFloat)
}

extension OutputService {
    func setVideoRotationAngle(_ angle: CGFloat) {
        // Set the rotation angle on the output object's video connection.
        output.connection(with: .video)?.videoRotationAngle = angle
    }
    func updateConfiguration(for device: AVCaptureDevice) {}
}
