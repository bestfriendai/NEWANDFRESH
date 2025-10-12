# Claude Code Instructions for Dual Camera Implementation

## Overview

This document provides instructions for Claude Code to implement the dual camera conversion outlined in `DUAL_CAMERA_IMPLEMENTATION_GUIDE.md`.

## Implementation Guide Location

**Primary Document:** `/Users/iamabillionaire/Downloads/FreshAndSlow/DUAL_CAMERA_IMPLEMENTATION_GUIDE.md`

This comprehensive 900+ line guide contains:
- Complete technical research on iOS 26 and Liquid Glass design
- Full AVFoundation multi-camera API reference
- Step-by-step implementation instructions
- Code examples for every modification
- Testing and validation procedures
- Performance optimization guidelines

## How to Use This Guide

### For Claude Code

When implementing the dual camera conversion, follow these steps:

1. **Read the Implementation Guide First**
   ```
   Read the file: /Users/iamabillionaire/Downloads/FreshAndSlow/DUAL_CAMERA_IMPLEMENTATION_GUIDE.md
   ```
   Understand the complete architecture before starting any implementation.

2. **Follow the Phase Structure**
   The guide is organized in 4 sequential phases:
   - **Phase 1:** Multi-Camera Session Setup (4-6 hours)
   - **Phase 2:** Dual Preview UI with Liquid Glass (3-4 hours)
   - **Phase 3:** Synchronized Recording Pipeline (6-8 hours)
   - **Phase 4:** Polish & Optimization (3-5 hours)

3. **Complete Each Phase Fully**
   Do not move to the next phase until the current phase is:
   - Fully implemented
   - Tested according to the phase testing section
   - Verified to work correctly

4. **Use the Code Examples**
   The guide provides complete, production-ready code examples for:
   - New methods to add
   - Existing code to modify
   - New files to create
   - Exact line numbers and locations where possible

5. **Test After Each Phase**
   Each phase includes a "Testing Phase X" section with:
   - Verification checklist
   - Expected behavior
   - Device requirements

### Implementation Commands

#### Start Phase 1 - Multi-Camera Session Setup
```
Please implement Phase 1 from DUAL_CAMERA_IMPLEMENTATION_GUIDE.md:
- Update CaptureService to use AVCaptureMultiCamSession
- Modify DeviceLookup for multi-cam device discovery
- Add multi-cam properties and configuration methods
- Implement manual connection management
- Add system pressure monitoring

Follow all steps 1.1 through 1.6 exactly as documented.
```

#### Start Phase 2 - Dual Preview UI
```
Please implement Phase 2 from DUAL_CAMERA_IMPLEMENTATION_GUIDE.md:
- Create DualCameraPreviewView with two preview layers
- Create SwiftUI wrapper DualCameraPreview
- Update CameraModel to expose preview ports
- Update CameraView with dual preview logic
- Apply Liquid Glass design (.glassEffect()) to all UI elements

Follow all steps 2.1 through 2.7 exactly as documented.
```

#### Start Phase 3 - Recording Pipeline
```
Please implement Phase 3 from DUAL_CAMERA_IMPLEMENTATION_GUIDE.md:
- Create DualMovieRecorder actor with AVAssetWriter
- Add AVCaptureDataOutputSynchronizer to CaptureService
- Implement synchronized frame processing
- Add Core Image composition for PiP overlay
- Update CameraModel with recording controls
- Update UI for dual recording

Follow all steps 3.1 through 3.7 exactly as documented.
```

#### Start Phase 4 - Polish & Optimization
```
Please implement Phase 4 from DUAL_CAMERA_IMPLEMENTATION_GUIDE.md:
- Add multi-cam indicator badge
- Add camera swap functionality
- Implement error handling and fallback UI
- Add performance monitoring overlay (debug)
- Optimize frame composition
- Add haptic feedback
- Enhance thermal management
- Add accessibility labels

Follow all steps 4.1 through 4.10 exactly as documented.
```

### Progressive Implementation

If you want to implement all phases:

```
Please implement the complete dual camera conversion from DUAL_CAMERA_IMPLEMENTATION_GUIDE.md.

Follow these guidelines:
1. Read the entire guide first to understand the architecture
2. Implement Phase 1 completely and verify it works
3. Implement Phase 2 completely and verify it works
4. Implement Phase 3 completely and verify it works
5. Implement Phase 4 completely and verify it works
6. Run the full test suite from the "Testing & Validation" section

Create a todo list to track progress through all phases.
```

