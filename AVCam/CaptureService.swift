/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
An object that manages a capture session and its inputs and outputs.
*/

import Foundation
@preconcurrency import AVFoundation
import Combine

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

    // Separate outputs for each camera
    fileprivate var backVideoOutput: AVCaptureVideoDataOutput?
    fileprivate var frontVideoOutput: AVCaptureVideoDataOutput?

    // Output queues
    private let backVideoQueue = DispatchQueue(label: "com.apple.avcam.backVideoQueue", qos: .userInitiated)
    private let frontVideoQueue = DispatchQueue(label: "com.apple.avcam.frontVideoQueue", qos: .userInitiated)

    // Recording
    fileprivate var dualRecorder: DualMovieRecorder?
    private var synchronizer: AVCaptureDataOutputSynchronizer?
    private let synchronizerQueue = DispatchQueue(label: "com.apple.avcam.synchronizer", qos: .userInitiated)
    private var audioOutput: AVCaptureAudioDataOutput?
    private var dualRecordingDelegate: DualRecordingDelegate?

    // The mode of capture, either photo or video. Defaults to photo.
    private(set) var captureMode = CaptureMode.photo
    
    // An object the service uses to retrieve capture devices.
    private let deviceLookup = DeviceLookup()
    
    // An object that monitors the state of the system-preferred camera.
    private let systemPreferredCamera = SystemPreferredCameraObserver()
    
    // An object that monitors video device rotations.
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator!
    private var rotationObservers = [AnyObject]()
    
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
    private func configureMultiCamSession() throws {
        guard let multiCamSession = captureSession as? AVCaptureMultiCamSession else {
            logger.error("Failed to cast session to AVCaptureMultiCamSession")
            throw CameraError.setupFailed
        }

        guard let devicePair = deviceLookup.multiCamDevicePair else {
            logger.error("No multi-cam device pair available")
            throw CameraError.setupFailed
        }

        logger.info("Starting multi-cam configuration with back: \(devicePair.back.localizedName), front: \(devicePair.front.localizedName)")

        // Store devices
        backCameraDevice = devicePair.back
        frontCameraDevice = devicePair.front

        // Configure formats BEFORE session configuration
        try configureMultiCamFormats(back: devicePair.back, front: devicePair.front)

        // Now configure the session
        multiCamSession.beginConfiguration()
        defer { multiCamSession.commitConfiguration() }

        // Add inputs without automatic connections
        try addMultiCamInputs(back: devicePair.back, front: devicePair.front)

        // Add audio input FIRST (before outputs)
        let defaultMic = try deviceLookup.defaultMic
        try addInput(for: defaultMic)

        // Add outputs without automatic connections
        try addMultiCamOutputs()

        // Create manual connections
        try createMultiCamConnections()

        // Check hardware cost
        let hardwareCost = multiCamSession.hardwareCost
        logger.info("Multi-cam hardware cost: \(hardwareCost)")

        guard hardwareCost < 1.0 else {
            logger.error("Hardware cost too high: \(hardwareCost) (must be < 1.0)")
            throw CameraError.setupFailed
        }

        logger.info("Hardware cost check passed: \(hardwareCost)")

        // Monitor system pressure for both devices
        observeSystemPressure(for: devicePair.back)
        observeSystemPressure(for: devicePair.front)

        // Setup synchronizer for recording
        setupSynchronizer()

        isMultiCamMode = true

        logger.info("Multi-camera session configuration complete")
    }

    /// Configure formats for multi-cam mode
    private func configureMultiCamFormats(back: AVCaptureDevice, front: AVCaptureDevice) throws {
        // Back camera - higher resolution (primary)
        guard let backFormat = deviceLookup.selectMultiCamFormat(for: back, targetFPS: 30) else {
            logger.error("No suitable multi-cam format found for back camera")
            throw CameraError.setupFailed
        }

        do {
            try back.lockForConfiguration()
            back.activeFormat = backFormat
            back.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            back.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            back.unlockForConfiguration()
            logger.info("Back camera format configured: \(backFormat)")
        } catch {
            logger.error("Failed to configure back camera format: \(error.localizedDescription)")
            throw error
        }

        // Front camera - lower resolution (PiP)
        guard let frontFormat = deviceLookup.selectMultiCamFormat(for: front, targetFPS: 30) else {
            logger.error("No suitable multi-cam format found for front camera")
            throw CameraError.setupFailed
        }

        do {
            try front.lockForConfiguration()
            front.activeFormat = frontFormat
            front.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            front.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            front.unlockForConfiguration()
            logger.info("Front camera format configured: \(frontFormat)")
        } catch {
            logger.error("Failed to configure front camera format: \(error.localizedDescription)")
            throw error
        }
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

        // Audio output for recording
        let audioOutput = AVCaptureAudioDataOutput()
        guard multiCamSession.canAddOutput(audioOutput) else {
            throw CameraError.addOutputFailed
        }
        multiCamSession.addOutput(audioOutput)
        self.audioOutput = audioOutput

        logger.info("Multi-cam outputs configured: back video, front video, audio")
    }

    /// Create manual connections for multi-cam outputs
    private func createMultiCamConnections() throws {
        guard let multiCamSession = captureSession as? AVCaptureMultiCamSession,
              let backInput = backVideoInput,
              let frontInput = frontVideoInput,
              let backOutput = backVideoOutput,
              let frontOutput = frontVideoOutput,
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

        multiCamSession.addConnection(frontOutputConnection)
        logger.info("Added front camera output connection")
    }

    /// Monitor system pressure for a device
    private func observeSystemPressure(for device: AVCaptureDevice) {
        let observation = device.observe(\.systemPressureState, options: .new) { [weak self] device, _ in
            Task { @MainActor [weak self] in
                await self?.handleSystemPressure(state: device.systemPressureState, for: device)
            }
        }
        // Store observation to keep it alive
        rotationObservers.append(observation)
    }

    private func handleSystemPressure(state: AVCaptureDevice.SystemPressureState, for device: AVCaptureDevice) async {
        logger.warning("System pressure: \(state.level.rawValue) for device: \(device.localizedName)")

        switch state.level {
        case .serious:
            // Reduce frame rate
            try? device.lockForConfiguration()
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 20)
            device.unlockForConfiguration()

        case .critical:
            // Aggressively reduce frame rate
            try? device.lockForConfiguration()
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 15)
            device.unlockForConfiguration()

        case .shutdown:
            // Stop capture
            captureSession.stopRunning()

        default:
            break
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
        // Configure the session and start it.
        try setUpSession()
        captureSession.startRunning()
        logger.info("Capture session started running. Multi-cam mode: \(self.isMultiCamMode)")
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
        if AVCaptureMultiCamSession.isMultiCamSupported {
            do {
                try configureMultiCamSession()
                multiCamSetupSucceeded = true
                logger.info("Multi-camera session configured successfully")
            } catch {
                logger.error("Multi-camera setup failed: \(error.localizedDescription). Falling back to single camera.")
                // Reset any partial multi-cam state
                backCameraDevice = nil
                frontCameraDevice = nil
                backVideoInput = nil
                frontVideoInput = nil
                backVideoOutput = nil
                frontVideoOutput = nil
                isMultiCamMode = false
            }
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
                captureSession.sessionPreset = captureMode == .photo ? .photo : .high
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
    private var currentDevice: AVCaptureDevice {
        // In multi-cam mode, return the back camera as the "current" device
        if isMultiCamMode, let device = backVideoInput?.device {
            return device
        }
        // In single-cam mode, use the active video input
        guard let device = activeVideoInput?.device else {
            fatalError("No device found for current video input.")
        }
        return device
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
            captureSession.sessionPreset = .photo
            captureSession.removeOutput(movieCapture.output)
        case .video:
            captureSession.sessionPreset = .high
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
        let selectedIndex = videoDevices.firstIndex(of: currentDevice) ?? 0
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
        guard let currentInput = activeVideoInput else { fatalError() }
        
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
        rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: videoPreviewLayer)
        
        // Set initial rotation state on the preview and output connections.
        updatePreviewRotation(rotationCoordinator.videoRotationAngleForHorizonLevelPreview)
        updateCaptureRotation(rotationCoordinator.videoRotationAngleForHorizonLevelCapture)
        
        // Cancel previous observations.
        rotationObservers.removeAll()
        
        // Add observers to monitor future changes.
        rotationObservers.append(
            rotationCoordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: .new) { [weak self] _, change in
                guard let self, let angle = change.newValue else { return }
                // Update the capture preview rotation.
                Task { await self.updatePreviewRotation(angle) }
            }
        )
        
        rotationObservers.append(
            rotationCoordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: .new) { [weak self] _, change in
                guard let self, let angle = change.newValue else { return }
                // Update the capture preview rotation.
                Task { await self.updateCaptureRotation(angle) }
            }
        )
    }
    
    private func updatePreviewRotation(_ angle: CGFloat) {
        let connection = videoPreviewLayer.connection
        Task { @MainActor in
            // Set initial rotation angle on the video preview.
            connection?.videoRotationAngle = angle
        }
    }
    
    private func updateCaptureRotation(_ angle: CGFloat) {
        // Update the orientation for all output services.
        outputServices.forEach { $0.setVideoRotationAngle(angle) }
    }
    
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        // Access the capture session's connected preview layer.
        guard let previewLayer = captureSession.connections.compactMap({ $0.videoPreviewLayer }).first else {
            fatalError("The app is misconfigured. The capture session should have a connection to a preview layer.")
        }
        return previewLayer
    }
    
    // MARK: - Automatic focus and exposure
    
    /// Performs a one-time automatic focus and expose operation.
    ///
    /// The app calls this method as the result of a person tapping on the preview area.
    func focusAndExpose(at point: CGPoint) {
        // The point this call receives is in view-space coordinates. Convert this point to device coordinates.
        let devicePoint = videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: point)
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
        let device = currentDevice
        
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
        try await photoCapture.capturePhoto(with: features)
    }
    
    // MARK: - Movie capture
    /// Starts recording video. The video records until the user stops recording,
    /// which calls the following `stopRecording()` method.
    func startRecording() {
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
            if isEnabled, let format = currentDevice.activeFormat10BitVariant {
                try currentDevice.lockForConfiguration()
                currentDevice.activeFormat = format
                currentDevice.unlockForConfiguration()
                isHDRVideoEnabled = true
            } else {
                captureSession.sessionPreset = .high
                isHDRVideoEnabled = false
            }
        } catch {
            logger.error("Unable to obtain lock on device and can't enable HDR video capture.")
        }
    }

    // MARK: - Internal state management
    /// Updates the state of the actor to ensure its advertised capabilities are accurate.
    ///
    /// When the capture session changes, such as changing modes or input devices, the service
    /// calls this method to update its configuration and capabilities. The app uses this state to
    /// determine which features to enable in the user interface.
    private func updateCaptureCapabilities() {
        // Update the output service configuration.
        outputServices.forEach { $0.updateConfiguration(for: currentDevice) }
        // Set the capture service's capabilities for the selected mode.
        switch captureMode {
        case .photo:
            captureCapabilities = photoCapture.capabilities
        case .video:
            captureCapabilities = movieCapture.capabilities
        }
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
                // If the system resets media services, the capture session stops running.
                if error.code == .mediaServicesWereReset {
                    if !captureSession.isRunning {
                        captureSession.startRunning()
                    }
                }
            }
        }
    }

    // MARK: - Dual Camera Recording

    /// Setup synchronizer for dual camera recording
    private func setupSynchronizer() {
        guard let backOutput = backVideoOutput,
              let frontOutput = frontVideoOutput else {
            logger.error("Cannot setup synchronizer - missing outputs")
            return
        }

        // Create delegate helper - IMPORTANT: Must be retained!
        let delegate = DualRecordingDelegate(captureService: self)
        self.dualRecordingDelegate = delegate

        // Create synchronizer (it becomes the delegate of the outputs automatically)
        let synchronizer = AVCaptureDataOutputSynchronizer(
            dataOutputs: [backOutput, frontOutput]
        )

        synchronizer.setDelegate(delegate, queue: synchronizerQueue)
        self.synchronizer = synchronizer

        logger.info("✅ Synchronizer configured with delegate")

        // Setup audio delegate separately
        audioOutput?.setSampleBufferDelegate(delegate, queue: synchronizerQueue)
        logger.info("✅ Audio delegate configured")
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
    /// Must be called AFTER preview layers are created
    func setupPreviewConnections(backLayer: AVCaptureVideoPreviewLayer, frontLayer: AVCaptureVideoPreviewLayer) throws {
        guard let multiCamSession = captureSession as? AVCaptureMultiCamSession,
              let backPort = backCameraPreviewPort,
              let frontPort = frontCameraPreviewPort else {
            throw CameraError.setupFailed
        }

        multiCamSession.beginConfiguration()
        defer { multiCamSession.commitConfiguration() }

        // Set sessions first
        backLayer.setSessionWithNoConnection(multiCamSession)
        frontLayer.setSessionWithNoConnection(multiCamSession)

        // Create preview connections
        let backPreviewConnection = AVCaptureConnection(inputPort: backPort, videoPreviewLayer: backLayer)
        if multiCamSession.canAddConnection(backPreviewConnection) {
            multiCamSession.addConnection(backPreviewConnection)
            logger.info("Added back camera preview connection")
        } else {
            logger.error("Cannot add back camera preview connection")
        }

        let frontPreviewConnection = AVCaptureConnection(inputPort: frontPort, videoPreviewLayer: frontLayer)
        if multiCamSession.canAddConnection(frontPreviewConnection) {
            multiCamSession.addConnection(frontPreviewConnection)
            logger.info("Added front camera preview connection")
        } else {
            logger.error("Cannot add front camera preview connection")
        }
    }

    /// Starts dual camera recording
    func startDualRecording() async throws -> URL {
        guard isMultiCamMode else {
            throw CameraError.multiCamNotSupported
        }

        // Generate output URL
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        // Create recorder
        let recorder = DualMovieRecorder()
        try await recorder.startRecording(to: outputURL)

        dualRecorder = recorder

        return outputURL
    }

    /// Stops dual camera recording
    func stopDualRecording() async throws -> URL {
        guard let recorder = dualRecorder else {
            throw CameraError.configurationFailed
        }

        let outputURL = try await recorder.stopRecording()
        dualRecorder = nil

        return outputURL
    }
}

