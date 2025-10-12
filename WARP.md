# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Common developer commands

- List available schemes
```bash path=null start=null
xcodebuild -project AVCam.xcodeproj -list -json
```

- Build the main app for a Simulator (UI only; Simulator has no camera)
```bash path=null start=null
xcodebuild -project AVCam.xcodeproj -scheme AVCam -destination 'platform=iOS Simulator,name=iPhone 16' build
```

- Clean the build for a scheme
```bash path=null start=null
xcodebuild -project AVCam.xcodeproj -scheme AVCam clean
```

- Open the project in Xcode
```bash path=null start=null
xed .
```

Notes
- Running on a physical device is required for any camera functionality (iOS 18+). Configure signing for all three targets in Xcode: AVCam, AVCamCaptureExtension, AVCamControlCenterExtension.
- No test targets were found; there is no command to run a single test.
- No SwiftLint/SwiftFormat configuration detected.

## Big-picture architecture (how the app works)

- Entry and app shell
  - SwiftUI app entry in AVCam/AVCamApp.swift creates a CameraModel and shows CameraView.
  - Two extensions are included:
    - Locked Camera Capture extension (AVCamCaptureExtension/*) to launch from Lock Screen/Control Center and share state via CameraState.
    - Control Center widget extension (AVCamControlCenterExtension/*) for quick access.

- Model layer (state and persistence)
  - CameraModel (AVCam/CameraModel.swift): the main @MainActor observable model used by SwiftUI. Mediates between views and the capture pipeline.
  - CameraState (AVCam/Model/CameraState.swift): persisted capture preferences shared with the capture extension via AVCamCaptureIntent.
  - MediaLibrary (AVCam/Model/MediaLibrary.swift): actor that writes photos/movies to Photos and emits thumbnails.

- Capture pipeline (performance-critical, off main thread)
  - CaptureService (AVCam/CaptureService.swift): actor that owns the AVCaptureSession, inputs/outputs, and configuration.
    - Uses DeviceLookup (AVCam/Capture/DeviceLookup.swift) to discover devices and choose multi-cam-compatible formats.
    - Chooses AVCaptureMultiCamSession when supported; otherwise falls back to a single-camera AVCaptureSession.
    - In multi-cam mode:
      - Adds inputs/outputs with no automatic connections and manually wires them (addInputWithNoConnections/addOutputWithNoConnections + AVCaptureConnection).
      - Creates synchronized video delivery via AVCaptureDataOutputSynchronizer and forwards audio via AVCaptureAudioDataOutput.
      - Monitors hardwareCost/systemPressure to keep load < 1.0 and adjust frame rates under pressure.
      - Exposes preview ports for both cameras so the UI can connect dedicated preview layers.
    - In single-cam mode: configures the usual Photo/Video outputs and capture controls.

- Recording path (dual camera)
  - DualMovieRecorder (AVCam/Capture/DualMovieRecorder.swift): actor that writes composed video frames using AVAssetWriter.
    - Composes two camera feeds into a split-screen 1920x1080 output using Core Image (Metal-accelerated) and appends synchronized frames.
    - Handles audio samples and finalization.

- Preview/UI composition
  - Single camera preview uses CameraPreview (UIViewRepresentable) bound to the session’s preview layer.
  - Dual camera preview uses DualCameraPreviewView (UIKit view with two AVCaptureVideoPreviewLayers) wrapped by DualCameraPreview (SwiftUI).
    - CaptureService.setupPreviewConnections(backLayer:frontLayer:) performs manual, per-layer connections to the multi-cam session.
  - CameraView + CameraUI (SwiftUI) orchestrate the preview, capture gestures, capture mode switching, and overlays.
  - Overlays include MultiCamBadge, PerformanceOverlay, recording time, and Live Photo indicators.

## Repo-specific guidance and docs to be aware of

- README.md highlights (AVCam sample)
  - The app is SwiftUI + Swift concurrency (actors) over AVFoundation.
  - Simulator cannot access cameras; testing camera features requires a physical device (iOS 18+).
  - The project includes a LockedCameraCapture capture extension and a Control Center extension; set signing for each target.

- CLAUDE.md (dual-camera implementation instructions and expectations)
  - Primary implementation guide: DUAL_CAMERA_IMPLEMENTATION_GUIDE.md (path: /Users/iamabillionaire/Downloads/FreshAndSlow/DUAL_CAMERA_IMPLEMENTATION_GUIDE.md).
  - Organized into four phases: session setup; dual preview UI; synchronized recording pipeline; polish/optimization.
  - Device requirements: iPhone XS or later; iOS 18+ minimum; Liquid Glass UI elements target newer OS features.
  - Success criteria emphasize two live previews, synchronized recording, and performance budgets (< 1.0 hardware cost, ~30 fps).
  - Upgrades.md provides historical notes and prior conversion research.

## Constraints and environment notes

- Camera features require a physical iOS device (18+). The Simulator builds but shows no camera feed.
- Multi-camera features depend on device support and may fall back to single-camera automatically.
- Ensure signing is configured per-target before attempting to run on device.
- No tests or lint tools are configured in this repo at present.
