# Dual-Camera Audio: FIG Errors −19224 and −17281 — Root Cause and Solutions (iOS 26+)

Last updated: 2025-10-12

## 1) Executive Summary

FreshAndSlow occasionally logs two FIG-layer errors during multi‑camera bring‑up:
- FigAudioSession(AV) err=−19224
- FigXPCUtilities / FigCaptureSourceRemote err=−17281

These events typically occur during session initialization and audio route/config transitions. In most cases they’re transient and non‑fatal if the session proceeds to run and audio/video capture works. However, repeated occurrences or correlated audio loss indicate timing/config conflicts between the app’s AVAudioSession and the capture session.

Key recommendations (priority → highest first):
- Critical: Choose ONE audio‑session ownership model and follow it strictly
  - A) Let AVCaptureSession manage the app audio session (simplest, recommended if needs are basic)
  - B) Take manual control of AVAudioSession (more robust under route changes; requires precise timing)
- Important: Apply correct operation sequence and timing, especially around audio activation and session.startRunning()
- Important: Handle audio route changes and re-apply configuration
- Informational: Enable HQ Bluetooth for mic usage; prefer 48 kHz sample rate and small IO buffer for camera recording

## 2) Error Analysis

### FigAudioSession(AV) err=−19224
- What it means: Internal audio-session error surfaced by the FIG layer when the system can’t immediately satisfy a requested route or configuration (category/mode/options/sample rate/buffer) — often during transitions (start/stop running, route change, Bluetooth connect/disconnect).
- When it occurs: Around multi‑camera startRunning(), or when the session/framework toggles the shared AVAudioSession while your app is also doing so.
- Fatal? Usually non‑fatal if capture proceeds; becomes problematic if it repeats or coincides with lost audio in recordings.
- Mitigation:
  - Use a single owner for AVAudioSession (either AVCaptureSession or your app).
  - If app‑owned, activate after capture is fully configured but before starting to run; re-apply on route changes.

### FigCaptureSourceRemote err=−17281 (and related “err == 0” asserts)
- What it means: Transient failure while bringing up remote capture sources/ports across processes in the multi‑cam pipeline (FIG infrastructure). Common during multi‑cam initialization.
- When it occurs: During multi‑cam device/connection bring‑up; often appears a few times before session starts.
- Fatal? Typically non‑fatal if previews/recording start normally.
- Mitigation:
  - Correct sequencing: configure formats → add inputs/outputs → create manual connections → set delegates/synchronizer → activate audio (if app‑owned) → startRunning.
  - Keep hardware cost < 1.0 and use multi‑cam‑supported formats.

References (best available):
- AVCaptureMultiCamSession: https://developer.apple.com/documentation/avfoundation/avcapturemulticamsession
- AVMultiCamPiP sample: https://developer.apple.com/documentation/AVFoundation/avmulticampip-capturing-from-multiple-cameras
- AVCaptureSession.automaticallyConfiguresApplicationAudioSession: https://developer.apple.com/documentation/avfoundation/avcapturesession/automaticallyconfiguresapplicationaudiosession
- AVCaptureSession.configuresApplicationAudioSessionForBluetoothHighQualityRecording: https://developer.apple.com/documentation/avfoundation/avcapturesession/configuresapplicationaudiosessionforbluetoothhighqualityrecording
- Audio route changes: https://developer.apple.com/documentation/avfaudio/responding-to-audio-route-changes
- WWDC 2025 “Enhancing your camera experience with capture controls”: https://developer.apple.com/videos/play/wwdc2025/253/
- WWDC 2019 Session 249 “Introducing Multi-Camera Capture for iOS” (historical): https://developer.apple.com/videos/play/wwdc2019/249/

(Apple doesn’t publicly document FIG error codes; guidance relies on official AVFoundation/AVFAudio docs plus observed best practices.)

## 3) Current Implementation Review (FreshAndSlow)

Observed in CaptureService:
- Multi‑cam path sets:
  - `automaticallyConfiguresApplicationAudioSession = true`
  - `configuresApplicationAudioSessionForBluetoothHighQualityRecording = true`
- No explicit AVAudioSession category/mode/activation (session‑managed model)
- No explicit route‑change reconfiguration (relying on framework defaults)

Gaps vs. best practice:
- If you ever need deterministic audio behavior during route changes or want tighter control (e.g., specific buffer duration/sample rate), switch to app‑managed AVAudioSession — but then set `automaticallyConfiguresApplicationAudioSession = false` and handle activation timing and route changes carefully.
- Add a route‑change observer even in session‑managed model to log/react to transitions (diagnostics, retries if needed).

## 4) Recommended Solution

Pick one of the following models; do not mix them.

### Model A (Recommended if requirements are simple): Session‑managed audio (keep current, add route diagnostics)
- Keep:
  - `session.automaticallyConfiguresApplicationAudioSession = true`
  - `session.configuresApplicationAudioSessionForBluetoothHighQualityRecording = true`
- Ensure sequence:
  1) Configure formats (multi‑cam supported)
  2) Begin configuration
  3) Add audio input FIRST, then video outputs
  4) Create connections (manual wiring)
  5) Set sample buffer delegates and synchronizer
  6) Commit configuration
  7) startRunning()
- Add route‑change observer to log/diagnose persistent −19224; optionally pause/retry audio if necessary.

Example route observer (Swift Concurrency, actor‑friendly):
```swift
private func observeAudioRoutes() {
    Task { [weak self] in
        for await note in NotificationCenter.default.notifications(
            named: AVAudioSession.routeChangeNotification
        ) {
            self?.logger.info("Audio route changed: \(note.userInfo ?? [:])")
            // In session‑managed mode, usually no reconfig needed; this is diagnostic.
        }
    }
}
```

