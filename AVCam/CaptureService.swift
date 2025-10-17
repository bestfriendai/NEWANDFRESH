/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
An object that manages a capture session and its inputs and outputs.
*/

import Foundation
@preconcurrency import AVFoundation
import Combine
import CoreImage
import UIKit

/// An actor that manages the capture pipeline, which includes the capture session, device inputs, and capture outputs.
/// The app defines it as an `actor` type to ensure that all camera operations happen off of the `@MainActor`.
actor CaptureService {

    /// A value that indicates whether the capture service is idle or capturing a photo or movie.
    @Published private(set) var captureActivity: CaptureActivity = .idle
    /// A value that indicates the current capture capabilities of the service.
    @Published private(set) var captureCapabilities = CaptureCapabilities.unknown
    /// A Boolean value that indicates whether a higher priority event, like receiving a phone call, interrupts the app.
    @Published private(set) var isInterrupted = false
    /// A Boolean value that indicates whether the user enables HDR video capture.
    @Published var isHDRVideoEnabled = false
    /// A Boolean value that indicates whether capture controls are in a fullscreen appearance.
    @Published var isShowingFullscreenControls = false
    /// A Boolean value that indicates whether cinematic video mode is enabled (iOS 26+).
    @Published private(set) var isCinematicVideoEnabled = false
    /// A Boolean value that indicates whether cinematic video is supported on the current device.
    @Published private(set) var isCinematicVideoSupported = false
    /// An optional error message explaining why multi-cam is unavailable/fallback occurred.
    @Published private(set) var multiCamErrorMessage: String?
    /// Current thermal level string (nominal/fair/serious/critical/shutdown)
    @Published private(set) var thermalLevel: String?
    /// Audio route information for diagnostics
    @Published private(set) var audioRouteDescription: String?


    /// A type that connects a preview destination with the capture session.
    nonisolated let previewSource: PreviewSource

    // The app's capture session.
    nonisolated let captureSession: AVCaptureSession

    // Indicates whether the service is running in multi-camera mode
    private(set) var isMultiCamMode: Bool = false

    // An object that manages the app's photo capture behavior.
    private let photoCapture = PhotoCapture()

    // An object that manages the app's video capture behavior.
    private let movieCapture = MovieCapture()

    // An internal collection of output services.
    private var outputServices: [any OutputService] { [photoCapture, movieCapture] }

    // The video input for the currently selected device camera.
    private var activeVideoInput: AVCaptureDeviceInput?

    // Multi-camera specific properties
    private var backCameraDevice: AVCaptureDevice?
    private var frontCameraDevice: AVCaptureDevice?
    private var backVideoInput: AVCaptureDeviceInput?
    private var frontVideoInput: AVCaptureDeviceInput?

    // Center Stage support for front camera
    @Published private(set) var isCenterStageSupported = false
    @Published private(set) var isCenterStageEnabled = false

    // Separate outputs for each camera
    fileprivate var backVideoOutput: AVCaptureVideoDataOutput?
    fileprivate var frontVideoOutput: AVCaptureVideoDataOutput?

    // Photo outputs for dual camera
    private var backPhotoOutput: AVCapturePhotoOutput?
    private var frontPhotoOutput: AVCapturePhotoOutput?

    // Output queues
    private let backVideoQueue = DispatchQueue(label: "com.apple.avcam.backVideoQueue", qos: .userInitiated)
    private let frontVideoQueue = DispatchQueue(label: "com.apple.avcam.frontVideoQueue", qos: .userInitiated)

    // Recording
    fileprivate var dualRecorder: DualMovieRecorder?
    private var synchronizer: AVCaptureDataOutputSynchronizer?
    private let synchronizerQueue = DispatchQueue(label: "com.apple.avcam.synchronizer", qos: .userInitiated)
    private let audioQueue = DispatchQueue(label: "com.apple.avcam.audio", qos: .userInitiated)
    private var audioOutput: AVCaptureAudioDataOutput?
    private var dualRecordingDelegate: DualRecordingDelegate?

    // The mode of capture, either photo or video. Defaults to photo.
    private(set) var captureMode = CaptureMode.photo

    // An object the service uses to retrieve capture devices.
    private let deviceLookup = DeviceLookup()

    // An object that monitors the state of the system-preferred camera.
    private let systemPreferredCamera = SystemPreferredCameraObserver()

    // An object that monitors video device rotations (single camera).
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    // Rotation coordinators for multi-camera (per device)
    private var backRotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var frontRotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservers = [AnyObject]()
    private var systemPressureObservers = [AnyObject]()

    // A Boolean value that indicates whether the actor finished its required configuration.
    private var isSetUp = false

    // A delegate object that responds to capture control activation and presentation events.
    private var controlsDelegate = CaptureControlsDelegate()

    // A map that stores capture controls by device identifier.
    private var controlsMap: [String: [AVCaptureControl]] = [:]

    // A serial dispatch queue to use for capture control actions.
    private let sessionQueue = DispatchSerialQueue(label: "com.example.apple-samplecode.AVCam.sessionQueue")

    // Sets the session queue as the actor's executor.
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        sessionQueue.asUnownedSerialExecutor()
    }

    init() {
        // Check multi-cam support and create appropriate session
        if AVCaptureMultiCamSession.isMultiCamSupported {
            self.captureSession = AVCaptureMultiCamSession()
        } else {
            self.captureSession = AVCaptureSession()
        }
        // Create a source object to connect the preview view with the capture session.
        previewSource = DefaultPreviewSource(session: captureSession)
    }

    // MARK: - Authorization
    /// A Boolean value that indicates whether a person authorizes this app to use
    /// device cameras and microphones. If they haven't previously authorized the
    /// app, querying this property prompts them for authorization.
    var isAuthorized: Bool {
        get async {
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            // Determine whether a person previously authorized camera access.
            var isAuthorized = status == .authorized
            // If the system hasn't determined their authorization status,
            // explicitly prompt them for approval.
            if status == .notDetermined {
                isAuthorized = await AVCaptureDevice.requestAccess(for: .video)
            }
            return isAuthorized
        }
    }

    // MARK: - Multi-Camera Configuration

    /// Configures multi-camera session with back and front cameras
    /// Follows the correct sequence from DUAL_CAMERA_AUDIO_FIG_ERRORS_SOLUTION.md:
    /// 1) Pre-activate audio session, 2) Configure formats, 3) beginConfiguration,
    /// 4) Add audio input FIRST, 5) Add video outputs, 6) Create connections,
    /// 7) Set delegates/synchronizer, 8) commitConfiguration, 9) startRunning (in start() method)
    private func configureMultiCamSession() throws {
        guard let multiCamSession = captureSession as? AVCaptureMultiCamSession else {
            logger.error("Failed to cast session to AVCaptureMultiCamSession")
            throw CameraError.setupFailed
        }

        guard let devicePair = deviceLookup.multiCamDevicePair else {
            logger.error("No multi-cam device pair available")
            throw CameraError.setupFailed
        }

        logger.info("📹 Starting multi-cam configuration with back: \(devicePair.back.localizedName), front: \(devicePair.front.localizedName)")

        // Store devices
        backCameraDevice = devicePair.back
        frontCameraDevice = devicePair.front

        // STEP 1: Configure formats BEFORE session configuration
        logger.info("📹 Step 1: Configuring multi-cam formats...")
        try configureMultiCamFormats(back: devicePair.back, front: devicePair.front)

        // STEP 2: Begin configuration
        logger.info("📹 Step 2: Beginning session configuration...")
        multiCamSession.beginConfiguration()
        defer {
            logger.info("📹 Step 8: Committing session configuration...")
            multiCamSession.commitConfiguration()
        }
        
        // Audio session preferences: Model A (session-managed)
        // CRITICAL: Set AFTER beginConfiguration to avoid FIG error -19224
        // Let capture session manage audio and enable HQ Bluetooth mic
        multiCamSession.automaticallyConfiguresApplicationAudioSession = true
        multiCamSession.configuresApplicationAudioSessionForBluetoothHighQualityRecording = true
        logger.info("🎧 Audio session mode: Session-managed (Model A)")
        logger.info("🎧 HQ Bluetooth recording: enabled")

        // STEP 3: Add audio input FIRST (before video inputs!) - CRITICAL for avoiding FIG errors
        // Per WWDC 2019 Session 249: Audio MUST be added before video in multi-cam setup
        logger.info("🎧 Step 3: Adding audio input (BEFORE video inputs!)...")
        let defaultMic = try deviceLookup.defaultMic
        try addInput(for: defaultMic)
        logger.info("🎧 Audio input added: \(defaultMic.localizedName)")

        // STEP 4: Add video inputs without automatic connections (AFTER audio)
        logger.info("📹 Step 4: Adding video inputs...")
        try addMultiCamInputs(back: devicePair.back, front: devicePair.front)

        // STEP 5: Add outputs without automatic connections
        logger.info("📹 Step 5: Adding video and audio outputs...")
        try addMultiCamOutputs()

        // STEP 6: Create manual connections
        logger.info("📹 Step 6: Creating manual connections...")
        try createMultiCamConnections()

        // Check hardware cost
        let hardwareCost = multiCamSession.hardwareCost
        logger.info("📹 Multi-cam hardware cost: \(String(format: "%.2f", hardwareCost)) (must be < 1.0)")

        guard hardwareCost < 1.0 else {
            logger.error("❌ Hardware cost too high: \(hardwareCost) (must be < 1.0)")
            multiCamErrorMessage = String(format: "Multi-camera disabled: hardware cost (%.2f) exceeds device capability.", hardwareCost)
            throw CameraError.hardwareCostExceeded(cost: hardwareCost)
        }

        logger.info("✅ Hardware cost check passed: \(String(format: "%.2f", hardwareCost))")

        // Monitor system pressure for both devices
        observeSystemPressure(for: devicePair.back)
        observeSystemPressure(for: devicePair.front)

        // STEP 7: Setup synchronizer and delegates for recording
        logger.info("📹 Step 7: Setting up synchronizer and delegates...")
        setupSynchronizer()

        isMultiCamMode = true

        logger.info("✅ Multi-camera session configuration complete")
        logger.info("📹 Next step (Step 9): startRunning() will be called in start() method")
    }

    /// Configure formats for multi-cam mode
    private func configureMultiCamFormats(back: AVCaptureDevice, front: AVCaptureDevice) throws {
        // Back camera - higher resolution (primary)
        guard let backFormat = deviceLookup.selectMultiCamFormat(for: back, targetFPS: 30) else {
            logger.error("No suitable multi-cam format found for back camera")
            throw CameraError.setupFailed
        }

        // Validate back camera format before applying
        try validateFormat(backFormat, for: back, targetFPS: 30)

        do {
            try back.lockForConfiguration()
            back.activeFormat = backFormat
            back.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            back.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            back.unlockForConfiguration()

            let dimensions = CMVideoFormatDescriptionGetDimensions(backFormat.formatDescription)
            logger.info("📹 Back camera: \(dimensions.width)x\(dimensions.height) @ 30fps")
        } catch {
            logger.error("Failed to configure back camera format: \(error.localizedDescription)")
            throw error
        }

        // Front camera - lower resolution (PiP)
        guard let frontFormat = deviceLookup.selectMultiCamFormat(for: front, targetFPS: 30) else {
            logger.error("No suitable multi-cam format found for front camera")
            throw CameraError.setupFailed
        }

        // Validate front camera format before applying
        try validateFormat(frontFormat, for: front, targetFPS: 30)

        do {
            try front.lockForConfiguration()
            front.activeFormat = frontFormat
            front.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            front.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)

            // Configure Center Stage if supported
            configureCenterStage(for: front)

            front.unlockForConfiguration()

            let dimensions = CMVideoFormatDescriptionGetDimensions(frontFormat.formatDescription)
            logger.info("📹 Front camera: \(dimensions.width)x\(dimensions.height) @ 30fps")
            if self.isCenterStageSupported {
                logger.info("📹 Center Stage: \(self.isCenterStageEnabled ? "Enabled" : "Disabled")")
            }
        } catch {
            logger.error("Failed to configure front camera format: \(error.localizedDescription)")
            throw error
        }
    }

    /// Configure Center Stage for front camera if supported
    private func configureCenterStage(for device: AVCaptureDevice) {
        // Center Stage is only available on certain devices (iPad Pro, Studio Display)
        // For iPhone, this feature may not be available
        // Check if the device supports Center Stage control
        if #available(iOS 14.5, *) {
            // Note: Center Stage is primarily for iPad and Mac, not iPhone
            // On iPhone, this will typically not be supported
            isCenterStageSupported = false
            isCenterStageEnabled = false
            logger.info("ℹ️ Center Stage is not available on iPhone devices")
        } else {
            isCenterStageSupported = false
            isCenterStageEnabled = false
        }
    }

    /// Validate that a format supports the required features for multi-cam recording
    private func validateFormat(_ format: AVCaptureDevice.Format, for device: AVCaptureDevice, targetFPS: Int) throws {
        // Check multi-cam support
        guard format.isMultiCamSupported else {
            logger.error("❌ Format does not support multi-cam: \(format)")
            throw CameraError.configurationFailed
        }

        // Check frame rate support
        let supportsTargetFPS = format.videoSupportedFrameRateRanges.contains { range in
            range.minFrameRate <= Double(targetFPS) && range.maxFrameRate >= Double(targetFPS)
        }

        guard supportsTargetFPS else {
            logger.error("❌ Format does not support \(targetFPS) fps: \(format)")
            throw CameraError.configurationFailed
        }

        // Check resolution (minimum 720p for quality)
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        guard dimensions.width >= 1280 && dimensions.height >= 720 else {
            logger.error("❌ Format resolution too low: \(dimensions.width)x\(dimensions.height)")
            throw CameraError.configurationFailed
        }

        logger.info("✅ Format validated: \(dimensions.width)x\(dimensions.height) @ \(targetFPS)fps, multi-cam: \(format.isMultiCamSupported)")
    }

    /// Add multi-cam inputs without automatic connections
    private func addMultiCamInputs(back: AVCaptureDevice, front: AVCaptureDevice) throws {
        guard let multiCamSession = captureSession as? AVCaptureMultiCamSession else {
            logger.error("Failed to get multi-cam session for adding inputs")
            throw CameraError.setupFailed
        }

        // Create both inputs first
        let backInput = try AVCaptureDeviceInput(device: back)
        let frontInput = try AVCaptureDeviceInput(device: front)

        // Check if BOTH can be added before adding either
        guard multiCamSession.canAddInput(backInput) else {
            logger.error("Cannot add back camera input to session")
            throw CameraError.addInputFailed
        }

        guard multiCamSession.canAddInput(frontInput) else {
            logger.error("Cannot add front camera input to session")
            throw CameraError.addInputFailed
        }

        // Now add both
        multiCamSession.addInputWithNoConnections(backInput)
        backVideoInput = backInput
        logger.info("Back camera input added")

        multiCamSession.addInputWithNoConnections(frontInput)
        frontVideoInput = frontInput
        logger.info("Front camera input added")
    }

    /// Add multi-cam outputs without automatic connections
    private func addMultiCamOutputs() throws {
        guard let multiCamSession = captureSession as? AVCaptureMultiCamSession else {
            throw CameraError.setupFailed
        }

        // Back camera video output
        let backOutput = AVCaptureVideoDataOutput()
        backOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        backOutput.alwaysDiscardsLateVideoFrames = true

        guard multiCamSession.canAddOutput(backOutput) else {
            throw CameraError.addOutputFailed
        }
        multiCamSession.addOutputWithNoConnections(backOutput)
        backVideoOutput = backOutput

        // Front camera video output
        let frontOutput = AVCaptureVideoDataOutput()
        frontOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        frontOutput.alwaysDiscardsLateVideoFrames = true

        guard multiCamSession.canAddOutput(frontOutput) else {
            throw CameraError.addOutputFailed
        }
        multiCamSession.addOutputWithNoConnections(frontOutput)
        frontVideoOutput = frontOutput

        // Back camera photo output
        let backPhotoOut = AVCapturePhotoOutput()
        guard multiCamSession.canAddOutput(backPhotoOut) else {
            throw CameraError.addOutputFailed
        }
        multiCamSession.addOutputWithNoConnections(backPhotoOut)
        backPhotoOutput = backPhotoOut

        // Front camera photo output
        let frontPhotoOut = AVCapturePhotoOutput()
        guard multiCamSession.canAddOutput(frontPhotoOut) else {
            throw CameraError.addOutputFailed
        }
        multiCamSession.addOutputWithNoConnections(frontPhotoOut)
        frontPhotoOutput = frontPhotoOut

        // Audio output for recording
        // Note: Audio uses addOutput() (not addOutputWithNoConnections) because
        // it automatically connects to the audio input - no manual connection needed
        let audioOutput = AVCaptureAudioDataOutput()
        guard multiCamSession.canAddOutput(audioOutput) else {
            logger.error("❌ Cannot add audio output to session")
            throw CameraError.addOutputFailed
        }
        multiCamSession.addOutput(audioOutput)
        self.audioOutput = audioOutput
        logger.info("🎧 Audio output added (auto-connects to audio input)")

        logger.info("✅ Multi-cam outputs configured: back video, front video, back photo, front photo, audio")
    }

    /// Create manual connections for multi-cam outputs
    private func createMultiCamConnections() throws {
        guard let multiCamSession = captureSession as? AVCaptureMultiCamSession,
              let backInput = backVideoInput,
              let frontInput = frontVideoInput,
              let backOutput = backVideoOutput,
              let frontOutput = frontVideoOutput,
              let backPhotoOut = backPhotoOutput,
              let frontPhotoOut = frontPhotoOutput,
              let backCamera = backCameraDevice,
              let frontCamera = frontCameraDevice else {
            throw CameraError.setupFailed
        }

        // Back camera video port
        guard let backVideoPort = backInput.ports(
            for: .video,
            sourceDeviceType: backCamera.deviceType,
            sourceDevicePosition: backCamera.position
        ).first else {
            throw CameraError.setupFailed
        }

        // Back camera data output connection
        let backOutputConnection = AVCaptureConnection(inputPorts: [backVideoPort], output: backOutput)
        guard multiCamSession.canAddConnection(backOutputConnection) else {
            throw CameraError.setupFailed
        }

        if backOutputConnection.isVideoStabilizationSupported {
            backOutputConnection.preferredVideoStabilizationMode = .auto
        }

        multiCamSession.addConnection(backOutputConnection)
        logger.info("Added back camera output connection")

        // Back camera photo output connection
        let backPhotoConnection = AVCaptureConnection(inputPorts: [backVideoPort], output: backPhotoOut)
        guard multiCamSession.canAddConnection(backPhotoConnection) else {
            throw CameraError.setupFailed
        }
        multiCamSession.addConnection(backPhotoConnection)
        logger.info("Added back camera photo connection")

        // Front camera video port
        guard let frontVideoPort = frontInput.ports(
            for: .video,
            sourceDeviceType: frontCamera.deviceType,
            sourceDevicePosition: frontCamera.position
        ).first else {
            throw CameraError.setupFailed
        }

        // Front camera data output connection
        let frontOutputConnection = AVCaptureConnection(inputPorts: [frontVideoPort], output: frontOutput)
        guard multiCamSession.canAddConnection(frontOutputConnection) else {
            throw CameraError.setupFailed
        }

        if frontOutputConnection.isVideoStabilizationSupported {
            frontOutputConnection.preferredVideoStabilizationMode = .auto
        }
        
        // Mirror front camera for natural selfie appearance
        if frontOutputConnection.isVideoMirroringSupported {
            frontOutputConnection.automaticallyAdjustsVideoMirroring = false
            frontOutputConnection.isVideoMirrored = true
            logger.info("📱 Front camera mirroring enabled")
        }

        multiCamSession.addConnection(frontOutputConnection)
        logger.info("Added front camera output connection (mirrored)")

        // Front camera photo output connection
        let frontPhotoConnection = AVCaptureConnection(inputPorts: [frontVideoPort], output: frontPhotoOut)
        guard multiCamSession.canAddConnection(frontPhotoConnection) else {
            throw CameraError.setupFailed
        }
        multiCamSession.addConnection(frontPhotoConnection)
        logger.info("Added front camera photo connection")
    }

    /// Monitor system pressure for a device
    private func observeSystemPressure(for device: AVCaptureDevice) {
        let observation = device.observe(\.systemPressureState, options: .new) { [weak self] device, _ in
            Task { @MainActor [weak self] in
                await self?.handleSystemPressure(state: device.systemPressureState, for: device)
            }
        }
        // Store observation to keep it alive (separate array from rotation observers)
        systemPressureObservers.append(observation)
    }

    private func handleSystemPressure(state: AVCaptureDevice.SystemPressureState, for device: AVCaptureDevice) async {
        logger.warning("⚠️ System pressure: \(state.level.rawValue) for \(device.localizedName)")
        
        // Log contributing factors for diagnostics
        if state.factors.contains(.systemTemperature) {
            logger.warning("   - Factor: System temperature")
        }
        if state.factors.contains(.peakPower) {
            logger.warning("   - Factor: Peak power demand")
        }
        if state.factors.contains(.depthModuleTemperature) {
            logger.warning("   - Factor: Depth module temperature")
        }

        switch state.level {
        case .nominal, .fair:
            // Restore full frame rate if we throttled earlier
            try? device.lockForConfiguration()
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            device.unlockForConfiguration()
            logger.info("✅ System pressure normal - restored 30fps")
            
        case .serious:
            // Reduce frame rate to 20fps
            try? device.lockForConfiguration()
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 20)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 20)
            device.unlockForConfiguration()
            logger.warning("⚠️ Throttling to 20fps due to serious pressure")

        case .critical:
            // Aggressively reduce frame rate to 15fps
            try? device.lockForConfiguration()
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 15)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 15)
            device.unlockForConfiguration()
            logger.error("❌ Throttling to 15fps due to critical pressure")

        case .shutdown:
            // Stop capture to protect hardware
            logger.error("🛑 SHUTDOWN: Stopping capture to prevent hardware damage")
            captureSession.stopRunning()
        
        default:
            logger.warning("⚠️ Unknown system pressure level")
        }
    }

    /// Observe thermal state changes and adjust behavior/logging
    /// Set thermal level safely within actor isolation
    private func setThermalLevel(_ level: String) {
        thermalLevel = level
    }

    private func observeThermalState() {
        Task { [weak self] in
            let center = NotificationCenter.default
            for await _ in center.notifications(named: ProcessInfo.thermalStateDidChangeNotification) {
                guard let self else { continue }
                let state = ProcessInfo.processInfo.thermalState
                let level: String
                switch state {
                case .nominal: level = "nominal"
                case .fair: level = "fair"
                case .serious: level = "serious"
                case .critical: level = "critical"
                @unknown default: level = "unknown"
                }
                logger.warning("Thermal state changed: \(level)")
                await self.setThermalLevel(level)
                // Optional: react to thermal pressure (e.g., reduce quality or disable PiP)
                // For now, rely primarily on system pressure handlers and inform the UI.
            }
        }
    }

    // MARK: - Audio Route Monitoring

    /// Observe audio route changes for diagnostics and FIG error tracking
    /// This helps diagnose FIG errors -19224 and -17281 during route transitions
    private func observeAudioRoutes() {
        Task { [weak self] in
            let center = NotificationCenter.default
            for await notification in center.notifications(named: AVAudioSession.routeChangeNotification) {
                guard let self else { continue }

                // Extract route change information
                let userInfo = notification.userInfo
                let reason = userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
                let reasonString = await self.audioRouteChangeReasonString(reason)

                // Get current route description
                let audioSession = AVAudioSession.sharedInstance()
                let currentRoute = audioSession.currentRoute
                let inputs = currentRoute.inputs.map { "\($0.portType.rawValue): \($0.portName)" }.joined(separator: ", ")
                let outputs = currentRoute.outputs.map { "\($0.portType.rawValue): \($0.portName)" }.joined(separator: ", ")

                let routeDescription = "Inputs: [\(inputs.isEmpty ? "none" : inputs)], Outputs: [\(outputs.isEmpty ? "none" : outputs)]"

                logger.info("🎧 Audio route changed: \(reasonString)")
                logger.info("🎧 Current route: \(routeDescription)")
                logger.info("🎧 Sample rate: \(audioSession.sampleRate) Hz, IO buffer: \(audioSession.ioBufferDuration * 1000) ms")

                // Update published property for UI diagnostics
                await self.setAudioRouteDescription(routeDescription)

                // In session-managed mode (Model A), no reconfiguration needed
                // The capture session handles audio session changes automatically
                // This observer is primarily for diagnostics and logging
            }
        }
    }

    /// Set audio route description safely within actor isolation
    private func setAudioRouteDescription(_ description: String) {
        audioRouteDescription = description
    }

    /// Convert audio route change reason to human-readable string
    private func audioRouteChangeReasonString(_ reason: UInt) -> String {
        switch AVAudioSession.RouteChangeReason(rawValue: reason) {
        case .newDeviceAvailable:
            return "New device available"
        case .oldDeviceUnavailable:
            return "Old device unavailable"
        case .categoryChange:
            return "Category change"
        case .override:
            return "Override"
        case .wakeFromSleep:
            return "Wake from sleep"
        case .noSuitableRouteForCategory:
            return "No suitable route for category"
        case .routeConfigurationChange:
            return "Route configuration change"
        default:
            return "Unknown reason (\(reason))"
        }
    }

    // MARK: - Capture session life cycle
    func start(with state: CameraState) async throws {
        // Set initial operating state.
        captureMode = state.captureMode
        isHDRVideoEnabled = state.isVideoHDREnabled

        // Exit early if not authorized or the session is already running.
        guard await isAuthorized, !captureSession.isRunning else {
            logger.info("Skipping start - not authorized or already running")
            return
        }

        // Configure the session and start it with retry logic for FIG errors
        try setUpSession()
        try await startSessionWithRetry()

        observeThermalState()
        observeAudioRoutes()

        // Log initial audio session state for diagnostics
        let audioSession = AVAudioSession.sharedInstance()
        logger.info("🎧 Audio session initialized - Sample rate: \(audioSession.sampleRate) Hz, IO buffer: \(audioSession.ioBufferDuration * 1000) ms")
        logger.info("🎧 Audio category: \(audioSession.category.rawValue), mode: \(audioSession.mode.rawValue)")

        logger.info("✅ Capture session started running. Multi-cam mode: \(self.isMultiCamMode)")
    }

    /// Switch from multi-camera mode to single camera mode as a fallback
    func switchToSingleCameraMode() async throws {
        logger.info("🔄 Switching from multi-cam to single camera mode...")

        // Stop current session
        if captureSession.isRunning {
            captureSession.stopRunning()
        }

        // Clean up multi-cam resources (synchronizer and delegate)
        self.synchronizer?.setDelegate(nil, queue: nil)
        self.synchronizer = nil
        self.dualRecordingDelegate = nil
        logger.info("🧹 Cleaned up multi-cam synchronizer and delegate")

        // Reset multi-cam state
        isMultiCamMode = false
        dualRecorder = nil

        // Reconfigure session for single camera
        try setUpSession()

        // Restart session
        try await startSessionWithRetry()

        logger.info("✅ Successfully switched to single camera mode")
    }

    /// Start the capture session with retry logic for transient FIG errors
    /// Implements recovery strategy from DUAL_CAMERA_AUDIO_FIG_ERRORS_SOLUTION.md
    private func startSessionWithRetry(maxRetries: Int = 3) async throws {
        var lastError: Error?

        for attempt in 1...maxRetries {
            do {
                logger.info("📹 Starting capture session (attempt \(attempt)/\(maxRetries))...")
                captureSession.startRunning()

                // Give the session just enough time to detect errors (10ms)
                // Reduced from 100ms to minimize startup delay
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms

                // Verify session is actually running
                guard captureSession.isRunning else {
                    throw CameraError.setupFailed
                }

                logger.info("✅ Capture session started successfully on attempt \(attempt)")
                return

            } catch {
                lastError = error
                logger.warning("⚠️ Session start attempt \(attempt) failed: \(error.localizedDescription)")

                if attempt < maxRetries {
                    // Stop session if it's in a bad state
                    if captureSession.isRunning {
                        captureSession.stopRunning()
                    }

                    // Exponential backoff: 200ms, 400ms, 800ms
                    let backoffMs = 200 * (1 << (attempt - 1))
                    logger.info("⏳ Waiting \(backoffMs)ms before retry...")
                    try await Task.sleep(nanoseconds: UInt64(backoffMs) * 1_000_000)

                    // For multi-cam, check if another app is holding audio
                    if isMultiCamMode {
                        let audioSession = AVAudioSession.sharedInstance()
                        logger.info("🎧 Audio session state: category=\(audioSession.category.rawValue), active=\(audioSession.isOtherAudioPlaying)")
                    }
                }
            }
        }

        // All retries exhausted
        logger.error("❌ Failed to start capture session after \(maxRetries) attempts")
        throw lastError ?? CameraError.setupFailed
    }

    // MARK: - Capture setup
    // Performs the initial capture session configuration.
    private func setUpSession() throws {
        // Return early if already set up.
        guard !isSetUp else { return }

        // Observe internal state and notifications.
        observeOutputServices()
        observeNotifications()
        observeCaptureControlsState()

        // Check if multi-cam is supported and try to configure it
        var multiCamSetupSucceeded = false
        multiCamErrorMessage = nil
        if AVCaptureMultiCamSession.isMultiCamSupported {
            do {
                try configureMultiCamSession()
                multiCamSetupSucceeded = true
                logger.info("Multi-camera session configured successfully")
            } catch {
                logger.error("Multi-camera setup failed: \(error.localizedDescription). Falling back to single camera.")
                // Provide user-facing reason for fallback
                multiCamErrorMessage = "Multi-camera unavailable: \(error.localizedDescription)"
                // Reset any partial multi-cam state
                backCameraDevice = nil
                frontCameraDevice = nil
                backVideoInput = nil
                frontVideoInput = nil
                backVideoOutput = nil
                frontVideoOutput = nil
                isMultiCamMode = false
            }
        } else {
            // Not supported by device
            multiCamErrorMessage = "This device does not support multi-camera capture (requires iPhone XS or later)."
        }

        // If multi-cam setup failed or isn't supported, use single camera
        if !multiCamSetupSucceeded {
            do {
                // Retrieve the default camera and microphone.
                let defaultCamera = try deviceLookup.defaultCamera
                let defaultMic = try deviceLookup.defaultMic

                // Enable using AirPods as a high-quality lapel microphone.
                captureSession.configuresApplicationAudioSessionForBluetoothHighQualityRecording = true

                // Add inputs for the default camera and microphone devices.
                activeVideoInput = try addInput(for: defaultCamera)
                try addInput(for: defaultMic)

                // Configure the session preset based on the current capture mode.
                // Use isMultiCamMode flag instead of type check because session may be
                // AVCaptureMultiCamSession even in fallback mode
                if !isMultiCamMode {
                    captureSession.sessionPreset = captureMode == .photo ? .photo : .high
                }
                // Add the photo capture output as the default output type.
                try addOutput(photoCapture.output)
                // If the capture mode is set to Video, add a movie capture output.
                if captureMode == .video {
                    // Add the movie output as the default output type.
                    try addOutput(movieCapture.output)
                    setHDRVideoEnabled(isHDRVideoEnabled)
                }

                // Configure controls to use with the Camera Control.
                configureControls(for: defaultCamera)
                // Monitor the system-preferred camera state.
                monitorSystemPreferredCamera()
                // Configure a rotation coordinator for the default video device.
                createRotationCoordinator(for: defaultCamera)
                // Observe changes to the default camera's subject area.
                observeSubjectAreaChanges(of: defaultCamera)
                // Update the service's advertised capabilities.
                updateCaptureCapabilities()

                logger.info("Single camera session configured successfully")
            } catch {
                logger.error("Single camera setup failed: \(error.localizedDescription)")
                throw CameraError.setupFailed
            }
        }

        isSetUp = true
    }

    // Adds an input to the capture session to connect the specified capture device.
    @discardableResult
    private func addInput(for device: AVCaptureDevice) throws -> AVCaptureDeviceInput {
        let input = try AVCaptureDeviceInput(device: device)
        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        } else {
            throw CameraError.addInputFailed
        }
        return input
    }

    // Adds an output to the capture session to connect the specified capture device, if allowed.
    private func addOutput(_ output: AVCaptureOutput) throws {
        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
        } else {
            throw CameraError.addOutputFailed
        }
    }

    // The device for the active video input.
    private var currentDevice: AVCaptureDevice? {
        // In multi-cam mode, return the back camera as the "current" device
        if isMultiCamMode, let device = backVideoInput?.device {
            return device
        }
        // In single-cam mode, use the active video input
        return activeVideoInput?.device
    }

    // MARK: - Capture controls

    private func configureControls(for device: AVCaptureDevice) {

        // Exit early if the host device doesn't support capture controls.
        guard captureSession.supportsControls else { return }

        // Begin configuring the capture session.
        captureSession.beginConfiguration()

        // Remove previously configured controls, if any.
        for control in captureSession.controls {
            captureSession.removeControl(control)
        }

        // Create controls and add them to the capture session.
        for control in createControls(for: device) {
            if captureSession.canAddControl(control) {
                captureSession.addControl(control)
            } else {
                logger.info("Unable to add control \(control).")
            }
        }

        // Set the controls delegate.
        captureSession.setControlsDelegate(controlsDelegate, queue: sessionQueue)

        // Commit the capture session configuration.
        captureSession.commitConfiguration()
    }

    func createControls(for device: AVCaptureDevice) -> [AVCaptureControl] {
        // Retrieve the capture controls for this device, if they exist.
        guard let controls = controlsMap[device.uniqueID] else {
            // Define the default controls.
            var controls = [
                AVCaptureSystemZoomSlider(device: device),
                AVCaptureSystemExposureBiasSlider(device: device)
            ]
            // Create a lens position control if the device supports setting a custom position.
            if device.isLockingFocusWithCustomLensPositionSupported {
                // Create a slider to adjust the value from 0 to 1.
                let lensSlider = AVCaptureSlider("Lens Position", symbolName: "circle.dotted.circle", in: 0...1)
                // Perform the slider's action on the session queue.
                lensSlider.setActionQueue(sessionQueue) { lensPosition in
                    do {
                        try device.lockForConfiguration()
                        device.setFocusModeLocked(lensPosition: lensPosition)
                        device.unlockForConfiguration()
                    } catch {
                        logger.info("Unable to change the lens position: \(error)")
                    }
                }
                // Add the slider the controls array.
                controls.append(lensSlider)
            }
            // Store the controls for future use.
            controlsMap[device.uniqueID] = controls
            return controls
        }

        // Return the previously created controls.
        return controls
    }

    // MARK: - Capture mode selection

    /// Changes the mode of capture, which can be `photo` or `video`.
    ///
    /// - Parameter `captureMode`: The capture mode to enable.
    func setCaptureMode(_ captureMode: CaptureMode) throws {
        // Update the internal capture mode value before performing the session configuration.
        self.captureMode = captureMode

        // Change the configuration atomically.
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        // Configure the capture session for the selected capture mode.
        switch captureMode {
        case .photo:
            // The app needs to remove the movie capture output to perform Live Photo capture.
            // Use isMultiCamMode flag instead of type check
            if !isMultiCamMode {
                captureSession.sessionPreset = .photo
            }
            captureSession.removeOutput(movieCapture.output)
        case .video:
            if !isMultiCamMode {
                captureSession.sessionPreset = .high
            }
            try addOutput(movieCapture.output)
            if isHDRVideoEnabled {
                setHDRVideoEnabled(true)
            }
        }

        // Update the advertised capabilities after reconfiguration.
        updateCaptureCapabilities()
    }

    // MARK: - Device selection

    /// Changes the capture device that provides video input.
    ///
    /// The app calls this method in response to the user tapping the button in the UI to change cameras.
    /// The implementation switches between the front and back cameras and, in iPadOS,
    /// connected external cameras.
    func selectNextVideoDevice() {
        // Cannot switch devices in multi-cam mode
        guard !isMultiCamMode else {
            logger.warning("Cannot switch video devices in multi-camera mode")
            return
        }

        // The array of available video capture devices.
        let videoDevices = deviceLookup.cameras

        // Find the index of the currently selected video device.
        let selectedIndex = currentDevice.flatMap { videoDevices.firstIndex(of: $0) } ?? 0
        // Get the next index.
        var nextIndex = selectedIndex + 1
        // Wrap around if the next index is invalid.
        if nextIndex == videoDevices.endIndex {
            nextIndex = 0
        }

        let nextDevice = videoDevices[nextIndex]
        // Change the session's active capture device.
        changeCaptureDevice(to: nextDevice)

        // The app only calls this method in response to the user requesting to switch cameras.
        // Set the new selection as the user's preferred camera.
        AVCaptureDevice.userPreferredCamera = nextDevice
    }

    // Changes the device the service uses for video capture.
    private func changeCaptureDevice(to device: AVCaptureDevice) {
        // Cannot change devices in multi-cam mode
        guard !isMultiCamMode else {
            logger.warning("Cannot change capture device in multi-camera mode")
            return
        }

        // The service must have a valid video input prior to calling this method.
        guard let currentInput = activeVideoInput else {
            logger.error("Cannot change capture device - no active video input")
            return
        }

        // Bracket the following configuration in a begin/commit configuration pair.
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        // Remove the existing video input before attempting to connect a new one.
        captureSession.removeInput(currentInput)
        do {
            // Attempt to connect a new input and device to the capture session.
            activeVideoInput = try addInput(for: device)
            // Configure capture controls for new device selection.
            configureControls(for: device)
            // Configure a new rotation coordinator for the new device.
            createRotationCoordinator(for: device)
            // Register for device observations.
            observeSubjectAreaChanges(of: device)
            // Update the service's advertised capabilities.
            updateCaptureCapabilities()
        } catch {
            // Reconnect the existing camera on failure.
            captureSession.addInput(currentInput)
        }
    }

    /// Monitors changes to the system's preferred camera selection.
    ///
    /// iPadOS supports external cameras. When someone connects an external camera to their iPad,
    /// they're signaling the intent to use the device. The system responds by updating the
    /// system-preferred camera (SPC) selection to this new device. When this occurs, if the SPC
    /// isn't the currently selected camera, switch to the new device.
    private func monitorSystemPreferredCamera() {
        Task {
            // An object monitors changes to system-preferred camera (SPC) value.
            for await camera in systemPreferredCamera.changes {
                // If the SPC isn't the currently selected camera, attempt to change to that device.
                if let camera, currentDevice != camera {
                    logger.debug("Switching camera selection to the system-preferred camera.")
                    changeCaptureDevice(to: camera)
                }
            }
        }
    }

    // MARK: - Rotation handling

    /// Create a new rotation coordinator for the specified device and observe its state to monitor rotation changes.
    private func createRotationCoordinator(for device: AVCaptureDevice) {
        // Create a new rotation coordinator for this device.
        // In single-cam mode, use the video preview layer for rotation updates
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: videoPreviewLayer)
        rotationCoordinator = coordinator

        // Set initial rotation state on the preview and output connections.
        updatePreviewRotation(coordinator.videoRotationAngleForHorizonLevelPreview)
        updateCaptureRotation(coordinator.videoRotationAngleForHorizonLevelCapture)

        // Cancel previous observations.
        rotationObservers.removeAll()

        // Add observers to monitor future changes.
        rotationObservers.append(
            coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: .new) { [weak self] _, change in
                guard let self, let angle = change.newValue else { return }
                // Update the capture preview rotation.
                Task { await self.updatePreviewRotation(angle) }
            }
        )

        rotationObservers.append(
            coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: .new) { [weak self] _, change in
                guard let self, let angle = change.newValue else { return }
                // Update the capture preview rotation.
                Task { await self.updateCaptureRotation(angle) }
            }
        )
    }

    private func updatePreviewRotation(_ angle: CGFloat) {
        let connection = videoPreviewLayer?.connection
        Task { @MainActor in
        // Set initial rotation angle on the video preview.
            connection?.videoRotationAngle = angle
        }
    }

        private func updateCaptureRotation(_ angle: CGFloat) {
        // Update the orientation for all output services.
        outputServices.forEach { $0.setVideoRotationAngle(angle) }
    }

    // Setup multi-cam rotation coordinators and wire updates
    private func setupMultiCamRotationCoordinators(backLayer: AVCaptureVideoPreviewLayer, frontLayer: AVCaptureVideoPreviewLayer) async {
        guard let backDevice = backCameraDevice, let frontDevice = frontCameraDevice else { return }

        // Create coordinators
        let backRC = AVCaptureDevice.RotationCoordinator(device: backDevice, previewLayer: backLayer)
        let frontRC = AVCaptureDevice.RotationCoordinator(device: frontDevice, previewLayer: frontLayer)
        backRotationCoordinator = backRC
        frontRotationCoordinator = frontRC

        // Set initial angles for preview connections
        await MainActor.run {
            backLayer.connection?.videoRotationAngle = backRC.videoRotationAngleForHorizonLevelPreview
            frontLayer.connection?.videoRotationAngle = frontRC.videoRotationAngleForHorizonLevelPreview
        }
        // Set initial angles for data outputs
        setRotationAngle(on: backVideoOutput, angle: backRC.videoRotationAngleForHorizonLevelCapture)
        setRotationAngle(on: frontVideoOutput, angle: frontRC.videoRotationAngleForHorizonLevelCapture)

        // Observe preview angle changes - use non-Sendable workaround
        rotationObservers.append(
            backRC.observe(\.videoRotationAngleForHorizonLevelPreview, options: .new) { _, change in
                guard let angle = change.newValue else { return }
                Task { @MainActor in 
                    backLayer.connection?.videoRotationAngle = angle 
                }
            }
        )
        rotationObservers.append(
            frontRC.observe(\.videoRotationAngleForHorizonLevelPreview, options: .new) { _, change in
                guard let angle = change.newValue else { return }
                Task { @MainActor in 
                    frontLayer.connection?.videoRotationAngle = angle 
                }
            }
        )

        // Observe capture angle changes - store weak references to avoid Sendable issues
        weak var weakBackOutput = backVideoOutput
        weak var weakFrontOutput = frontVideoOutput
        weak var weakRecorder = dualRecorder
        weak var weakBackRC = backRC
        weak var weakFrontRC = frontRC
        
        rotationObservers.append(
            backRC.observe(\.videoRotationAngleForHorizonLevelCapture, options: .new) { _, change in
                guard let angle = change.newValue,
                      let backOutput = weakBackOutput,
                      let frontRC = weakFrontRC,
                      let recorder = weakRecorder else { return }
                Task {
                    await self.setRotationAngle(on: backOutput, angle: angle)
                    // Also update recorder for proper composition
                    let frontAngle = await frontRC.videoRotationAngleForHorizonLevelCapture
                    await recorder.setRotationAngles(back: angle, front: frontAngle)
                }
            }
        )
        rotationObservers.append(
            frontRC.observe(\.videoRotationAngleForHorizonLevelCapture, options: .new) { _, change in
                guard let angle = change.newValue,
                      let frontOutput = weakFrontOutput,
                      let backRC = weakBackRC,
                      let recorder = weakRecorder else { return }
                Task {
                    await self.setRotationAngle(on: frontOutput, angle: angle)
                    // Also update recorder for proper composition
                    let backAngle = await backRC.videoRotationAngleForHorizonLevelCapture
                    await recorder.setRotationAngles(back: backAngle, front: angle)
                }
            }
        )
    }
 // Helper: set video rotation angle on a data output connection if present
    private func setRotationAngle(on output: AVCaptureVideoDataOutput?, angle: CGFloat) {
        output?.connection(with: .video)?.videoRotationAngle = angle
    }

    private var videoPreviewLayer: AVCaptureVideoPreviewLayer? {
        // Access the capture session's connected preview layer (single-cam mode only).
        return captureSession.connections.compactMap({ $0.videoPreviewLayer }).first
    }

    // MARK: - Automatic focus and exposure

    /// Performs a one-time automatic focus and expose operation.
    ///
    /// The app calls this method as the result of a person tapping on the preview area.
    func focusAndExpose(at point: CGPoint) {
        // The point this call receives is in view-space coordinates. Convert this point to device coordinates.
        guard let previewLayer = videoPreviewLayer else {
            logger.warning("No preview layer available for focus/exposure point conversion")
            return
        }
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)
        do {
            // Perform a user-initiated focus and expose.
            try focusAndExpose(at: devicePoint, isUserInitiated: true)
        } catch {
            logger.debug("Unable to perform focus and exposure operation. \(error)")
        }
    }

    // Observe notifications of type `subjectAreaDidChangeNotification` for the specified device.
    private func observeSubjectAreaChanges(of device: AVCaptureDevice) {
        // Cancel the previous observation task.
        subjectAreaChangeTask?.cancel()
        subjectAreaChangeTask = Task {
            // Signal true when this notification occurs.
            for await _ in NotificationCenter.default.notifications(named: AVCaptureDevice.subjectAreaDidChangeNotification, object: device).compactMap({ _ in true }) {
                // Perform a system-initiated focus and expose.
                try? focusAndExpose(at: CGPoint(x: 0.5, y: 0.5), isUserInitiated: false)
            }
        }
    }
    private var subjectAreaChangeTask: Task<Void, Never>?

    private func focusAndExpose(at devicePoint: CGPoint, isUserInitiated: Bool) throws {
        // Configure the current device.
        guard let device = currentDevice else {
            logger.error("No current device available for focus/exposure")
            throw CameraError.videoDeviceUnavailable
        }

        // The following mode and point of interest configuration requires obtaining an exclusive lock on the device.
        try device.lockForConfiguration()

        let focusMode = isUserInitiated ? AVCaptureDevice.FocusMode.autoFocus : .continuousAutoFocus
        if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
            device.focusPointOfInterest = devicePoint
            device.focusMode = focusMode
        }

        let exposureMode = isUserInitiated ? AVCaptureDevice.ExposureMode.autoExpose : .continuousAutoExposure
        if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
            device.exposurePointOfInterest = devicePoint
            device.exposureMode = exposureMode
        }
        // Enable subject-area change monitoring when performing a user-initiated automatic focus and exposure operation.
        // If this method enables change monitoring, when the device's subject area changes, the app calls this method a
        // second time and resets the device to continuous automatic focus and exposure.
        device.isSubjectAreaChangeMonitoringEnabled = isUserInitiated

        // Release the lock.
        device.unlockForConfiguration()
    }

    // MARK: - Photo capture
    func capturePhoto(with features: PhotoFeatures) async throws -> Photo {
        if isMultiCamMode {
            return try await captureDualPhoto(with: features)
        } else {
            return try await photoCapture.capturePhoto(with: features)
        }
    }

    func captureDualPhoto(with features: PhotoFeatures) async throws -> Photo {
        guard isMultiCamMode,
              let backPhotoOut = backPhotoOutput,
              let frontPhotoOut = frontPhotoOutput,
              let backCamera = backCameraDevice,
              let frontCamera = frontCameraDevice else {
            throw CameraError.multiCamNotSupported
        }

        captureActivity = .photoCapture(isLivePhoto: false)
        defer { captureActivity = .idle }

        let backSettings = createMultiCamPhotoSettings(for: backPhotoOut, device: backCamera)
        let frontSettings = createMultiCamPhotoSettings(for: frontPhotoOut, device: frontCamera)

        // Capture both photos simultaneously
        async let backPhotoTask = capturePhotoFromOutput(backPhotoOut, settings: backSettings)
        async let frontPhotoTask = capturePhotoFromOutput(frontPhotoOut, settings: frontSettings)

        let (backData, frontData) = try await (backPhotoTask, frontPhotoTask)

        // Compose the PiP photo
        let composedData = try composePhotos(backData: backData, frontData: frontData)

        // Return all three photos for CameraModel to save
        logger.info("📸 Captured 3 dual camera photos (back, front, composed)")

        // Return photo with all 3 data (composed as primary, back and front as extras)
        return Photo(data: composedData, isProxy: false, livePhotoMovieURL: nil, backData: backData, frontData: frontData)
    }

    private func createMultiCamPhotoSettings(for output: AVCapturePhotoOutput, device: AVCaptureDevice) -> AVCapturePhotoSettings {
        var photoSettings = AVCapturePhotoSettings()

        if output.availablePhotoCodecTypes.contains(.hevc) {
            photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        }

        if let previewPhotoPixelFormatType = photoSettings.availablePreviewPhotoPixelFormatTypes.first {
            photoSettings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: previewPhotoPixelFormatType]
        }

        if !output.connections.isEmpty, output.maxPhotoDimensions != .zero {
            photoSettings.maxPhotoDimensions = output.maxPhotoDimensions
        } else if output.connections.isEmpty {
            photoSettings.maxPhotoDimensions = device.activeFormat.supportedMaxPhotoDimensions.last ?? .zero
        }

        photoSettings.photoQualityPrioritization = .quality

        return photoSettings
    }

    private func capturePhotoFromOutput(_ output: AVCapturePhotoOutput, settings: AVCapturePhotoSettings) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let delegate = SinglePhotoCaptureDelegate(continuation: continuation)
            output.capturePhoto(with: settings, delegate: delegate)
        }
    }

    private func composePhotos(backData: Data, frontData: Data) throws -> Data {
        guard let backImage = CIImage(data: backData),
              let frontImage = CIImage(data: frontData) else {
            throw CameraError.configurationFailed
        }

        let outputSize = CGSize(width: 1920, height: 1080)
        let pipSize = CGSize(width: outputSize.width * 0.25, height: outputSize.height * 0.25)
        let pipPadding: CGFloat = 20

        let backExtent = backImage.extent
        let frontExtent = frontImage.extent

        let backScale = max(outputSize.width / backExtent.width, outputSize.height / backExtent.height)
        let backScaled = backImage.transformed(by: CGAffineTransform(scaleX: backScale, y: backScale))

        let backCropped = backScaled.cropped(to: CGRect(
            x: (backScaled.extent.width - outputSize.width) / 2,
            y: (backScaled.extent.height - outputSize.height) / 2,
            width: outputSize.width,
            height: outputSize.height
        ))

        let backPositioned = backCropped.transformed(by: CGAffineTransform(
            translationX: -backCropped.extent.minX,
            y: -backCropped.extent.minY
        ))

        let frontScale = max(pipSize.width / frontExtent.width, pipSize.height / frontExtent.height)
        let frontScaled = frontImage.transformed(by: CGAffineTransform(scaleX: frontScale, y: frontScale))

        let frontCropped = frontScaled.cropped(to: CGRect(
            x: (frontScaled.extent.width - pipSize.width) / 2,
            y: (frontScaled.extent.height - pipSize.height) / 2,
            width: pipSize.width,
            height: pipSize.height
        ))

        let pipX = outputSize.width - pipSize.width - pipPadding
        let pipY = outputSize.height - pipSize.height - pipPadding

        let frontPositioned = frontCropped.transformed(by: CGAffineTransform(
            translationX: pipX - frontCropped.extent.minX,
            y: pipY - frontCropped.extent.minY
        ))

        let composite = frontPositioned.composited(over: backPositioned)

        let ciContext = CIContext(options: [.useSoftwareRenderer: false])

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let jpegData = ciContext.jpegRepresentation(
                of: composite,
                colorSpace: colorSpace,
                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.9]
              ) else {
            throw CameraError.configurationFailed
        }

        return jpegData
    }

    // MARK: - Movie capture
    /// Starts recording video. The video records until the user stops recording,
    /// which calls the following `stopRecording()` method.
    func startRecording() {
        // Verify session is running before starting recording (best practice per Apple docs)
        guard captureSession.isRunning else {
            logger.error("Cannot start recording: capture session is not running")
            return
        }
        movieCapture.startRecording()
    }

    /// Stops the recording and returns the captured movie.
    func stopRecording() async throws -> Movie {
        try await movieCapture.stopRecording()
    }

    /// Sets whether the app captures HDR video.
    func setHDRVideoEnabled(_ isEnabled: Bool) {
        // Bracket the following configuration in a begin/commit configuration pair.
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }
        do {
            // If the current device provides a 10-bit HDR format, enable it for use.
            if isEnabled, let device = currentDevice, let format = device.activeFormat10BitVariant {
                try device.lockForConfiguration()
                device.activeFormat = format
                device.unlockForConfiguration()
                isHDRVideoEnabled = true
            } else {
                // Use isMultiCamMode flag instead of type check
                if !isMultiCamMode {
                    captureSession.sessionPreset = .high
                }
                isHDRVideoEnabled = false
            }
        } catch {
            logger.error("Unable to obtain lock on device and can't enable HDR video capture.")
        }
    }

    /// Toggle Center Stage on/off for front camera during dual camera mode
    /// Note: Center Stage is not available on iPhone devices
    func toggleCenterStage() async {
        // Center Stage is only available on iPad and Mac, not iPhone
        logger.info("Center Stage toggle requested, but feature is not available on iPhone")
    }

    /// Enables or disables cinematic video capture (iOS 26+)
    /// Adds depth-of-field effects during video recording
    /// Note: This feature is planned for iOS 26 but API may not be available yet
    func setCinematicVideoEnabled(_ isEnabled: Bool) async {
        // Feature not yet available in current SDK
        logger.info("Cinematic video feature planned for future iOS release")
        isCinematicVideoSupported = false
        isCinematicVideoEnabled = false

        // Uncomment when iOS 26 SDK is available with this feature:
        /*
        guard #available(iOS 26.0, *) else {
            logger.info("Cinematic video requires iOS 26.0 or later")
            isCinematicVideoSupported = false
            return
        }

        guard let videoInput = activeVideoInput else {
            logger.warning("No active video input for cinematic video")
            return
        }

        let device = videoInput.device

        // Check if device supports cinematic video
        guard device.isCinematicVideoCaptureSupported else {
            logger.info("Cinematic video not supported on \(device.localizedName)")
            isCinematicVideoSupported = false
            return
        }

        isCinematicVideoSupported = true

        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            videoInput.isCinematicVideoCaptureEnabled = isEnabled
            isCinematicVideoEnabled = isEnabled

            logger.info("✅ Cinematic video \(isEnabled ? "enabled" : "disabled")")
        } catch {
            logger.error("Failed to configure cinematic video: \(error.localizedDescription)")
            isCinematicVideoEnabled = false
        }
        */
    }

    /// Checks if cinematic video is supported and updates the capability
    /// Note: Feature not yet available in current SDK
    private func updateCinematicVideoCapability() {
        // Feature not yet available
        isCinematicVideoSupported = false
        isCinematicVideoEnabled = false

        // Uncomment when iOS 26 SDK is available with this feature:
        /*
        if #available(iOS 26.0, *),
           let device = activeVideoInput?.device,
           device.isCinematicVideoCaptureSupported {
            isCinematicVideoSupported = true
        } else {
            isCinematicVideoSupported = false
            isCinematicVideoEnabled = false
        }
        */
    }

    // MARK: - Internal state management
    /// Updates the state of the actor to ensure its advertised capabilities are accurate.
    ///
    /// When the capture session changes, such as changing modes or input devices, the service
    /// calls this method to update its configuration and capabilities. The app uses this state to
    /// determine which features to enable in the user interface.
    private func updateCaptureCapabilities() {
        // Update the output service configuration.
        guard let device = currentDevice else {
            logger.warning("No current device available to update capture capabilities")
            return
        }
        outputServices.forEach { $0.updateConfiguration(for: device) }

        // Update cinematic video capability
        updateCinematicVideoCapability()

        // Build capabilities with responsive capture and cinematic video support
        let baseCapabilities: CaptureCapabilities
        switch captureMode {
        case .photo:
            baseCapabilities = photoCapture.capabilities
        case .video:
            baseCapabilities = movieCapture.capabilities
        }

        // Enhance with responsive capture support
        let isResponsive = photoCapture.output.isResponsiveCaptureSupported

        captureCapabilities = CaptureCapabilities(
            isLivePhotoCaptureSupported: baseCapabilities.isLivePhotoCaptureSupported,
            isHDRSupported: baseCapabilities.isHDRSupported,
            isResponsiveCaptureSupported: isResponsive,
            isCinematicVideoSupported: isCinematicVideoSupported
        )
    }

    /// Merge the `captureActivity` values of the photo and movie capture services,
    /// and assign the value to the actor's property.`
    private func observeOutputServices() {
        Publishers.Merge(photoCapture.$captureActivity, movieCapture.$captureActivity)
            .assign(to: &$captureActivity)
    }

    /// Observe when capture control enter and exit a fullscreen appearance.
    private func observeCaptureControlsState() {
        controlsDelegate.$isShowingFullscreenControls
            .assign(to: &$isShowingFullscreenControls)
    }

    /// Observe capture-related notifications.
    private func observeNotifications() {
        Task {
            for await reason in NotificationCenter.default.notifications(named: AVCaptureSession.wasInterruptedNotification)
                .compactMap({ $0.userInfo?[AVCaptureSessionInterruptionReasonKey] as AnyObject? })
                .compactMap({ AVCaptureSession.InterruptionReason(rawValue: $0.integerValue) }) {
                /// Set the `isInterrupted` state as appropriate.
                isInterrupted = [.audioDeviceInUseByAnotherClient, .videoDeviceInUseByAnotherClient].contains(reason)
            }
        }

        Task {
            // Await notification of the end of an interruption.
            for await _ in NotificationCenter.default.notifications(named: AVCaptureSession.interruptionEndedNotification) {
                isInterrupted = false
            }
        }

        Task {
            for await error in NotificationCenter.default.notifications(named: AVCaptureSession.runtimeErrorNotification)
                .compactMap({ $0.userInfo?[AVCaptureSessionErrorKey] as? AVError }) {

                // Log all runtime errors for FIG error diagnostics
                logger.error("❌ AVCaptureSession runtime error: \(error.localizedDescription)")
                logger.error("❌ Error code: \(error.code.rawValue)")

                // If the system resets media services, the capture session stops running.
                if error.code == .mediaServicesWereReset {
                    logger.warning("⚠️ Media services were reset - restarting session...")
                    if !captureSession.isRunning {
                        captureSession.startRunning()
                    }
                }
            }
        }
    }

    // MARK: - Dual Camera Recording

    /// Setup synchronizer for dual camera recording
    /// This configures the AVCaptureDataOutputSynchronizer to deliver synchronized
    /// video frames from both cameras, and sets up the audio delegate separately
    private func setupSynchronizer() {
        guard let backOutput = backVideoOutput,
              let frontOutput = frontVideoOutput else {
            logger.error("❌ Cannot setup synchronizer - missing video outputs")
            return
        }

        guard let audioOut = audioOutput else {
            logger.error("❌ Cannot setup audio delegate - missing audio output")
            return
        }

        // Create delegate helper - IMPORTANT: Must be retained!
        let delegate = DualRecordingDelegate(captureService: self, backOutput: backOutput, frontOutput: frontOutput)
        self.dualRecordingDelegate = delegate
        logger.info("📹 Created DualRecordingDelegate (retained)")

        // Create synchronizer (it becomes the delegate of the outputs automatically)
        let synchronizer = AVCaptureDataOutputSynchronizer(
            dataOutputs: [backOutput, frontOutput]
        )

        synchronizer.setDelegate(delegate, queue: synchronizerQueue)
        self.synchronizer = synchronizer
        logger.info("✅ Synchronizer configured with delegate on queue: \(self.synchronizerQueue.label)")

        // Setup audio delegate separately (audio is not part of synchronizer)
        // Use dedicated audio queue to prevent congestion on synchronizer queue
        audioOut.setSampleBufferDelegate(delegate, queue: audioQueue)
        logger.info("✅ Audio delegate configured on dedicated queue: \(self.audioQueue.label)")
        logger.info("🎧 Audio output will deliver samples to DualRecordingDelegate.captureOutput(_:didOutput:from:)")
    }

    /// Computed property to get back camera preview port
    var backCameraPreviewPort: AVCaptureInput.Port? {
        guard let backInput = backVideoInput,
              let backCamera = backCameraDevice else {
            return nil
        }

        return backInput.ports(
            for: .video,
            sourceDeviceType: backCamera.deviceType,
            sourceDevicePosition: backCamera.position
        ).first
    }

    /// Computed property to get front camera preview port
    var frontCameraPreviewPort: AVCaptureInput.Port? {
        guard let frontInput = frontVideoInput,
              let frontCamera = frontCameraDevice else {
            return nil
        }

        return frontInput.ports(
            for: .video,
            sourceDeviceType: frontCamera.deviceType,
            sourceDevicePosition: frontCamera.position
        ).first
    }

    /// Setup preview layer connections for dual camera mode
    /// Can be called while session is running - connections are added atomically
    func setupPreviewConnections(backLayer: AVCaptureVideoPreviewLayer, frontLayer: AVCaptureVideoPreviewLayer) async throws {
        guard let multiCamSession = captureSession as? AVCaptureMultiCamSession,
              let backPort = backCameraPreviewPort,
              let frontPort = frontCameraPreviewPort else {
            throw CameraError.setupFailed
        }

        // Set sessions first - this can be done without begin/commitConfiguration
        // The layers will start displaying frames as soon as connections are added
        backLayer.setSessionWithNoConnection(multiCamSession)
        frontLayer.setSessionWithNoConnection(multiCamSession)
        logger.info("✅ Preview layers attached to session")

        // Add connections atomically with minimal session disruption
        multiCamSession.beginConfiguration()
        
        // Create preview connections
        let backPreviewConnection = AVCaptureConnection(inputPort: backPort, videoPreviewLayer: backLayer)
        if multiCamSession.canAddConnection(backPreviewConnection) {
            multiCamSession.addConnection(backPreviewConnection)
            logger.info("✅ Added back camera preview connection")
        } else {
            logger.error("❌ Cannot add back camera preview connection")
        }

        let frontPreviewConnection = AVCaptureConnection(inputPort: frontPort, videoPreviewLayer: frontLayer)
        if multiCamSession.canAddConnection(frontPreviewConnection) {
            // Mirror front camera preview for natural selfie appearance
            if frontPreviewConnection.isVideoMirroringSupported {
                frontPreviewConnection.automaticallyAdjustsVideoMirroring = false
                frontPreviewConnection.isVideoMirrored = true
            }
            multiCamSession.addConnection(frontPreviewConnection)
            logger.info("✅ Added front camera preview connection (mirrored)")
        } else {
            logger.error("❌ Cannot add front camera preview connection")
        }
        
        multiCamSession.commitConfiguration()
        logger.info("🎥 Preview connections configured - frames should appear immediately")

        // Setup rotation coordinators per device to drive videoRotationAngle for preview and outputs
        await setupMultiCamRotationCoordinators(backLayer: backLayer, frontLayer: frontLayer)
    }

    /// Starts dual camera recording
    func startDualRecording() async throws -> URL {
        guard isMultiCamMode else {
            throw CameraError.multiCamNotSupported
        }

        // Verify session is running before starting recording (best practice per Apple docs)
        guard captureSession.isRunning else {
            logger.error("Cannot start dual recording: capture session is not running")
            throw CameraError.configurationFailed
        }

        // Update capture activity FIRST so UI responds immediately
        captureActivity = .movieCapture(duration: 0.0)
        logger.info("🎬 Starting dual camera recording...")

        // Generate output URL
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        // Create recorder
        let recorder = DualMovieRecorder()
        try await recorder.startRecording(to: outputURL)

        dualRecorder = recorder
        
        logger.info("🎬 Dual recording active - frames will be synchronized and composed")

        return outputURL
    }

    /// Stops dual camera recording
    func stopDualRecording() async throws -> Movie {
        guard let recorder = dualRecorder else {
            throw CameraError.configurationFailed
        }

        logger.info("🎬 Stopping dual camera recording...")
        let (composedURL, backURL, frontURL) = try await recorder.stopRecording()
        dualRecorder = nil

        // Note: synchronizer and delegate are NOT cleaned up here
        // They remain active for the lifetime of the multi-cam session
        // This allows recording to start/stop multiple times without reconfiguration
        // They will be cleaned up when switching to single camera mode or session teardown

        // Update capture activity to idle
        captureActivity = .idle
        logger.info("🎬 Dual recording stopped - 3 files saved: \(composedURL.lastPathComponent), \(backURL.lastPathComponent), \(frontURL.lastPathComponent)")

        return Movie(url: composedURL, backURL: backURL, frontURL: frontURL)
    }

    // MARK: - Nonisolated Bridge Methods for Delegate Callbacks

    /// Bridge method to process frame pairs from delegate callback to actor
    /// This method is nonisolated and can be called from any context
    nonisolated func processFramePair(back: CMSampleBuffer, front: CMSampleBuffer) {
        // Schedule work on the actor's executor (sessionQueue)
        Task {
            await self.dualRecorder?.processSynchronizedFrames(
                backBuffer: back,
                frontBuffer: front
            )
        }
    }

    /// Bridge method to process audio buffer from delegate callback to actor
    /// This method is nonisolated and can be called from any context
    nonisolated func processAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        // Schedule work on the actor's executor (sessionQueue)
        Task {
            await self.dualRecorder?.processAudio(sampleBuffer)
        }
    }
}

