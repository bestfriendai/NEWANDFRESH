# Dual Camera App Implementation Guide
## Complete Blueprint for Converting AVCam to iOS 26 Dual Camera App with Liquid Glass Design

**Generated:** 2025-10-11
**Target:** iOS 26.0+
**Project:** AVCam → Dual Camera App
**Architecture:** Swift Concurrency + SwiftUI + AVFoundation

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Current Codebase Analysis](#current-codebase-analysis)
3. [iOS 26 & Liquid Glass Features](#ios-26--liquid-glass-features)
4. [AVFoundation Multi-Camera Technical Reference](#avfoundation-multi-camera-technical-reference)
5. [Implementation Plan](#implementation-plan)
6. [Phase 1: Multi-Camera Session Setup](#phase-1-multi-camera-session-setup)
7. [Phase 2: Dual Preview UI with Liquid Glass](#phase-2-dual-preview-ui-with-liquid-glass)
8. [Phase 3: Synchronized Recording Pipeline](#phase-3-synchronized-recording-pipeline)
9. [Phase 4: Polish & Optimization](#phase-4-polish--optimization)
10. [Testing & Validation](#testing--validation)
11. [Performance Optimization](#performance-optimization)
12. [Reference Documentation](#reference-documentation)

---

## Executive Summary

### Project Overview

This guide provides complete, step-by-step instructions for converting the existing AVCam sample application into a modern dual camera app featuring:

- **Simultaneous front and back camera capture**
- **Picture-in-picture (PiP) dual preview**
- **Synchronized dual-camera video recording with composited output**
- **iOS 26 Liquid Glass design language**
- **Hardware Camera Control button support**
- **AirPods remote capture support**
- **Performance optimization for thermal management**

### Current State

**AVCam** is Apple's official camera sample app:
- iOS 18+ deployment target (WWDC25 version)
- Modern SwiftUI + Swift Concurrency architecture
- Actor-based `CaptureService` for thread-safe camera operations
- Single camera with photo/video/Live Photo support
- Camera Control hardware button integration
- Already uses AVFoundation best practices

### Target State

**Dual Camera App** will extend AVCam with:
- `AVCaptureMultiCamSession` for simultaneous capture
- Two preview layers (full-screen primary + corner PiP secondary)
- Real-time frame composition for dual-camera video recording
- Liquid Glass UI design (`.glassEffect()` modifiers)
- Device capability detection with graceful fallback
- Optimized performance with thermal management

### Key Architectural Changes

| Component | Current | New |
|-----------|---------|-----|
| Session | `AVCaptureSession` | `AVCaptureMultiCamSession` |
| Connections | Implicit (automatic) | Manual (explicit wiring) |
| Preview | Single `AVCaptureVideoPreviewLayer` | Two preview layers with manual connections |
| Recording | `AVCaptureMovieFileOutput` | Custom pipeline: `AVCaptureVideoDataOutput` + `AVCaptureDataOutputSynchronizer` + `AVAssetWriter` |
| UI Style | Material-based blur | Liquid Glass (`.glassEffect()`) |

---

## Current Codebase Analysis

### Architecture Overview

**Pattern:** MVVM with Actor-based Concurrency

```
┌─────────────────────┐
│   CameraView.swift  │  SwiftUI Views
│   (SwiftUI)         │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  CameraModel.swift  │  Observable UI State
│  (@Observable)      │  (Main Actor)
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ CaptureService.swift│  Camera Operations
│  (Actor)            │  (Background)
└──────────┬──────────┘
           │
           ▼
     AVFoundation
```

### Core Files

#### Primary Files (Major Changes Required)

**`/AVCam/CaptureService.swift`** (Actor)
- **Current:** Manages `AVCaptureSession` with implicit connections
- **Changes:** Replace with `AVCaptureMultiCamSession`, manual connections, dual outputs
- **Complexity:** HIGH

**`/AVCam/Capture/MovieCapture.swift`**
- **Current:** Uses `AVCaptureMovieFileOutput` for single-camera recording
- **Changes:** Replace entirely with new `DualMovieRecorder` class using `AVAssetWriter`
- **Complexity:** HIGH

**`/AVCam/Capture/DeviceLookup.swift`**
- **Current:** Discovers single camera per position
- **Changes:** Add multi-cam device set discovery, return camera pairs
- **Complexity:** MEDIUM

**`/AVCam/CameraView.swift`** (SwiftUI)
- **Current:** Single camera preview container
- **Changes:** Integrate dual preview with PiP layout
- **Complexity:** MEDIUM

**`/AVCam/Views/CameraPreview.swift`** (UIViewRepresentable)
- **Current:** Single preview layer wrapper
- **Changes:** Create new `DualCameraPreviewView` with two preview layers
- **Complexity:** MEDIUM

#### Secondary Files (Minor Changes)

**`/AVCam/CameraModel.swift`**
- Minor changes to expose two preview layers and dual-camera state

**`/AVCam/Views/CameraUI.swift`**
- Add dual-camera indicators and controls

**`/AVCam/Model/DataTypes.swift`**
- Add new types for dual-camera state

### Current Strengths

✅ **Actor isolation** - Already prepared for complex state management
✅ **Modern Swift** - Async/await throughout
✅ **UIKit bridging** - Preview layer pattern easily extends to dual
✅ **Protocol abstraction** - `Camera` protocol for testing
✅ **Rotation handling** - Existing coordinator can manage both cameras
✅ **Media library integration** - Already handles file saving
✅ **Recent updates** - WWDC25 version includes Camera Control and AirPods support

---

## iOS 26 & Liquid Glass Features

### iOS 26 Release Information

- **Release Date:** September 15, 2025
- **Announced:** WWDC 2025 (June 9, 2025)
- **Target Deployment:** iOS 26.0+
- **Compatibility:** iPhone 16 series, iPhone 17 series fully supported

### New Camera Features in iOS 26

#### 1. AirPods Remote Control (H2 Chip)
Press and hold AirPods stem to take photos or record video remotely.

**Compatible Devices:**
- AirPods Pro 3
- AirPods Pro 2
- AirPods 4
- AirPods 4 with ANC

**Implementation:**
```swift
// Enable in CaptureService
captureSession.configuresApplicationAudioSessionForBluetoothHighQualityRecording = true
```

#### 2. Studio-Quality Audio Recording
When recording with AirPods, audio quality is significantly improved for content creation.

#### 3. Camera Control Button Integration
Physical hardware button on iPhone 16/17 for camera control.

**Already implemented in AVCam via:**
```swift
.onCameraCaptureEvent { event in
    // Handle hardware button press
}
```

#### 4. Cinematic Mode API
Third-party apps can now capture Cinematic mode video with depth effects.

**Future enhancement opportunity.**

### Liquid Glass Design Language

#### What is Liquid Glass?

Liquid Glass is Apple's new design language introduced in iOS 26, representing an evolution beyond flat design. It's characterized by:

1. **Optical Properties of Real Glass**
   - Refraction and reflection
   - Realistic lighting and shaders
   - Dynamic motion response
   - Physically accurate lensing

2. **Fluid, Responsive Behavior**
   - Floating elements above content
   - Rounded, translucent components
   - Subtle interactive animations
   - Depth-based visual hierarchy

3. **Environmental Awareness**
   - Adapts to light/dark appearance
   - Reacts to ambient light
   - Motion-reactive on mobile devices

#### SwiftUI Implementation

**The `.glassEffect()` Modifier:**

```swift
Text("Hello, World!")
    .padding()
    .glassEffect(.regular, in: .circle)
```

**Variants:**
- `.regular` - Standard glass effect
- `.clear` - More transparent
- `.identity` - Base variant

**Customization:**
```swift
.glassEffect(.regular, in: .capsule)
.tint(.blue.opacity(0.3))
```

**`GlassEffectContainer` for Animations:**

```swift
GlassEffectContainer {
    HStack {
        Button("Capture") { }
            .glassEffect(.regular, in: .circle)

        Button("Switch") { }
            .glassEffect(.regular, in: .circle)
    }
}
```

When child elements animate between states, they fluidly merge and separate rather than independently fading.

#### Application to Camera Apps

**Key Benefits:**
- Controls float above preview without obscuring view
- Transparent buttons maintain context awareness
- Clear functional layer separation from content
- Natural touch patterns with rounded forms
- Dynamic response to camera rotation and device orientation

**Design Guidelines:**
1. Layer thoughtfully (headers over glass panels)
2. Use blur with purpose (enhance contrast while maintaining lightness)
3. Prioritize content focus (minimal distractions)
4. Responsive elements (shrink/expand based on context)

---

## AVFoundation Multi-Camera Technical Reference

### Key Concepts

#### AVCaptureMultiCamSession

**Class:** `AVCaptureMultiCamSession` (subclass of `AVCaptureSession`)

**Purpose:** Enables simultaneous capture from multiple cameras of the same media type.

**Key Differences:**
- Supports multiple camera inputs simultaneously
- Requires manual connection management
- Does not support session presets
- Has `hardwareCost` property for bandwidth monitoring
- More restrictive format support

**Device Support Check:**
```swift
guard AVCaptureMultiCamSession.isMultiCamSupported else {
    // Fallback to single camera
    return
}
```

**Compatibility:**
- iPhone XS/XS Max/XR and later (iOS 13+)
- iPad Pro (iOS 13+)
- Requires A13 Bionic or newer

#### Hardware Cost

**Property:** `session.hardwareCost` (Float, 0.0 to 1.0+)

**Meaning:** Represents ISP (Image Signal Processor) bandwidth usage.

**Guidelines:**
- **< 1.0:** Acceptable, session will run
- **≥ 1.0:** Exceeded capacity, reduce resolution/frame rate
- Monitor during configuration to stay within limits

**Cost Reduction Strategies:**
1. Lower resolution (1920x1080 instead of 4K)
2. Reduce frame rate (30fps instead of 60fps)
3. Use binned formats
4. Disable one camera temporarily

#### System Pressure

**Property:** `device.systemPressureState`

**Levels:**
- `.nominal` - Normal operation
- `.fair` - Slightly elevated, monitor closely
- `.serious` - Reduce frame rate (30fps → 20fps)
- `.critical` - Aggressively reduce or disable camera
- `.shutdown` - System stopping capture

**Factors:**
- `.systemTemperature` - Device thermal state
- `.peakPower` - Battery/power limitations
- `.depthModuleTemperature` - TrueDepth camera temperature

**Response Strategy:**
```swift
device.observe(\.systemPressureState) { device, _ in
    let state = device.systemPressureState

    switch state.level {
    case .serious:
        // Reduce frame rate to 20fps
    case .critical:
        // Reduce to 15fps or disable one camera
    default:
        break
    }
}
```

#### Manual Connection Management

With `AVCaptureMultiCamSession`, you **must** manually wire inputs to outputs.

**Pattern:**
```swift
// 1. Add input without automatic connections
session.addInputWithNoConnections(backInput)

// 2. Add output without automatic connections
session.addOutputWithNoConnections(backVideoOutput)

// 3. Get the input port for video media
guard let backVideoPort = backInput.ports(
    for: .video,
    sourceDeviceType: backCamera.deviceType,
    sourceDevicePosition: backCamera.position
).first else { return }

// 4. Create manual connection
let backConnection = AVCaptureConnection(
    inputPorts: [backVideoPort],
    output: backVideoOutput
)

// 5. Add connection to session
if session.canAddConnection(backConnection) {
    session.addConnection(backConnection)
}
```

#### Format Selection

Not all formats support multi-camera capture.

**Check format support:**
```swift
for format in device.formats {
    if format.isMultiCamSupported {
        // Can be used in AVCaptureMultiCamSession
    }
}
```

**Recommended formats:**
- Binned formats up to 60 FPS
- 1920x1080 at 30 FPS
- 1920x1440 at 30 FPS

**Selection strategy:**
```swift
func selectOptimalFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
    device.formats
        .filter { $0.isMultiCamSupported }
        .filter { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return dimensions.width <= 1920 && dimensions.height <= 1080
        }
        .filter { format in
            format.videoSupportedFrameRateRanges.contains { range in
                range.maxFrameRate >= 30.0 && range.minFrameRate <= 30.0
            }
        }
        .first
}
```

#### AVCaptureDataOutputSynchronizer

**Purpose:** Coordinates time-matched delivery of data from multiple capture outputs.

**How it works:**
- First output in array acts as "master"
- Waits for all outputs to receive data with equal or later timestamp
- Hardware synchronization occurs at sensor level
- Single delegate callback delivers all synchronized data

**Setup:**
```swift
let synchronizer = AVCaptureDataOutputSynchronizer(
    dataOutputs: [backVideoOutput, frontVideoOutput]
)

synchronizer.setDelegate(self, queue: synchronizerQueue)
```

**Delegate:**
```swift
func dataOutputSynchronizer(
    _ synchronizer: AVCaptureDataOutputSynchronizer,
    didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection
) {
    guard let backData = synchronizedDataCollection.synchronizedData(for: backVideoOutput) as? AVCaptureSynchronizedSampleBufferData,
          let frontData = synchronizedDataCollection.synchronizedData(for: frontVideoOutput) as? AVCaptureSynchronizedSampleBufferData else {
        return
    }

    let backSampleBuffer = backData.sampleBuffer
    let frontSampleBuffer = frontData.sampleBuffer

    // Process synchronized frames
}
```

---

## Implementation Plan

### Overview

The conversion will be executed in four phases:

1. **Phase 1:** Multi-Camera Session Setup
2. **Phase 2:** Dual Preview UI with Liquid Glass
3. **Phase 3:** Synchronized Recording Pipeline
4. **Phase 4:** Polish & Optimization

### Timeline Estimate

- **Phase 1:** 4-6 hours
- **Phase 2:** 3-4 hours
- **Phase 3:** 6-8 hours
- **Phase 4:** 3-5 hours
- **Total:** 16-23 hours

### Prerequisites Checklist

Before starting:

- [ ] Read this entire guide
- [ ] Review `Upgrades.md` for additional context
- [ ] Backup current codebase (`git commit -m "Pre-dual-camera backup"`)
- [ ] Have iOS 26 compatible device for testing (Simulator doesn't support camera)
- [ ] Verify deployment target is iOS 18.0 minimum (iOS 26.0 for Liquid Glass)
- [ ] Understand Swift Concurrency (actors, async/await)
- [ ] Understand AVFoundation basics

---

## Phase 1: Multi-Camera Session Setup

### Objective

Replace `AVCaptureSession` with `AVCaptureMultiCamSession` and implement manual connection management for two cameras.

### Step 1.1: Update CaptureService - Session Type

**File:** `/AVCam/CaptureService.swift`

**Location:** Around line 30 (private properties section)

**Change:**
```swift
// OLD
private let captureSession = AVCaptureSession()

// NEW
private let captureSession: AVCaptureSession

init() {
    // Check multi-cam support and create appropriate session
    if AVCaptureMultiCamSession.isMultiCamSupported {
        self.captureSession = AVCaptureMultiCamSession()
    } else {
        self.captureSession = AVCaptureSession()
    }
}
```

**Add property to track multi-cam state:**
```swift
private(set) var isMultiCamMode: Bool = false
```

### Step 1.2: Update DeviceLookup - Multi-Cam Device Discovery

**File:** `/AVCam/Capture/DeviceLookup.swift`

**Add new computed property for multi-cam device pairs:**

```swift
/// Returns a pair of cameras suitable for multi-cam capture (back + front)
var multiCamDevicePair: (back: AVCaptureDevice, front: AVCaptureDevice)? {
    guard AVCaptureMultiCamSession.isMultiCamSupported else {
        return nil
    }

    // Discover back camera
    let backDiscovery = AVCaptureDevice.DiscoverySession(
        deviceTypes: [
            .builtInTripleCamera,
            .builtInDualWideCamera,
            .builtInDualCamera,
            .builtInWideAngleCamera
        ],
        mediaType: .video,
        position: .back
    )

    // Discover front camera
    let frontDiscovery = AVCaptureDevice.DiscoverySession(
        deviceTypes: [
            .builtInTrueDepthCamera,
            .builtInWideAngleCamera
        ],
        mediaType: .video,
        position: .front
    )

    guard let backCamera = backDiscovery.devices.first,
          let frontCamera = frontDiscovery.devices.first else {
        return nil
    }

    return (back: backCamera, front: frontCamera)
}
```

**Add format selection helper:**

```swift
/// Selects optimal format for multi-cam capture
func selectMultiCamFormat(for device: AVCaptureDevice, targetFPS: Int = 30) -> AVCaptureDevice.Format? {
    device.formats
        .filter { $0.isMultiCamSupported }
        .filter { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            // Limit to 1080p for performance
            return dimensions.width <= 1920 && dimensions.height <= 1440
        }
        .filter { format in
            format.videoSupportedFrameRateRanges.contains { range in
                range.maxFrameRate >= Double(targetFPS) &&
                range.minFrameRate <= Double(targetFPS)
            }
        }
        .first
}
```

### Step 1.3: CaptureService - Add Multi-Cam Properties

**File:** `/AVCam/CaptureService.swift`

**Add after existing input properties (around line 40):**

```swift
// Multi-camera specific properties
private var backCameraDevice: AVCaptureDevice?
private var frontCameraDevice: AVCaptureDevice?
private var backVideoInput: AVCaptureDeviceInput?
private var frontVideoInput: AVCaptureDeviceInput?

// Separate outputs for each camera
private var backVideoOutput: AVCaptureVideoDataOutput?
private var frontVideoOutput: AVCaptureVideoDataOutput?

// Output queues
private let backVideoQueue = DispatchQueue(label: "com.apple.avcam.backVideoQueue", qos: .userInitiated)
private let frontVideoQueue = DispatchQueue(label: "com.apple.avcam.frontVideoQueue", qos: .userInitiated)
```

### Step 1.4: CaptureService - Multi-Cam Setup Method

**File:** `/AVCam/CaptureService.swift`

**Add new method for multi-cam configuration:**

```swift
/// Configures multi-camera session with back and front cameras
private func configureMultiCamSession() throws {
    guard let multiCamSession = captureSession as? AVCaptureMultiCamSession else {
        throw CameraError.noCamerasAvailable
    }

    guard let devicePair = deviceLookup.multiCamDevicePair else {
        throw CameraError.noCamerasAvailable
    }

    multiCamSession.beginConfiguration()
    defer { multiCamSession.commitConfiguration() }

    // Store devices
    backCameraDevice = devicePair.back
    frontCameraDevice = devicePair.front

    // Select and apply formats
    try configureMultiCamFormats(back: devicePair.back, front: devicePair.front)

    // Add inputs without automatic connections
    try addMultiCamInputs(back: devicePair.back, front: devicePair.front)

    // Add outputs without automatic connections
    try addMultiCamOutputs()

    // Create manual connections
    try createMultiCamConnections()

    // Add audio input (shared)
    try addAudioInput()

    // Check hardware cost
    let hardwareCost = multiCamSession.hardwareCost
    logger.info("Multi-cam hardware cost: \(hardwareCost)")

    guard hardwareCost < 1.0 else {
        throw CameraError.configurationFailed
    }

    // Monitor system pressure for both devices
    observeSystemPressure(for: devicePair.back)
    observeSystemPressure(for: devicePair.front)

    isMultiCamMode = true
}

/// Configure formats for multi-cam mode
private func configureMultiCamFormats(back: AVCaptureDevice, front: AVCaptureDevice) throws {
    // Back camera - higher resolution (primary)
    if let backFormat = deviceLookup.selectMultiCamFormat(for: back, targetFPS: 30) {
        try back.lockForConfiguration()
        back.activeFormat = backFormat
        back.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
        back.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
        back.unlockForConfiguration()
    }

    // Front camera - lower resolution (PiP)
    if let frontFormat = deviceLookup.selectMultiCamFormat(for: front, targetFPS: 30) {
        try front.lockForConfiguration()
        front.activeFormat = frontFormat
        front.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
        front.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
        front.unlockForConfiguration()
    }
}

/// Add multi-cam inputs without automatic connections
private func addMultiCamInputs(back: AVCaptureDevice, front: AVCaptureDevice) throws {
    guard let multiCamSession = captureSession as? AVCaptureMultiCamSession else {
        throw CameraError.configurationFailed
    }

    // Back camera input
    let backInput = try AVCaptureDeviceInput(device: back)
    guard multiCamSession.canAddInput(backInput) else {
        throw CameraError.configurationFailed
    }
    multiCamSession.addInputWithNoConnections(backInput)
    backVideoInput = backInput

    // Front camera input
    let frontInput = try AVCaptureDeviceInput(device: front)
    guard multiCamSession.canAddInput(frontInput) else {
        throw CameraError.configurationFailed
    }
    multiCamSession.addInputWithNoConnections(frontInput)
    frontVideoInput = frontInput
}

/// Add multi-cam outputs without automatic connections
private func addMultiCamOutputs() throws {
    guard let multiCamSession = captureSession as? AVCaptureMultiCamSession else {
        throw CameraError.configurationFailed
    }

    // Back camera video output
    let backOutput = AVCaptureVideoDataOutput()
    backOutput.videoSettings = [
        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
    ]
    backOutput.alwaysDiscardsLateVideoFrames = true

    guard multiCamSession.canAddOutput(backOutput) else {
        throw CameraError.configurationFailed
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
        throw CameraError.configurationFailed
    }
    multiCamSession.addOutputWithNoConnections(frontOutput)
    frontVideoOutput = frontOutput
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
        throw CameraError.configurationFailed
    }

    // Back camera connection
    guard let backVideoPort = backInput.ports(
        for: .video,
        sourceDeviceType: backCamera.deviceType,
        sourceDevicePosition: backCamera.position
    ).first else {
        throw CameraError.configurationFailed
    }

    let backConnection = AVCaptureConnection(inputPorts: [backVideoPort], output: backOutput)
    guard multiCamSession.canAddConnection(backConnection) else {
        throw CameraError.configurationFailed
    }

    if backConnection.isVideoStabilizationSupported {
        backConnection.preferredVideoStabilizationMode = .auto
    }

    multiCamSession.addConnection(backConnection)

    // Front camera connection
    guard let frontVideoPort = frontInput.ports(
        for: .video,
        sourceDeviceType: frontCamera.deviceType,
        sourceDevicePosition: frontCamera.position
    ).first else {
        throw CameraError.configurationFailed
    }

    let frontConnection = AVCaptureConnection(inputPorts: [frontVideoPort], output: frontOutput)
    guard multiCamSession.canAddConnection(frontConnection) else {
        throw CameraError.configurationFailed
    }

    if frontConnection.isVideoStabilizationSupported {
        frontConnection.preferredVideoStabilizationMode = .auto
    }

    multiCamSession.addConnection(frontConnection)
}

/// Monitor system pressure for a device
private func observeSystemPressure(for device: AVCaptureDevice) {
    let observation = device.observe(\.systemPressureState, options: .new) { [weak self] device, _ in
        Task { @MainActor [weak self] in
            await self?.handleSystemPressure(state: device.systemPressureState, for: device)
        }
    }
    // Store observation to keep it alive (add to observations array)
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
        await stop()

    default:
        break
    }
}
```

### Step 1.5: Update Start Method

**File:** `/AVCam/CaptureService.swift`

**Modify the `start()` method to use multi-cam when available:**

```swift
func start() async throws {
    guard await authorizeAccess() else {
        throw CameraError.notAuthorized
    }

    // Check if multi-cam is supported and configure accordingly
    if AVCaptureMultiCamSession.isMultiCamSupported {
        try configureMultiCamSession()
    } else {
        // Fallback to existing single camera configuration
        try configureSingleCameraSession() // existing logic
    }

    // Start the session on background thread
    captureSession.startRunning()

    logger.info("Capture session started - Multi-cam mode: \(isMultiCamMode)")
}
```

### Step 1.6: Add Error Handling

**File:** `/AVCam/Model/DataTypes.swift`

**Add to `CameraError` enum (around line 80):**

```swift
case multiCamNotSupported
case hardwareCostExceeded
case connectionFailed
```

### Testing Phase 1

**Verify:**
1. ✅ App launches without crashes
2. ✅ Multi-cam support detected on compatible devices
3. ✅ Session starts successfully
4. ✅ Hardware cost logged and < 1.0
5. ✅ No preview yet (expected - that's Phase 2)

**Test on:**
- iPhone XS or later
- Check console logs for "Multi-cam hardware cost" message

---

## Phase 2: Dual Preview UI with Liquid Glass

### Objective

Create two preview layers (full-screen primary + corner PiP secondary) with iOS 26 Liquid Glass design.

### Step 2.1: Create DualCameraPreviewView

**New File:** `/AVCam/Views/DualCameraPreviewView.swift`

**Create new file with:**

```swift
import UIKit
import AVFoundation

/// Container view for dual camera preview layers (back + front)
class DualCameraPreviewView: UIView {

    // MARK: - Properties

    /// Back camera preview layer (full screen)
    let backPreviewLayer: AVCaptureVideoPreviewLayer

    /// Front camera preview layer (PiP)
    let frontPreviewLayer: AVCaptureVideoPreviewLayer

    /// PiP position
    enum PiPPosition {
        case topRight
        case topLeft
        case bottomRight
        case bottomLeft
    }

    var pipPosition: PiPPosition = .topRight {
        didSet {
            updatePiPLayout()
        }
    }

    private let pipSize = CGSize(width: 150, height: 200)
    private let pipPadding: CGFloat = 16

    // MARK: - Initialization

    init(session: AVCaptureSession) {
        // Create back camera preview (full screen)
        backPreviewLayer = AVCaptureVideoPreviewLayer()
        backPreviewLayer.videoGravity = .resizeAspectFill

        // Create front camera preview (PiP)
        frontPreviewLayer = AVCaptureVideoPreviewLayer()
        frontPreviewLayer.videoGravity = .resizeAspectFill
        frontPreviewLayer.cornerRadius = 12
        frontPreviewLayer.masksToBounds = true

        super.init(frame: .zero)

        // Add layers
        layer.addSublayer(backPreviewLayer)
        layer.addSublayer(frontPreviewLayer)

        // Set session
        backPreviewLayer.session = session
        frontPreviewLayer.session = session
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()

        // Back camera fills entire view
        backPreviewLayer.frame = bounds

        // Update PiP position
        updatePiPLayout()
    }

    private func updatePiPLayout() {
        let pipFrame: CGRect

        switch pipPosition {
        case .topRight:
            pipFrame = CGRect(
                x: bounds.width - pipSize.width - pipPadding,
                y: safeAreaInsets.top + pipPadding,
                width: pipSize.width,
                height: pipSize.height
            )
        case .topLeft:
            pipFrame = CGRect(
                x: pipPadding,
                y: safeAreaInsets.top + pipPadding,
                width: pipSize.width,
                height: pipSize.height
            )
        case .bottomRight:
            pipFrame = CGRect(
                x: bounds.width - pipSize.width - pipPadding,
                y: bounds.height - pipSize.height - safeAreaInsets.bottom - pipPadding - 100, // 100 for toolbar
                width: pipSize.width,
                height: pipSize.height
            )
        case .bottomLeft:
            pipFrame = CGRect(
                x: pipPadding,
                y: bounds.height - pipSize.height - safeAreaInsets.bottom - pipPadding - 100,
                width: pipSize.width,
                height: pipSize.height
            )
        }

        frontPreviewLayer.frame = pipFrame
    }

    // MARK: - Connection Setup

    /// Must be called after view is added to session to create connections
    func setupConnections(
        backVideoPort: AVCaptureInput.Port,
        frontVideoPort: AVCaptureInput.Port
    ) throws {
        guard let session = backPreviewLayer.session as? AVCaptureMultiCamSession else {
            throw CameraError.configurationFailed
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // Back camera preview connection
        let backPreviewConnection = AVCaptureConnection(
            inputPort: backVideoPort,
            videoPreviewLayer: backPreviewLayer
        )
        if session.canAddConnection(backPreviewConnection) {
            session.addConnection(backPreviewConnection)
        }

        // Front camera preview connection
        let frontPreviewConnection = AVCaptureConnection(
            inputPort: frontVideoPort,
            videoPreviewLayer: frontPreviewLayer
        )
        if session.canAddConnection(frontPreviewConnection) {
            session.addConnection(frontPreviewConnection)
        }
    }
}
```

### Step 2.2: Create SwiftUI Wrapper for Dual Preview

**New File:** `/AVCam/Views/DualCameraPreview.swift`

**Create:**

```swift
import SwiftUI
import AVFoundation

/// SwiftUI wrapper for dual camera preview
struct DualCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let backVideoPort: AVCaptureInput.Port?
    let frontVideoPort: AVCaptureInput.Port?

    func makeUIView(context: Context) -> DualCameraPreviewView {
        let view = DualCameraPreviewView(session: session)

        // Setup connections if ports available
        if let backPort = backVideoPort,
           let frontPort = frontVideoPort {
            try? view.setupConnections(
                backVideoPort: backPort,
                frontVideoPort: frontPort
            )
        }

        return view
    }

    func updateUIView(_ uiView: DualCameraPreviewView, context: Context) {
        // Update if needed
    }
}
```

### Step 2.3: Update CameraModel to Expose Dual Preview

**File:** `/AVCam/CameraModel.swift`

**Add properties for preview ports:**

```swift
// Multi-camera preview ports
private(set) var backVideoPort: AVCaptureInput.Port?
private(set) var frontVideoPort: AVCaptureInput.Port?
private(set) var isMultiCamMode: Bool = false
```

**Update model to get ports from CaptureService after configuration.**

### Step 2.4: Update CaptureService to Provide Preview Ports

**File:** `/AVCam/CaptureService.swift`

**Add computed properties:**

```swift
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
```

### Step 2.5: Update CameraView with Dual Preview

**File:** `/AVCam/CameraView.swift`

**Replace preview section (around line 40) with:**

```swift
// Dual camera preview when in multi-cam mode
if model.isMultiCamMode {
    DualCameraPreview(
        session: model.captureSession,
        backVideoPort: model.backVideoPort,
        frontVideoPort: model.frontVideoPort
    )
    .ignoresSafeArea()
} else {
    // Existing single camera preview
    CameraPreview(provider: model.previewSource)
        .ignoresSafeArea()
}
```

### Step 2.6: Apply Liquid Glass Design to UI

**File:** `/AVCam/Views/CameraUI.swift`

**Update button styles to use `.glassEffect()`:**

**Replace `.ultraThinMaterial` backgrounds with Liquid Glass:**

```swift
// OLD
.background(.ultraThinMaterial)

// NEW (iOS 26+)
.glassEffect(.regular, in: .capsule)
```

**Example for MainToolbar buttons:**

**File:** `/AVCam/Views/Toolbars/MainToolbar.swift`

```swift
Button {
    action()
} label: {
    Image(systemName: "camera.rotate")
        .font(.title2)
        .foregroundStyle(.white)
        .padding(12)
}
.glassEffect(.regular, in: .circle)
```

**Wrap related buttons in `GlassEffectContainer` for smooth animations:**

```swift
GlassEffectContainer {
    HStack(spacing: 20) {
        // Thumbnail button
        Button { } label: { }
            .glassEffect(.regular, in: .circle)

        // Capture button
        Button { } label: { }
            .glassEffect(.regular, in: .circle)

        // Camera switch button
        Button { } label: { }
            .glassEffect(.regular, in: .circle)
    }
}
```

**Add tint for depth:**

```swift
.glassEffect(.regular, in: .circle)
.tint(.white.opacity(0.1))
```

### Step 2.7: Update Status Overlays with Liquid Glass

**File:** `/AVCam/Views/Overlays/StatusOverlay.swift`

**Update status messages:**

```swift
Text(message)
    .font(.headline)
    .foregroundStyle(.white)
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .glassEffect(.regular, in: .capsule)
    .transition(.scale.combined(with: .opacity))
```

### Testing Phase 2

**Verify:**
1. ✅ Two preview layers visible (back full-screen, front PiP in corner)
2. ✅ PiP preview has rounded corners
3. ✅ Both cameras showing live feed
4. ✅ Liquid Glass effect on buttons (transparent, glassy appearance)
5. ✅ Smooth animations when buttons appear/disappear

**Test on:**
- iPhone XS or later with iOS 26

---

## Phase 3: Synchronized Recording Pipeline

### Objective

Replace `AVCaptureMovieFileOutput` with custom recording pipeline using `AVCaptureVideoDataOutput`, `AVCaptureDataOutputSynchronizer`, Core Image composition, and `AVAssetWriter`.

### Architecture Overview

```
Back Camera → AVCaptureVideoDataOutput ─┐
                                         ├→ AVCaptureDataOutputSynchronizer
Front Camera → AVCaptureVideoDataOutput ─┘            ↓
                                              DualMovieRecorder (Actor)
                                                       ↓
                                              Core Image Compositor
                                              (PiP overlay on back camera)
                                                       ↓
Microphone → AVCaptureAudioDataOutput ─────→ AVAssetWriter → .mov file
```

### Step 3.1: Create DualMovieRecorder

**New File:** `/AVCam/Capture/DualMovieRecorder.swift`

**Create comprehensive recorder:**

```swift
import AVFoundation
import CoreImage
import os

/// Actor responsible for recording synchronized dual-camera video with PiP composition
actor DualMovieRecorder {

    private let logger = Logger(subsystem: "com.apple.avcam", category: "DualMovieRecorder")

    // MARK: - Properties

    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    private var isRecording = false
    private var recordingStartTime: CMTime?

    private let ciContext = CIContext()

    // Output configuration
    private let outputSize = CGSize(width: 1920, height: 1080)
    private let pipSize = CGSize(width: 300, height: 400)
    private let pipPadding: CGFloat = 32

    // MARK: - Public Interface

    /// Starts recording dual camera video
    func startRecording(to url: URL) throws {
        guard !isRecording else {
            throw RecorderError.alreadyRecording
        }

        // Remove existing file
        try? FileManager.default.removeItem(at: url)

        // Create asset writer
        let writer = try AVAssetWriter(url: url, fileType: .mov)

        // Configure video input
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: outputSize.width,
            AVVideoHeightKey: outputSize.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 10_000_000, // 10 Mbps
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoProfileLevelKey: AVVideoProfileLevelHEVCMainAutoLevel
            ]
        ]

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true

        // Create pixel buffer adaptor
        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: outputSize.width,
            kCVPixelBufferHeightKey as String: outputSize.height
        ]

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )

        guard writer.canAdd(videoInput) else {
            throw RecorderError.cannotAddInput
        }
        writer.add(videoInput)

        // Configure audio input
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 44100,
            AVEncoderBitRateKey: 128000
        ]

        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput.expectsMediaDataInRealTime = true

        guard writer.canAdd(audioInput) else {
            throw RecorderError.cannotAddInput
        }
        writer.add(audioInput)

        // Start writing
        guard writer.startWriting() else {
            throw RecorderError.cannotStartWriting
        }

        // Store references
        self.assetWriter = writer
        self.videoInput = videoInput
        self.audioInput = audioInput
        self.pixelBufferAdaptor = adaptor
        self.isRecording = true
        self.recordingStartTime = nil

        logger.info("Recording started to: \(url.path)")
    }

    /// Stops recording and finalizes the file
    func stopRecording() async throws -> URL {
        guard isRecording else {
            throw RecorderError.notRecording
        }

        isRecording = false

        guard let writer = assetWriter else {
            throw RecorderError.writerNotConfigured
        }

        // Mark inputs as finished
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()

        // Finish writing
        await writer.finishWriting()

        let outputURL = writer.outputURL

        // Clean up
        assetWriter = nil
        videoInput = nil
        audioInput = nil
        pixelBufferAdaptor = nil
        recordingStartTime = nil

        if writer.status == .completed {
            logger.info("Recording completed: \(outputURL.path)")
            return outputURL
        } else if let error = writer.error {
            throw error
        } else {
            throw RecorderError.writingFailed
        }
    }

    /// Processes synchronized video frames from both cameras
    func processSynchronizedFrames(
        backBuffer: CMSampleBuffer,
        frontBuffer: CMSampleBuffer
    ) {
        guard isRecording,
              let videoInput = videoInput,
              let adaptor = pixelBufferAdaptor,
              videoInput.isReadyForMoreMediaData else {
            return
        }

        // Get presentation time
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(backBuffer)

        // Start session on first frame
        if recordingStartTime == nil {
            assetWriter?.startSession(atSourceTime: presentationTime)
            recordingStartTime = presentationTime
        }

        // Compose frames
        guard let composedPixelBuffer = composeFrames(
            back: backBuffer,
            front: frontBuffer
        ) else {
            return
        }

        // Append to video
        adaptor.append(composedPixelBuffer, withPresentationTime: presentationTime)
    }

    /// Processes audio sample buffer
    func processAudio(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording,
              let audioInput = audioInput,
              audioInput.isReadyForMoreMediaData,
              recordingStartTime != nil else {
            return
        }

        audioInput.append(sampleBuffer)
    }

    // MARK: - Frame Composition

    private func composeFrames(back: CMSampleBuffer, front: CMSampleBuffer) -> CVPixelBuffer? {
        guard let backPixelBuffer = CMSampleBufferGetImageBuffer(back),
              let frontPixelBuffer = CMSampleBufferGetImageBuffer(front) else {
            return nil
        }

        // Create CIImages
        let backImage = CIImage(cvPixelBuffer: backPixelBuffer)
        let frontImage = CIImage(cvPixelBuffer: frontPixelBuffer)

        // Scale back camera to output size
        let backScaledImage = backImage.transformed(by: CGAffineTransform(
            scaleX: outputSize.width / backImage.extent.width,
            y: outputSize.height / backImage.extent.height
        ))

        // Calculate PiP transform (top-right corner)
        let pipX = outputSize.width - pipSize.width - pipPadding
        let pipY = pipPadding

        let pipScale = min(
            pipSize.width / frontImage.extent.width,
            pipSize.height / frontImage.extent.height
        )

        let pipTransform = CGAffineTransform(scaleX: pipScale, y: pipScale)
            .concatenating(CGAffineTransform(translationX: pipX, y: pipY))

        let frontScaledImage = frontImage.transformed(by: pipTransform)

        // Add rounded corner mask and border to PiP
        let frontWithBorder = frontScaledImage
            .applyingFilter("CIRoundedRectangle", parameters: [
                "inputRadius": 12
            ])

        // Composite: front over back
        let composited = frontWithBorder.composited(over: backScaledImage)

        // Render to pixel buffer
        guard let pixelBufferPool = pixelBufferAdaptor?.pixelBufferPool,
              let outputPixelBuffer = createPixelBuffer(from: pixelBufferPool) else {
            return nil
        }

        ciContext.render(composited, to: outputPixelBuffer)

        return outputPixelBuffer
    }

    private func createPixelBuffer(from pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(
            kCFAllocatorDefault,
            pool,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess else {
            return nil
        }

        return pixelBuffer
    }
}

// MARK: - Errors

enum RecorderError: Error {
    case alreadyRecording
    case notRecording
    case cannotAddInput
    case cannotStartWriting
    case writerNotConfigured
    case writingFailed
}
```

### Step 3.2: Update CaptureService - Add Synchronizer

**File:** `/AVCam/CaptureService.swift`

**Add properties:**

```swift
// Recording
private var dualRecorder: DualMovieRecorder?
private var synchronizer: AVCaptureDataOutputSynchronizer?
private let synchronizerQueue = DispatchQueue(label: "com.apple.avcam.synchronizer", qos: .userInitiated)
```

**Add audio output:**

```swift
private var audioOutput: AVCaptureAudioDataOutput?
```

**In `configureMultiCamOutputs()`, add audio output:**

```swift
// Audio output for recording
let audioOutput = AVCaptureAudioDataOutput()
guard multiCamSession.canAddOutput(audioOutput) else {
    throw CameraError.configurationFailed
}
multiCamSession.addOutput(audioOutput)
self.audioOutput = audioOutput
```

**Setup synchronizer after outputs are configured:**

```swift
private func setupSynchronizer() {
    guard let backOutput = backVideoOutput,
          let frontOutput = frontVideoOutput else {
        return
    }

    let synchronizer = AVCaptureDataOutputSynchronizer(
        dataOutputs: [backOutput, frontOutput]
    )

    synchronizer.setDelegate(self, queue: synchronizerQueue)
    self.synchronizer = synchronizer

    // Also setup audio delegate
    audioOutput?.setSampleBufferDelegate(self, queue: synchronizerQueue)
}
```

**Call `setupSynchronizer()` at end of `configureMultiCamSession()`.**

### Step 3.3: Implement Synchronizer Delegate

**File:** `/AVCam/CaptureService.swift`

**Add extension:**

```swift
// MARK: - AVCaptureDataOutputSynchronizerDelegate

extension CaptureService: AVCaptureDataOutputSynchronizerDelegate {
    nonisolated func dataOutputSynchronizer(
        _ synchronizer: AVCaptureDataOutputSynchronizer,
        didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection
    ) {
        guard let backOutput = backVideoOutput,
              let frontOutput = frontVideoOutput else {
            return
        }

        // Get synchronized data
        guard let backData = synchronizedDataCollection.synchronizedData(for: backOutput) as? AVCaptureSynchronizedSampleBufferData,
              let frontData = synchronizedDataCollection.synchronizedData(for: frontOutput) as? AVCaptureSynchronizedSampleBufferData,
              !backData.sampleBufferWasDropped,
              !frontData.sampleBufferWasDropped else {
            return
        }

        let backBuffer = backData.sampleBuffer
        let frontBuffer = frontData.sampleBuffer

        // Process frames for recording
        Task {
            await dualRecorder?.processSynchronizedFrames(
                backBuffer: backBuffer,
                frontBuffer: frontBuffer
            )
        }
    }
}

// MARK: - AVCaptureAudioDataOutputSampleBufferDelegate

extension CaptureService: AVCaptureAudioDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Audio samples
        Task {
            await dualRecorder?.processAudio(sampleBuffer)
        }
    }
}
```

### Step 3.4: Add Recording Control Methods

**File:** `/AVCam/CaptureService.swift`

**Add methods:**

```swift
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
```

### Step 3.5: Update CameraModel for Recording

**File:** `/AVCam/CameraModel.swift`

**Add recording state:**

```swift
private(set) var isDualRecording = false
```

**Add recording methods:**

```swift
func startDualRecording() async {
    do {
        let outputURL = try await captureService.startDualRecording()
        isDualRecording = true
        logger.info("Started dual recording to: \(outputURL)")
    } catch {
        logger.error("Failed to start dual recording: \(error)")
    }
}

func stopDualRecording() async {
    do {
        let outputURL = try await captureService.stopDualRecording()
        isDualRecording = false

        // Save to photo library
        try await mediaLibrary.saveVideo(at: outputURL)

        logger.info("Stopped dual recording, saved to library")
    } catch {
        logger.error("Failed to stop dual recording: \(error)")
    }
}
```

### Step 3.6: Update UI for Recording

**File:** `/AVCam/Views/Toolbars/MainToolbar.swift`

**Update capture button to start/stop dual recording when in multi-cam mode:**

```swift
Button {
    Task {
        if model.isMultiCamMode {
            if model.isDualRecording {
                await model.stopDualRecording()
            } else {
                await model.startDualRecording()
            }
        } else {
            // Existing single camera capture logic
        }
    }
} label: {
    ZStack {
        // Recording indicator
        if model.isDualRecording {
            RoundedRectangle(cornerRadius: 8)
                .fill(.red)
                .frame(width: 40, height: 40)
        } else {
            Circle()
                .fill(.red)
                .frame(width: 60, height: 60)
        }
    }
}
.glassEffect(.clear, in: .circle)
.scaleEffect(model.isDualRecording ? 0.8 : 1.0)
.animation(.easeInOut(duration: 0.2), value: model.isDualRecording)
```

### Step 3.7: Add Recording Timer Overlay

**File:** `/AVCam/Views/Overlays/RecordingTimerOverlay.swift`

**Update to show for dual recording:**

```swift
if model.isDualRecording {
    HStack {
        Circle()
            .fill(.red)
            .frame(width: 10, height: 10)

        Text(timerString)
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(.white)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .glassEffect(.regular, in: .capsule)
}
```

### Testing Phase 3

**Verify:**
1. ✅ Start recording button works in multi-cam mode
2. ✅ Recording timer appears and counts up
3. ✅ Both camera feeds continue showing during recording
4. ✅ Stop recording saves video to library
5. ✅ Playback shows back camera full-screen with front camera PiP overlay
6. ✅ Audio is recorded properly
7. ✅ Video quality is acceptable (1080p HEVC)

**Test on:**
- iPhone XS or later
- Record 10-30 second clips
- Check Photos app for saved videos

---

## Phase 4: Polish & Optimization

### Objective

Add final touches, error handling, performance optimizations, and user experience enhancements.

### Step 4.1: Add Multi-Cam Indicator Badge

**New File:** `/AVCam/Views/Overlays/MultiCamBadge.swift`

**Create:**

```swift
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
```

**Add to CameraView:**

```swift
if model.isMultiCamMode {
    VStack {
        HStack {
            MultiCamBadge()
            Spacer()
        }
        .padding()
        Spacer()
    }
}
```

### Step 4.2: Add Camera Swap Button (PiP Position Toggle)

**Update DualCameraPreviewView to support swapping:**

**File:** `/AVCam/Views/DualCameraPreviewView.swift`

**Add method:**

```swift
func swapCameras() {
    // Swap which camera is full-screen vs PiP
    CATransaction.begin()
    CATransaction.setAnimationDuration(0.3)
    CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))

    let tempFrame = backPreviewLayer.frame
    backPreviewLayer.frame = frontPreviewLayer.frame
    frontPreviewLayer.frame = tempFrame

    CATransaction.commit()
}
```

**Add button in CameraUI to trigger swap.**

### Step 4.3: Error Handling & Fallback UI

**Create error state view:**

**New File:** `/AVCam/Views/Overlays/MultiCamErrorView.swift`

```swift
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
    }
}
```

**Show when multi-cam setup fails.**

### Step 4.4: Performance Monitoring UI (Debug Only)

**File:** `/AVCam/Views/Overlays/PerformanceOverlay.swift`

```swift
import SwiftUI

struct PerformanceOverlay: View {
    let hardwareCost: Float
    let systemPressure: String

    var body: some View {
        #if DEBUG
        VStack(alignment: .leading, spacing: 4) {
            Text("Hardware Cost: \(String(format: "%.2f", hardwareCost))")
            Text("System Pressure: \(systemPressure)")
        }
        .font(.caption2.monospaced())
        .foregroundStyle(.white)
        .padding(8)
        .glassEffect(.regular, in: .rect(cornerRadius: 8))
        .padding()
        #endif
    }
}
```

**Add to CameraView for debugging.**

### Step 4.5: Optimize Frame Composition

**File:** `/AVCam/Capture/DualMovieRecorder.swift`

**Optimize `composeFrames` method:**

```swift
private func composeFrames(back: CMSampleBuffer, front: CMSampleBuffer) -> CVPixelBuffer? {
    guard let backPixelBuffer = CMSampleBufferGetImageBuffer(back),
          let frontPixelBuffer = CMSampleBufferGetImageBuffer(front),
          let pixelBufferPool = pixelBufferAdaptor?.pixelBufferPool,
          let outputPixelBuffer = createPixelBuffer(from: pixelBufferPool) else {
        return nil
    }

    // Use Metal-accelerated CIContext for performance
    let backImage = CIImage(cvPixelBuffer: backPixelBuffer)
    let frontImage = CIImage(cvPixelBuffer: frontPixelBuffer)

    // Optimize: Pre-calculate transforms if sizes don't change
    let backScale = outputSize.width / backImage.extent.width
    let backTransform = CGAffineTransform(scaleX: backScale, y: backScale)

    let pipScale = min(pipSize.width / frontImage.extent.width, pipSize.height / frontImage.extent.height)
    let pipX = outputSize.width - pipSize.width - pipPadding
    let pipY = pipPadding
    let pipTransform = CGAffineTransform(scaleX: pipScale, y: pipScale)
        .concatenating(CGAffineTransform(translationX: pipX, y: pipY))

    let backScaled = backImage.transformed(by: backTransform)
    let frontScaled = frontImage.transformed(by: pipTransform)

    // Add border to PiP for visibility
    let borderRect = CIImage(color: .white)
        .cropped(to: CGRect(
            origin: CGPoint(x: pipX - 2, y: pipY - 2),
            size: CGSize(width: pipSize.width + 4, height: pipSize.height + 4)
        ))

    let composite = frontScaled
        .composited(over: borderRect)
        .composited(over: backScaled)

    // Render efficiently
    ciContext.render(
        composite,
        to: outputPixelBuffer,
        bounds: CGRect(origin: .zero, size: outputSize),
        colorSpace: CGColorSpaceCreateDeviceRGB()
    )

    return outputPixelBuffer
}
```

### Step 4.6: Add Haptic Feedback

**File:** `/AVCam/CameraModel.swift`

**Add haptic feedback for recording start/stop:**

```swift
import UIKit

func startDualRecording() async {
    // Haptic feedback
    let generator = UIImpactFeedbackGenerator(style: .medium)
    generator.impactOccurred()

    do {
        let outputURL = try await captureService.startDualRecording()
        isDualRecording = true
        logger.info("Started dual recording to: \(outputURL)")
    } catch {
        logger.error("Failed to start dual recording: \(error)")
    }
}

func stopDualRecording() async {
    // Haptic feedback
    let generator = UIImpactFeedbackGenerator(style: .light)
    generator.impactOccurred()

    do {
        let outputURL = try await captureService.stopDualRecording()
        isDualRecording = false

        try await mediaLibrary.saveVideo(at: outputURL)
        logger.info("Stopped dual recording, saved to library")
    } catch {
        logger.error("Failed to stop dual recording: \(error)")
    }
}
```

### Step 4.7: Thermal Management Enhancement

**File:** `/AVCam/CaptureService.swift`

**Enhance `handleSystemPressure` to notify user:**

```swift
private func handleSystemPressure(state: AVCaptureDevice.SystemPressureState, for device: AVCaptureDevice) async {
    logger.warning("System pressure: \(state.level.rawValue) for device: \(device.localizedName)")

    switch state.level {
    case .serious:
        // Reduce frame rate
        try? device.lockForConfiguration()
        device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 20)
        device.unlockForConfiguration()

        // Notify user
        await notifyThermalWarning("Camera performance reduced due to temperature")

    case .critical:
        // Aggressively reduce frame rate
        try? device.lockForConfiguration()
        device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 15)
        device.unlockForConfiguration()

        await notifyThermalWarning("Camera overheating - quality reduced")

    case .shutdown:
        // Stop capture
        await stop()
        await notifyThermalWarning("Camera stopped due to overheating")

    default:
        break
    }
}

@MainActor
private func notifyThermalWarning(_ message: String) {
    // Post notification or update UI state
    NotificationCenter.default.post(
        name: Notification.Name("ThermalWarning"),
        object: nil,
        userInfo: ["message": message]
    )
}
```

**Display warnings in UI.**

### Step 4.8: Add Settings for Dual Camera

**New section in Settings (if exists):**

```swift
Section {
    Toggle("Enable Dual Camera", isOn: $enableDualCamera)

    if enableDualCamera {
        Picker("Primary Camera", selection: $primaryCamera) {
            Text("Back").tag(0)
            Text("Front").tag(1)
        }

        Picker("PiP Position", selection: $pipPosition) {
            Text("Top Right").tag(0)
            Text("Top Left").tag(1)
            Text("Bottom Right").tag(2)
            Text("Bottom Left").tag(3)
        }
    }
} header: {
    Text("Dual Camera")
}
```

### Step 4.9: Accessibility

**Add accessibility labels:**

**File:** `/AVCam/Views/Toolbars/MainToolbar.swift`

```swift
Button {
    // Capture action
} label: {
    // Button content
}
.accessibilityLabel(model.isDualRecording ? "Stop dual camera recording" : "Start dual camera recording")
.accessibilityHint(model.isDualRecording ? "Double tap to stop recording from both cameras" : "Double tap to start recording from both cameras simultaneously")
```

### Step 4.10: Memory Management

**File:** `/AVCam/Capture/DualMovieRecorder.swift`

**Ensure proper cleanup:**

```swift
deinit {
    // Cancel any in-progress writing
    assetWriter?.cancelWriting()
}
```

**File:** `/AVCam/CaptureService.swift`

**Add cleanup on stop:**

```swift
func stop() async {
    // Stop recording if active
    if let recorder = dualRecorder {
        try? await recorder.stopRecording()
        dualRecorder = nil
    }

    captureSession.stopRunning()

    // Clean up references
    backVideoOutput = nil
    frontVideoOutput = nil
    synchronizer = nil

    logger.info("Capture session stopped")
}
```

### Testing Phase 4

**Verify:**
1. ✅ Multi-cam badge displays when in dual mode
2. ✅ Error handling shows appropriate messages
3. ✅ Thermal warnings appear and frame rate reduces
4. ✅ Haptic feedback on recording start/stop
5. ✅ Performance is smooth (30fps, no dropped frames)
6. ✅ Memory usage is stable (no leaks)
7. ✅ Accessibility labels work with VoiceOver

**Performance Testing:**
- Record for 5+ minutes continuously
- Monitor thermal state
- Check for frame drops
- Verify memory doesn't grow unbounded

---

## Testing & Validation

### Device Requirements

**Minimum:**
- iPhone XS, XS Max, or XR
- iOS 18.0+

**Recommended:**
- iPhone 16 or 17 series
- iOS 26.0+

**Note:** Simulator does not support camera - physical device required.

### Test Scenarios

#### Functional Tests

1. **Multi-Cam Detection**
   - [ ] Launches successfully on compatible devices
   - [ ] Shows single camera fallback on incompatible devices
   - [ ] Displays multi-cam badge when in dual mode

2. **Preview**
   - [ ] Both camera previews visible simultaneously
   - [ ] Back camera shows full-screen
   - [ ] Front camera shows in PiP with rounded corners
   - [ ] PiP position is correct (top-right by default)
   - [ ] Previews update in real-time

3. **Recording**
   - [ ] Start recording button triggers dual recording
   - [ ] Recording timer displays and counts correctly
   - [ ] Both cameras continue showing during recording
   - [ ] Stop recording saves video successfully
   - [ ] Video appears in Photos app

4. **Video Output**
   - [ ] Playback shows back camera full-screen
   - [ ] Playback shows front camera as PiP overlay
   - [ ] PiP has border and rounded corners
   - [ ] Audio is synchronized
   - [ ] Video quality is 1080p HEVC
   - [ ] Duration matches expected length

5. **UI/UX**
   - [ ] Liquid Glass effect visible on buttons
   - [ ] Buttons are semi-transparent with blur
   - [ ] Animations are smooth
   - [ ] Haptic feedback on recording start/stop
   - [ ] Accessibility labels work

#### Performance Tests

1. **Hardware Cost**
   - [ ] Hardware cost stays < 1.0
   - [ ] Logged in console during startup
   - [ ] No warnings about exceeded bandwidth

2. **Frame Rate**
   - [ ] Consistent 30fps during preview
   - [ ] No visible stuttering
   - [ ] Recording maintains 30fps

3. **Thermal Management**
   - [ ] Device doesn't overheat during 5-minute recording
   - [ ] System pressure warnings appear if thermal state elevated
   - [ ] Frame rate automatically reduces under pressure
   - [ ] Recording stops if critical shutdown

4. **Memory**
   - [ ] Memory usage stable during long recordings
   - [ ] No memory leaks (use Instruments)
   - [ ] Memory released after stopping

5. **Battery**
   - [ ] Battery drain is acceptable (note: dual camera is intensive)
   - [ ] No unusual power consumption patterns

#### Edge Cases

1. **Interruptions**
   - [ ] Phone call during recording
   - [ ] App backgrounded during recording
   - [ ] Camera Control button press during recording
   - [ ] Low battery warning
   - [ ] Lock screen

2. **Errors**
   - [ ] Graceful handling when multi-cam fails
   - [ ] Clear error messages
   - [ ] Recovery to single camera mode

3. **Permissions**
   - [ ] Handles denied camera permission
   - [ ] Handles denied microphone permission
   - [ ] Handles denied photo library permission

### Validation Checklist

#### Code Quality

- [ ] No compiler warnings
- [ ] No force unwraps in production code
- [ ] Proper error handling throughout
- [ ] Actor isolation correctly implemented
- [ ] No data races (verified with Thread Sanitizer)

#### Architecture

- [ ] Clean separation of concerns
- [ ] CaptureService handles all AVFoundation
- [ ] CameraModel manages UI state
- [ ] Views are presentation only
- [ ] No business logic in views

#### Documentation

- [ ] Code comments for complex logic
- [ ] Documentation comments for public APIs
- [ ] README updated with dual camera info
- [ ] CLAUDE.md updated with instructions

---

## Performance Optimization

### Optimization Checklist

#### Frame Processing

- [ ] Use GPU-accelerated Core Image (not CPU)
- [ ] Reuse pixel buffers from pool
- [ ] Minimize pixel format conversions
- [ ] Avoid unnecessary copies

#### Threading

- [ ] Session configuration on background thread
- [ ] UI updates on MainActor
- [ ] Separate queues for each camera output
- [ ] Synchronizer on dedicated queue

#### Memory

- [ ] Release sample buffers promptly (CFRelease)
- [ ] Set `alwaysDiscardsLateVideoFrames = true`
- [ ] Limit output queue depth
- [ ] Clean up on stop

#### Thermal

- [ ] Monitor system pressure for both cameras
- [ ] Reduce frame rate under pressure
- [ ] Stop recording if critical
- [ ] Notify user of thermal state

#### Battery

- [ ] Stop session when app backgrounded
- [ ] Use appropriate format/resolution balance
- [ ] Don't over-process frames

### Profiling

Use Xcode Instruments to profile:

1. **Time Profiler** - CPU usage
2. **Allocations** - Memory usage and leaks
3. **Leaks** - Memory leaks specifically
4. **System Trace** - Overall system performance
5. **Metal System Trace** - GPU usage (Core Image)

### Benchmarks

**Target Performance:**
- Frame rate: 30fps consistently
- Hardware cost: < 0.8
- Memory: < 200MB during recording
- CPU: < 60% average
- GPU: < 50% average

---

## Reference Documentation

### Apple Documentation

1. **AVCaptureMultiCamSession**
   - https://developer.apple.com/documentation/avfoundation/avcapturemulticamsession

2. **AVMultiCamPiP Sample**
   - https://developer.apple.com/documentation/avfoundation/avmulticampip-capturing-from-multiple-cameras

3. **AVCam Sample**
   - https://developer.apple.com/documentation/avfoundation/avcam-building-a-camera-app

4. **Liquid Glass Guide**
   - https://developer.apple.com/documentation/TechnologyOverviews/liquid-glass

5. **WWDC 2019 Session 249**
   - "Introducing Multi-Camera Capture for iOS"
   - https://developer.apple.com/videos/play/wwdc2019/249/

### Community Resources

1. **Donny Wals - Liquid Glass Design**
   - Custom UI with Liquid Glass on iOS 26

2. **Swift with Majid - Glass Effects**
   - Glassifying custom SwiftUI views

3. **Stack Overflow**
   - Tags: `avcapturemulticamsession`, `avfoundation`

### Project Files Reference

**Modified Files:**
- `/AVCam/CaptureService.swift`
- `/AVCam/Capture/DeviceLookup.swift`
- `/AVCam/CameraModel.swift`
- `/AVCam/CameraView.swift`
- `/AVCam/Model/DataTypes.swift`
- `/AVCam/Views/CameraUI.swift`
- `/AVCam/Views/Toolbars/MainToolbar.swift`

**New Files:**
- `/AVCam/Capture/DualMovieRecorder.swift`
- `/AVCam/Views/DualCameraPreviewView.swift`
- `/AVCam/Views/DualCameraPreview.swift`
- `/AVCam/Views/Overlays/MultiCamBadge.swift`
- `/AVCam/Views/Overlays/MultiCamErrorView.swift`
- `/AVCam/Views/Overlays/PerformanceOverlay.swift`

---

## Summary

This guide provides complete, step-by-step instructions for converting AVCam to a dual camera app with iOS 26 Liquid Glass design. The implementation is structured in four phases:

1. **Phase 1:** Multi-camera session setup with manual connections
2. **Phase 2:** Dual preview UI with Liquid Glass effects
3. **Phase 3:** Synchronized recording with Core Image composition
4. **Phase 4:** Polish, optimization, and thermal management

The resulting app will capture simultaneous front and back camera video with picture-in-picture composition, modern Liquid Glass UI, and robust performance management.

**Estimated total implementation time: 16-23 hours**

---

**End of Implementation Guide**