Pros: simplest, fewer moving parts; good for most apps. Cons: less explicit control; may still log occasional benign FIG messages during bring‑up.

### Model B: App‑managed AVAudioSession (max control; reduces conflicting changes)
- Set:
  - `session.automaticallyConfiguresApplicationAudioSession = false`
  - `session.configuresApplicationAudioSessionForBluetoothHighQualityRecording = true` (still useful)
- Configure and activate AVAudioSession after session is fully configured but before calling `startRunning()`.
- Re‑apply configuration on route changes.

Production‑ready configuration (tested pattern):
```swift
private func configureAppAudioSession() throws {
    let s = AVAudioSession.sharedInstance()
    try s.setCategory(.playAndRecord,
                      mode: .videoRecording,
                      options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
    // Camera pipelines typically prefer 48 kHz
    try? s.setPreferredSampleRate(48_000)
    // Small IO buffer for lower capture latency
    try? s.setPreferredIOBufferDuration(0.005)
    try s.setActive(true, options: [])
}

private func observeAudioRoutesAndReconfigure() {
    Task { [weak self] in
        for await _ in NotificationCenter.default.notifications(
            named: AVAudioSession.routeChangeNotification
        ) {
            do { try self?.configureAppAudioSession() }
            catch { self?.logger.error("AVAudioSession reconfig failed: \(error.localizedDescription)") }
        }
    }
}
```

Correct sequence (Model B):
1) Validate multi‑cam support and choose formats (multi‑cam‑supported)
2) beginConfiguration()
3) Add audio input FIRST, then video outputs, then audio/video outputs
4) Create manual connections
5) Set delegates and AVCaptureDataOutputSynchronizer
6) commitConfiguration()
7) try configureAppAudioSession()  // activate now
8) startRunning()

Pros: explicit control; fewer conflicting changes, often fewer FIG warnings; resilient to route changes. Cons: more code; you own all activation timing and must keep it correct across lifecycle.

### Bluetooth and microphones
- If you rely on AirPods/external Bluetooth mics:
  - Session‑managed: set `configuresApplicationAudioSessionForBluetoothHighQualityRecording = true`
  - App‑managed: include `.allowBluetooth` and `.allowBluetoothA2DP` options and prefer 48 kHz

### Recovery strategies
- If startRunning fails after persistent −19224/−17281:
  - Stop session, deactivate audio session (if app‑managed), sleep a short back‑off (e.g., 200–300 ms), re‑configure, try again.
  - Verify another app isn’t holding exclusive audio routes (phone call, CarPlay, FaceTime, etc.).

## 5) Implementation Checklist

- [ ] Decide and adopt ONE model (A: session‑managed, or B: app‑managed)
- [ ] Ensure correct multi‑cam configuration order (audio input → outputs → connections → delegates → synchronizer)
- [ ] If Model A: keep defaults; add route change observer for diagnostics
- [ ] If Model B: set `automaticallyConfiguresApplicationAudioSession = false`, implement `configureAppAudioSession()` and `observeAudioRoutesAndReconfigure()`
- [ ] Activate AVAudioSession after commitConfiguration and before startRunning
- [ ] Enable HQ Bluetooth (session flag or AVAudioSession options)
- [ ] Test with: device speaker, wired headphones, AirPods; toggle during preview & recording
- [ ] Confirm no persistent FIG errors; occasional one‑offs at bring‑up are acceptable if audio works

### Testing procedure (device required)
1) Launch in multi‑cam preview → verify dual previews are smooth at 30 fps
2) Start recording → record 10–20 s; stop → playback verifies audio present
3) While previewing, connect/disconnect AirPods → confirm no crashes; audio continues after route change
4) Repeat start/stop recording across route changes; watch console for −19224/−17281
5) Under stress (thermal fair/serious), ensure no repeated FIG errors and audio intact

### Expected console after fixes
- Single or zero FIG messages during initial bring‑up
- No repeating −19224/−17281
- Logs like:
  - “AVAudioSession configured/activated (48 kHz, 5 ms buffer)”
  - “Audio route changed: {…}, re-applied config” (Model B)

## 6) References
- AVCaptureMultiCamSession: https://developer.apple.com/documentation/avfoundation/avcapturemulticamsession
- AVMultiCamPiP sample: https://developer.apple.com/documentation/AVFoundation/avmulticampip-capturing-from-multiple-cameras
- AVCaptureSession.automaticallyConfiguresApplicationAudioSession: https://developer.apple.com/documentation/avfoundation/avcapturesession/automaticallyconfiguresapplicationaudiosession
- AVCaptureSession.configuresApplicationAudioSessionForBluetoothHighQualityRecording: https://developer.apple.com/documentation/avfoundation/avcapturesession/configuresapplicationaudiosessionforbluetoothhighqualityrecording
- AVAudioSession route changes: https://developer.apple.com/documentation/avfaudio/responding-to-audio-route-changes
- WWDC 2025 Session 253: Enhancing your camera experience with capture controls: https://developer.apple.com/videos/play/wwdc2025/253/
- WWDC 2019 Session 249: Introducing Multi‑Camera Capture for iOS: https://developer.apple.com/videos/play/wwdc2019/249/
- AVCaptureSession (overview): https://developer.apple.com/documentation/avfoundation/avcapturesession

Notes:
- FIG error codes aren’t publicly documented; guidance is derived from Apple’s official AVFoundation/AVFAudio docs and WWDC content, plus observed behavior in Apple samples and production apps.