// MARK: - Dual Recording Delegate Helper

/// Helper class to bridge delegate callbacks to the actor-isolated CaptureService
private class DualRecordingDelegate: NSObject, AVCaptureDataOutputSynchronizerDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    weak var captureService: CaptureService?
    weak var backVideoOutput: AVCaptureVideoDataOutput?
    weak var frontVideoOutput: AVCaptureVideoDataOutput?

    init(captureService: CaptureService, backOutput: AVCaptureVideoDataOutput, frontOutput: AVCaptureVideoDataOutput) {
        self.captureService = captureService
        self.backVideoOutput = backOutput
        self.frontVideoOutput = frontOutput
        super.init()
    }

    func dataOutputSynchronizer(
        _ synchronizer: AVCaptureDataOutputSynchronizer,
        didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection
    ) {
        // CRITICAL: Match outputs by identity, NOT array order
        // Array order from synchronizer.dataOutputs is not guaranteed
        guard let backOutput = backVideoOutput,
              let frontOutput = frontVideoOutput else {
            return
        }

        // Get synchronized data using the stored output references
        guard let backData = synchronizedDataCollection.synchronizedData(for: backOutput) as? AVCaptureSynchronizedSampleBufferData,
              let frontData = synchronizedDataCollection.synchronizedData(for: frontOutput) as? AVCaptureSynchronizedSampleBufferData else {
            return
        }

        // Check for dropped frames
        guard !backData.sampleBufferWasDropped,
              !frontData.sampleBufferWasDropped else {
            return
        }

        let backBuffer = backData.sampleBuffer
        let frontBuffer = frontData.sampleBuffer

        // Process frames on actor's executor (properly isolated)
        // Use nonisolated method to bridge from delegate callback to actor
        captureService?.processFramePair(back: backBuffer, front: frontBuffer)
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Process audio on actor's executor (properly isolated)
        captureService?.processAudioBuffer(sampleBuffer)
    }
}

