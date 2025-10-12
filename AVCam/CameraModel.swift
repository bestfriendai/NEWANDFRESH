/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
An object that provides the interface to the features of the camera.
*/

import SwiftUI
import Combine
import AVFoundation

/// An object that provides the interface to the features of the camera.
///
/// This object provides the default implementation of the `Camera` protocol, which defines the interface
/// to configure the camera hardware and capture media. `CameraModel` doesn't perform capture itself, but is an
/// `@Observable` type that mediates interactions between the app's SwiftUI views and `CaptureService`.
///
/// For SwiftUI previews and Simulator, the app uses `PreviewCameraModel` instead.
///
@MainActor
@Observable
final class CameraModel: Camera {
    
    /// The current status of the camera, such as unauthorized, running, or failed.
    private(set) var status = CameraStatus.unknown
    
    /// The current state of photo or movie capture.
    private(set) var captureActivity = CaptureActivity.idle
    
    /// A Boolean value that indicates whether the app is currently switching video devices.
    private(set) var isSwitchingVideoDevices = false
    
    /// A Boolean value that indicates whether the camera prefers showing a minimized set of UI controls.
    private(set) var prefersMinimizedUI = false
    
    /// A Boolean value that indicates whether the app is currently switching capture modes.
    private(set) var isSwitchingModes = false
    
    /// A Boolean value that indicates whether to show visual feedback when capture begins.
    private(set) var shouldFlashScreen = false
    
    /// A thumbnail for the last captured photo or video.
    private(set) var thumbnail: CGImage?
    
    /// An error that indicates the details of an error during photo or movie capture.
    private(set) var error: Error?

    /// An object that provides the connection between the capture session and the video preview layer.
    var previewSource: PreviewSource { captureService.previewSource }

    // MARK: - Multi-Camera Properties

    /// A Boolean value that indicates whether the camera is in multi-camera mode.
    private(set) var isMultiCamMode: Bool = false

    /// A Boolean value that indicates whether dual camera recording is active.
    private(set) var isDualRecording = false

    /// The AVCaptureSession instance for preview connections.
    var captureSession: AVCaptureSession {
        captureService.captureSession
    }

    /// The back camera preview port for dual preview connections.
    private(set) var backVideoPort: AVCaptureInput.Port?

    /// The front camera preview port for dual preview connections.
    private(set) var frontVideoPort: AVCaptureInput.Port?

    /// A Boolean that indicates whether the camera supports HDR video recording.
    private(set) var isHDRVideoSupported = false

    /// An object that saves captured media to a person's Photos library.
    private let mediaLibrary = MediaLibrary()
    
    /// An object that manages the app's capture functionality.
    private let captureService = CaptureService()
    
    /// Persistent state shared between the app and capture extension.
    private var cameraState = CameraState()
    
    init() {
        //
    }
    
    // MARK: - Starting the camera
    /// Start the camera and begin the stream of data.
    func start() async {
        // Verify that the person authorizes the app to use device cameras and microphones.
        guard await captureService.isAuthorized else {
            status = .unauthorized
            return
        }
        do {
            // Synchronize the state of the model with the persistent state.
            await syncState()
            // Start the capture service to start the flow of data.
            try await captureService.start(with: cameraState)
            // Update multi-cam state
            await updateMultiCamState()
            observeState()
            status = .running
        } catch {
            logger.error("Failed to start capture service. \(error)")
            status = .failed
        }
    }

    /// Updates the multi-camera state from the capture service
    private func updateMultiCamState() async {
        isMultiCamMode = await captureService.isMultiCamMode
        if isMultiCamMode {
            backVideoPort = await captureService.backCameraPreviewPort
            frontVideoPort = await captureService.frontCameraPreviewPort
        }
    }
    
    /// Synchronizes the persistent camera state.
    ///
    /// `CameraState` represents the persistent state, such as the capture mode, that the app and extension share.
    func syncState() async {
        cameraState = await CameraState.current
        captureMode = cameraState.captureMode
        qualityPrioritization = cameraState.qualityPrioritization
        isLivePhotoEnabled = cameraState.isLivePhotoEnabled
        isHDRVideoEnabled = cameraState.isVideoHDREnabled
    }
    
    // MARK: - Changing modes and devices
    
    /// A value that indicates the mode of capture for the camera.
    var captureMode = CaptureMode.photo {
        didSet {
            guard status == .running else { return }
            Task {
                isSwitchingModes = true
                defer { isSwitchingModes = false }
                // Update the configuration of the capture service for the new mode.
                try? await captureService.setCaptureMode(captureMode)
                // Update the persistent state value.
                cameraState.captureMode = captureMode
            }
        }
    }
    
    /// Selects the next available video device for capture.
    func switchVideoDevices() async {
        isSwitchingVideoDevices = true
        defer { isSwitchingVideoDevices = false }
        await captureService.selectNextVideoDevice()
    }
    