## Important Notes

### File Locations

All file paths in the implementation guide are absolute paths starting from:
```
/Users/iamabillionaire/Downloads/FreshAndSlow/
```

### Code Style

The guide follows the existing AVCam code style:
- Swift Concurrency (async/await, actors)
- SwiftUI for UI
- Actor isolation for CaptureService
- Observable pattern for CameraModel
- UIViewRepresentable for preview layers

### Device Requirements

**Testing requires a physical device:**
- iPhone XS or later for multi-camera support
- iOS 18.0+ minimum
- iOS 26.0+ for Liquid Glass features
- Simulator does NOT support camera functionality

### Key Architecture Changes

| Component | Before | After |
|-----------|--------|-------|
| Session | AVCaptureSession | AVCaptureMultiCamSession |
| Connections | Implicit | Manual (explicit wiring) |
| Preview | 1 layer | 2 layers (full-screen + PiP) |
| Recording | AVCaptureMovieFileOutput | Custom (AVAssetWriter + Compositor) |
| UI Style | Material blur | Liquid Glass (.glassEffect()) |

### Performance Targets

- Frame rate: 30fps consistently
- Hardware cost: < 0.8 (< 1.0 required)
- Memory: < 200MB during recording
- CPU: < 60% average
- GPU: < 50% average

## Troubleshooting

### If Multi-Camera Doesn't Work

1. Check `AVCaptureMultiCamSession.isMultiCamSupported` returns true
2. Verify device is iPhone XS or later
3. Check hardware cost is < 1.0 (logged in console)
4. Ensure formats have `isMultiCamSupported = true`
5. Verify manual connections are created correctly

### If Preview Doesn't Show

1. Check both preview layers have session set
2. Verify connections are added to session
3. Check `setupConnections()` is called after preview view creation
4. Ensure preview layer frames are non-zero

### If Recording Fails

1. Check synchronizer delegate is receiving frames
2. Verify AVAssetWriter started successfully
3. Check pixel buffer pool is available
4. Ensure output URL is writable location
5. Verify audio input is configured

### If Performance is Poor

1. Check system pressure state (should be nominal or fair)
2. Reduce resolution to 1920x1080 if needed
3. Verify frame rate is 30fps (not 60fps)
4. Check hardware cost < 1.0
5. Profile with Instruments (Time Profiler, Allocations)

## Additional Documentation

### Related Files

- **Upgrades.md** - Previous dual camera conversion notes (2,942 lines)
- **DUAL_CAMERA_IMPLEMENTATION_GUIDE.md** - Complete implementation guide (this is the primary reference)

### External References

1. **Apple Documentation:**
   - AVCaptureMultiCamSession: https://developer.apple.com/documentation/avfoundation/avcapturemulticamsession
   - AVMultiCamPiP Sample: https://developer.apple.com/documentation/avfoundation/avmulticampip-capturing-from-multiple-cameras
   - Liquid Glass: https://developer.apple.com/documentation/TechnologyOverviews/liquid-glass

2. **WWDC Sessions:**
   - WWDC 2019 Session 249: "Introducing Multi-Camera Capture for iOS"
   - WWDC 2025 Session 253: "Enhancing your camera experience with capture controls"

## Success Criteria

The implementation is complete when:

✅ Multi-camera session starts successfully on compatible devices
✅ Two preview layers display (back full-screen, front PiP)
✅ Liquid Glass effects applied to all UI elements
✅ Recording captures synchronized dual-camera video
✅ Playback shows composed video (back with front PiP overlay)
✅ Audio is synchronized with video
✅ Performance targets met (30fps, < 1.0 hardware cost)
✅ Thermal management reduces frame rate under pressure
✅ Error handling provides clear feedback
✅ All tests from "Testing & Validation" section pass

## Quick Start

To begin implementation immediately:

```
1. Read: DUAL_CAMERA_IMPLEMENTATION_GUIDE.md (Executive Summary and Architecture)
2. Create a git commit backup: git commit -am "Pre-dual-camera backup"
3. Start with Phase 1, Step 1.1
4. Follow each step sequentially
5. Test after completing each phase
6. Use a todo list to track progress
```

---

**Last Updated:** 2025-10-11
**Guide Version:** 1.0
**Target iOS:** 26.0+
**Minimum iOS:** 18.0+