// MARK: - Dual Recording Delegate Helper

/// Helper class to bridge delegate callbacks to the actor-isolated CaptureService
private class DualRecordingDelegate: NSObject, AVCaptureDataOutputSynchronizerDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    weak var captureService: CaptureService?

    init(captureService: CaptureService) {
        self.captureService = captureService
        super.init()
    }

    func dataOutputSynchronizer(
        _ synchronizer: AVCaptureDataOutputSynchronizer,
        didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection
    ) {
        // Extract outputs from synchronizer's data outputs array (these are the outputs we registered)
        guard synchronizer.dataOutputs.count == 2,
              let backOutput = synchronizer.dataOutputs[0] as? AVCaptureVideoDataOutput,
              let frontOutput = synchronizer.dataOutputs[1] as? AVCaptureVideoDataOutput else {
            return
        }

        // Get synchronized data immediately (must be synchronous)
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

        // Process frames asynchronously
        Task { [weak self] in
            guard let service = self?.captureService else { return }
            await service.dualRecorder?.processSynchronizedFrames(
                backBuffer: backBuffer,
                frontBuffer: frontBuffer
            )
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        Task { [weak self] in
            guard let service = self?.captureService else { return }
            await service.dualRecorder?.processAudio(sampleBuffer)
        }
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