    // MARK: - Photo capture
    
    /// Captures a photo and writes it to the user's Photos library.
    func capturePhoto() async {
        do {
            let photoFeatures = PhotoFeatures(isLivePhotoEnabled: isLivePhotoEnabled, qualityPrioritization: qualityPrioritization)
            let photo = try await captureService.capturePhoto(with: photoFeatures)
            try await mediaLibrary.save(photo: photo)
        } catch {
            self.error = error
        }
    }
    
    /// A Boolean value that indicates whether to capture Live Photos when capturing stills.
    var isLivePhotoEnabled = true {
        didSet {
            // Update the persistent state value.
            cameraState.isLivePhotoEnabled = isLivePhotoEnabled
        }
    }
    
    /// A value that indicates how to balance the photo capture quality versus speed.
    var qualityPrioritization = QualityPrioritization.quality {
        didSet {
            // Update the persistent state value.
            cameraState.qualityPrioritization = qualityPrioritization
        }
    }
    
    /// Performs a focus and expose operation at the specified screen point.
    func focusAndExpose(at point: CGPoint) async {
        await captureService.focusAndExpose(at: point)
    }
    
    /// Sets the `showCaptureFeedback` state to indicate that capture is underway.
    private func flashScreen() {
        shouldFlashScreen = true
        withAnimation(.linear(duration: 0.01)) {
            shouldFlashScreen = false
        }
    }
    
    // MARK: - Video capture
    /// A Boolean value that indicates whether the camera captures video in HDR format.
    var isHDRVideoEnabled = false {
        didSet {
            guard status == .running, captureMode == .video else { return }
            Task {
                await captureService.setHDRVideoEnabled(isHDRVideoEnabled)
                // Update the persistent state value.
                cameraState.isVideoHDREnabled = isHDRVideoEnabled
            }
        }
    }
    
    /// Toggles the state of recording.
    func toggleRecording() async {
        switch await captureService.captureActivity {
        case .movieCapture:
            do {
                // If currently recording, stop the recording and write the movie to the library.
                let movie = try await captureService.stopRecording()
                try await mediaLibrary.save(movie: movie)
            } catch {
                self.error = error
            }
        default:
            // In any other case, start recording.
            await captureService.startRecording()
        }
    }

    // MARK: - Multi-Camera Support

    /// Starts dual camera recording with haptic feedback.
    func startDualRecording() async {
        // Haptic feedback
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        #endif

        do {
            _ = try await captureService.startDualRecording()
            isDualRecording = true
            logger.info("Started dual camera recording")
        } catch {
            logger.error("Failed to start dual recording: \(error.localizedDescription)")
            self.error = error
        }
    }

    /// Stops dual camera recording with haptic feedback.
    func stopDualRecording() async {
        // Haptic feedback
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        #endif

        do {
            let outputURL = try await captureService.stopDualRecording()
            isDualRecording = false

            // Save to photo library
            try await mediaLibrary.save(movie: Movie(url: outputURL))
            logger.info("Stopped dual recording, saved to library")
        } catch {
            logger.error("Failed to stop dual recording: \(error.localizedDescription)")
            self.error = error
        }
    }

    /// Setup preview layer connections for dual camera mode
    func setupDualPreviewConnections(backLayer: AVCaptureVideoPreviewLayer, frontLayer: AVCaptureVideoPreviewLayer) async {
        do {
            try await captureService.setupPreviewConnections(backLayer: backLayer, frontLayer: frontLayer)
            logger.info("Dual preview connections setup successfully")
        } catch {
            logger.error("Failed to setup dual preview connections: \(error.localizedDescription)")
            self.error = error
        }
    }

    // MARK: - Internal state observations

    // Set up camera's state observations.
    private func observeState() {
        Task {
            // Await new thumbnails that the media library generates when saving a file.
            for await thumbnail in mediaLibrary.thumbnails.compactMap({ $0 }) {
                self.thumbnail = thumbnail
            }
        }
        
        Task {
            // Await new capture activity values from the capture service.
            for await activity in await captureService.$captureActivity.values {
                if activity.willCapture {
                    // Flash the screen to indicate capture is starting.
                    flashScreen()
                } else {
                    // Forward the activity to the UI.
                    captureActivity = activity
                }
            }
        }
        
        Task {
            // Await updates to the capabilities that the capture service advertises.
            for await capabilities in await captureService.$captureCapabilities.values {
                isHDRVideoSupported = capabilities.isHDRSupported
                cameraState.isVideoHDRSupported = capabilities.isHDRSupported
            }
        }
        
        Task {
            // Await updates to a person's interaction with the Camera Control HUD.
            for await isShowingFullscreenControls in await captureService.$isShowingFullscreenControls.values {
                withAnimation {
                    // Prefer showing a minimized UI when capture controls enter a fullscreen appearance.
                    prefersMinimizedUI = isShowingFullscreenControls
                }
            }
        }
    }
}