class CaptureControlsDelegate: NSObject, AVCaptureSessionControlsDelegate {

    @Published private(set) var isShowingFullscreenControls = false

    func sessionControlsDidBecomeActive(_ session: AVCaptureSession) {
        logger.debug("Capture controls active.")
    }

    func sessionControlsWillEnterFullscreenAppearance(_ session: AVCaptureSession) {
        isShowingFullscreenControls = true
        logger.debug("Capture controls will enter fullscreen appearance.")
    }

    func sessionControlsWillExitFullscreenAppearance(_ session: AVCaptureSession) {
        isShowingFullscreenControls = false
        logger.debug("Capture controls will exit fullscreen appearance.")
    }

    func sessionControlsDidBecomeInactive(_ session: AVCaptureSession) {
        logger.debug("Capture controls inactive.")
    }
}

private class SinglePhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {

    private let continuation: CheckedContinuation<Data, Error>
    private var photoData: Data?

    init(continuation: CheckedContinuation<Data, Error>) {
        self.continuation = continuation
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            continuation.resume(throwing: error)
            return
        }
        photoData = photo.fileDataRepresentation()
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error = error {
            continuation.resume(throwing: error)
            return
        }

        guard let photoData else {
            continuation.resume(throwing: PhotoCaptureError.noPhotoData)
            return
        }

        continuation.resume(returning: photoData)
    }
}
