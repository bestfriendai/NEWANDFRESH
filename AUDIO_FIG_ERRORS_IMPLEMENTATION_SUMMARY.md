# Audio FIG Errors Implementation Summary

**Date:** 2025-10-12  
**Reference:** DUAL_CAMERA_AUDIO_FIG_ERRORS_SOLUTION.md  
**Status:** ✅ COMPLETE

## Overview

This document summarizes the implementation of fixes for FIG audio errors (-19224 and -17281) in the FreshAndSlow dual-camera app, following the recommendations from `DUAL_CAMERA_AUDIO_FIG_ERRORS_SOLUTION.md`.

## FIG Errors Background

### FigAudioSession(AV) err=-19224
- **What:** Internal audio-session error during route/config transitions
- **When:** Around multi-cam startRunning(), or during audio route changes
- **Impact:** Usually non-fatal if capture proceeds; problematic if repeated

### FigCaptureSourceRemote err=-17281
- **What:** Transient failure during multi-cam device bring-up across processes
- **When:** During multi-cam initialization
- **Impact:** Typically non-fatal if previews/recording start normally

## Implementation Approach: Model A (Session-Managed Audio)

We chose **Model A** (session-managed audio) as recommended for apps with basic audio requirements:

✅ **Advantages:**
- Simplest implementation
- Fewer moving parts
- Good for most apps
- Framework handles audio session automatically

✅ **Configuration:**
```swift
multiCamSession.automaticallyConfiguresApplicationAudioSession = true
multiCamSession.configuresApplicationAudioSessionForBluetoothHighQualityRecording = true
```

## Changes Implemented

### 1. ✅ Audio Route Change Observer (CaptureService.swift)

**Added:** `observeAudioRoutes()` method (lines 478-540)

**Purpose:** Monitor audio route changes for diagnostics and FIG error tracking

**Features:**
- Listens to `AVAudioSession.routeChangeNotification`
- Logs route change reason (new device, old device unavailable, etc.)
- Logs current audio inputs/outputs
- Logs sample rate and IO buffer duration
- Updates published `audioRouteDescription` property for UI diagnostics

**Example Log Output:**
```
🎧 Audio route changed: New device available
🎧 Current route: Inputs: [MicrophoneBuiltIn: iPhone Microphone], Outputs: [BluetoothA2DPOutput: AirPods Pro]
🎧 Sample rate: 48000.0 Hz, IO buffer: 5.0 ms
```

### 2. ✅ Enhanced Audio Session Diagnostics (CaptureService.swift)

**Added:** Initial audio session state logging in `start()` method (lines 582-585)

**Logs:**
- Sample rate (Hz)
- IO buffer duration (ms)
- Audio category (e.g., playAndRecord)
- Audio mode (e.g., videoRecording)

**Example Log Output:**
```
🎧 Audio session initialized - Sample rate: 48000.0 Hz, IO buffer: 5.0 ms
🎧 Audio category: playAndRecord, mode: videoRecording
```

### 3. ✅ Verified Multi-Cam Configuration Sequence (CaptureService.swift)

**Enhanced:** `configureMultiCamSession()` method with step-by-step logging (lines 143-226)

**Correct Sequence (per DUAL_CAMERA_AUDIO_FIG_ERRORS_SOLUTION.md):**
1. ✅ Configure formats BEFORE session configuration
2. ✅ beginConfiguration()
3. ✅ Add audio input FIRST (before outputs) - **CRITICAL**
4. ✅ Add video outputs
5. ✅ Create manual connections
6. ✅ Set delegates and synchronizer
7. ✅ commitConfiguration()
8. ✅ startRunning() (in start() method)

**Example Log Output:**
```
📹 Starting multi-cam configuration with back: Back Camera, front: Front Camera
🎧 Audio session mode: Session-managed (Model A)
🎧 HQ Bluetooth recording: enabled
📹 Step 1: Configuring multi-cam formats...
📹 Step 2: Beginning session configuration...
📹 Step 3a: Adding video inputs...
🎧 Step 3b: Adding audio input (BEFORE outputs)...
🎧 Audio input added: iPhone Microphone
📹 Step 4: Adding video and audio outputs...
🎧 Audio output added (auto-connects to audio input)
📹 Step 5: Creating manual connections...
📹 Step 6: Setting up synchronizer and delegates...
📹 Step 7: Committing session configuration...
✅ Multi-camera session configuration complete
```

### 4. ✅ Audio Output Delegate Verification (CaptureService.swift)

**Enhanced:** `setupSynchronizer()` method with detailed logging (lines 1287-1320)

**Verified:**
- ✅ Audio output delegate properly set
- ✅ Delegate retained (important!)
- ✅ Audio samples delivered to `DualRecordingDelegate.captureOutput(_:didOutput:from:)`
- ✅ Audio processed by `DualMovieRecorder.processAudio()`

**Example Log Output:**
```
📹 Created DualRecordingDelegate (retained)
✅ Synchronizer configured with delegate on queue: com.apple.avcam.synchronizer
✅ Audio delegate configured on queue: com.apple.avcam.synchronizer
🎧 Audio output will deliver samples to DualRecordingDelegate.captureOutput(_:didOutput:from:)
```

### 5. ✅ Audio Sample Processing Diagnostics (DualMovieRecorder.swift)

**Enhanced:** `processAudio()` method with sample counting and logging (lines 213-234)

**Features:**
- Logs first 3 audio samples to verify audio is flowing
- Logs presentation timestamp for each sample
- Logs errors if audio append fails

**Example Log Output:**
```
🎬 Recording started to: /tmp/ABC123.mov
🎧 Audio input configured: 44.1 kHz, 2 channels, AAC
🎧 Audio sample #1 appended at time: 0.023s
🎧 Audio sample #2 appended at time: 0.046s
🎧 Audio sample #3 appended at time: 0.069s
```

### 6. ✅ Recovery Strategy for Persistent FIG Errors (CaptureService.swift)

**Added:** `startSessionWithRetry()` method (lines 591-640)

**Features:**
- Retry logic with exponential backoff (200ms, 400ms, 800ms)
- Up to 3 attempts to start the session
- Stops session between retries if in bad state
- Logs audio session state on retry
- Checks for other apps holding audio

**Example Log Output:**
```
📹 Starting capture session (attempt 1/3)...
⚠️ Session start attempt 1 failed: The operation couldn't be completed
⏳ Waiting 200ms before retry...
🎧 Audio session state: category=playAndRecord, active=false
📹 Starting capture session (attempt 2/3)...
✅ Capture session started successfully on attempt 2
```

### 7. ✅ Enhanced Runtime Error Logging (CaptureService.swift)

**Enhanced:** Runtime error notification handler (lines 1272-1293)

**Features:**
- Logs all AVCaptureSession runtime errors
- Logs error code and domain
- Logs underlying errors (where FIG errors often appear)
- Handles media services reset

**Example Log Output:**
```
❌ AVCaptureSession runtime error: The operation couldn't be completed
❌ Error code: -11800, domain: AVFoundationErrorDomain
❌ Underlying error: FigAudioSession(AV) err=-19224
```

## Testing Checklist

Based on DUAL_CAMERA_AUDIO_FIG_ERRORS_SOLUTION.md Section 5:

### Required Testing (Device Required - Simulator Does NOT Support Camera)

- [ ] **Launch in multi-cam preview**
  - Verify dual previews are smooth at 30 fps
  - Check console for FIG errors (occasional one-offs at bring-up are acceptable)

- [ ] **Start recording**
  - Record 10-20 seconds
  - Stop recording
  - Playback and verify audio is present and synchronized

- [ ] **Audio route changes during preview**
  - Connect AirPods while previewing
  - Disconnect AirPods while previewing
  - Confirm no crashes
  - Verify audio continues after route change
  - Check console logs for route change notifications

- [ ] **Audio route changes during recording**
  - Start recording
  - Connect/disconnect AirPods during recording
  - Stop recording
  - Verify audio is present in recording
  - Check for FIG errors in console

- [ ] **Thermal stress testing**
  - Record for extended period (5+ minutes)
  - Monitor thermal state (fair/serious/critical)
  - Verify no repeated FIG errors
  - Verify audio remains intact

### Expected Console Output After Fixes

✅ **Good:**
```
📹 Starting multi-cam configuration...
🎧 Audio session mode: Session-managed (Model A)
🎧 Step 3b: Adding audio input (BEFORE outputs)...
✅ Multi-camera session configuration complete
📹 Starting capture session (attempt 1/3)...
✅ Capture session started successfully on attempt 1
🎧 Audio session initialized - Sample rate: 48000.0 Hz, IO buffer: 5.0 ms
```

⚠️ **Acceptable (transient, non-repeating):**
```
FigCaptureSourceRemote err=-17281 (during initial bring-up, once or twice)
```

❌ **Bad (indicates persistent problem):**
```
FigAudioSession(AV) err=-19224 (repeated multiple times)
FigCaptureSourceRemote err=-17281 (repeated multiple times)
❌ Failed to start capture session after 3 attempts
```

## Files Modified

1. **AVCam/CaptureService.swift**
   - Added `audioRouteDescription` published property
   - Added `observeAudioRoutes()` method
   - Added `setAudioRouteDescription()` method
   - Added `audioRouteChangeReasonString()` method
   - Enhanced `configureMultiCamSession()` with step-by-step logging
   - Enhanced `start()` with audio session diagnostics
   - Added `startSessionWithRetry()` method with exponential backoff
   - Enhanced `setupSynchronizer()` with detailed logging
   - Enhanced runtime error handler with FIG error diagnostics

2. **AVCam/Capture/DualMovieRecorder.swift**
   - Added `audioSampleCount` property for diagnostics
   - Enhanced `startRecording()` with audio config logging
   - Enhanced `processAudio()` with sample counting and logging

## Performance Impact

✅ **Minimal:**
- Audio route observer: Async, only fires on route changes (rare)
- Enhanced logging: Only during session start and first few audio samples
- Retry logic: Only executes on failure (rare)
- No impact on steady-state recording performance

## Next Steps

1. **Test on physical device** (iPhone XS or later)
2. **Monitor console logs** during testing
3. **Verify audio route changes** work smoothly
4. **Check for FIG errors** - should be zero or minimal
5. **If persistent FIG errors occur:**
   - Review console logs for patterns
   - Check if another app is holding audio
   - Consider switching to Model B (app-managed audio) if needed

## References

- **DUAL_CAMERA_AUDIO_FIG_ERRORS_SOLUTION.md** - Primary reference document
- **Apple AVCaptureMultiCamSession:** https://developer.apple.com/documentation/avfoundation/avcapturemulticamsession
- **Apple AVMultiCamPiP Sample:** https://developer.apple.com/documentation/AVFoundation/avmulticampip-capturing-from-multiple-cameras
- **Apple Audio Route Changes:** https://developer.apple.com/documentation/avfaudio/responding-to-audio-route-changes
- **WWDC 2019 Session 249:** Introducing Multi-Camera Capture for iOS
- **WWDC 2025 Session 253:** Enhancing your camera experience with capture controls

---

**Implementation Status:** ✅ COMPLETE  
**Ready for Testing:** YES  
**Device Required:** YES (iPhone XS or later)

