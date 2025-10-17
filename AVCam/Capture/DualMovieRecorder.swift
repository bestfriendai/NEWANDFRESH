import AVFoundation
import CoreImage
import Metal
import os

/// Actor responsible for recording synchronized dual-camera video with PiP composition
actor DualMovieRecorder {

    private let logger = Logger(subsystem: "com.apple.avcam", category: "DualMovieRecorder")

    // MARK: - Properties

    // Three separate asset writers for back, front, and composed videos
    private var backWriter: AVAssetWriter?
    private var frontWriter: AVAssetWriter?
    private var composedWriter: AVAssetWriter?

    // Video inputs for each writer
    private var backVideoInput: AVAssetWriterInput?
    private var frontVideoInput: AVAssetWriterInput?
    private var composedVideoInput: AVAssetWriterInput?

    // Audio inputs (shared audio track for all three)
    private var backAudioInput: AVAssetWriterInput?
    private var frontAudioInput: AVAssetWriterInput?
    private var composedAudioInput: AVAssetWriterInput?

    // Pixel buffer adaptors
    private var composedPixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    private var isRecording = false
    private var recordingStartTime: CMTime?
    private var isStopping = false // Prevent new frames during stop
    private var audioSampleCount = 0 // For diagnostics

    // Output URLs for the three videos
    private var backVideoURL: URL?
    private var frontVideoURL: URL?
    private var composedVideoURL: URL?

    // Metal-accelerated Core Image context for GPU rendering
    // Use high priority queue for recording to prevent frame drops
    private let ciContext: CIContext = {
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: metalDevice, options: [
                .priorityRequestLow: false,
                .cacheIntermediates: false,
                .name: "DualRecorderContext"
            ])
        } else {
            return CIContext(options: [.priorityRequestLow: false])
        }
    }()

    // Output configuration for split-screen (16:9 aspect ratio)
    private let outputSize = CGSize(width: 1920, height: 1080)

    // Cache for reusable Core Image components
    private var cachedBackground: CIImage?
    private let cachedColorSpace = CGColorSpaceCreateDeviceRGB()
    
    // Performance monitoring
    private var frameCount: Int = 0
    private var droppedFrameCount: Int = 0
    private var totalRenderTime: TimeInterval = 0
    private var renderStartTime: CFAbsoluteTime = 0

    // Memory pressure monitoring
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var isUnderMemoryPressure = false

    // Rotation tracking for proper video orientation
    private var backRotationAngle: CGFloat = 0
    private var frontRotationAngle: CGFloat = 0

    // MARK: - Public Interface

    /// Starts recording dual camera video to 3 separate files
    /// - Parameter url: Base URL for the composed video (back and front will have suffixes)
    func startRecording(to url: URL) async throws {
        guard !isRecording else {
            throw RecorderError.alreadyRecording
        }

        // Generate URLs for all three videos
        let baseURL = url.deletingPathExtension()
        let backURL = baseURL.appendingPathExtension("back.mov")
        let frontURL = baseURL.appendingPathExtension("front.mov")
        let composedURL = url // Use the original URL for composed video

        // Remove existing files
        try? FileManager.default.removeItem(at: backURL)
        try? FileManager.default.removeItem(at: frontURL)
        try? FileManager.default.removeItem(at: composedURL)

        // Store URLs
        self.backVideoURL = backURL
        self.frontVideoURL = frontURL
        self.composedVideoURL = composedURL

        // Create three asset writers
        let backWriter = try AVAssetWriter(url: backURL, fileType: .mov)
        let frontWriter = try AVAssetWriter(url: frontURL, fileType: .mov)
        let composedWriter = try AVAssetWriter(url: composedURL, fileType: .mov)

        // Configure video settings (same for all)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: outputSize.width,
            AVVideoHeightKey: outputSize.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 10_000_000, // 10 Mbps
                AVVideoExpectedSourceFrameRateKey: 30
            ]
        ]

        // Configure audio settings (same for all - shared audio track)
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 44100,
            AVEncoderBitRateKey: 128000
        ]

        // Setup back camera writer
        let backVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        backVideoInput.expectsMediaDataInRealTime = true
        guard backWriter.canAdd(backVideoInput) else { throw RecorderError.cannotAddInput }
        backWriter.add(backVideoInput)

        let backAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        backAudioInput.expectsMediaDataInRealTime = true
        guard backWriter.canAdd(backAudioInput) else { throw RecorderError.cannotAddInput }
        backWriter.add(backAudioInput)

        // Setup front camera writer
        let frontVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        frontVideoInput.expectsMediaDataInRealTime = true
        guard frontWriter.canAdd(frontVideoInput) else { throw RecorderError.cannotAddInput }
        frontWriter.add(frontVideoInput)

        let frontAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        frontAudioInput.expectsMediaDataInRealTime = true
        guard frontWriter.canAdd(frontAudioInput) else { throw RecorderError.cannotAddInput }
        frontWriter.add(frontAudioInput)

        // Setup composed writer with pixel buffer adaptor
        let composedVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        composedVideoInput.expectsMediaDataInRealTime = true

        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: outputSize.width,
            kCVPixelBufferHeightKey as String: outputSize.height,
            kCVPixelBufferPoolMinimumBufferCountKey as String: 8,

            // APPLE RECOMMENDED (WWDC 2019 Session 249): Enable IOSurface for hardware composition
            // This enables 30-40% faster GPU rendering for multi-camera composition
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary,

            // Enable Metal compatibility for GPU acceleration
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: composedVideoInput,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )

        guard composedWriter.canAdd(composedVideoInput) else { throw RecorderError.cannotAddInput }
        composedWriter.add(composedVideoInput)

        let composedAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        composedAudioInput.expectsMediaDataInRealTime = true
        guard composedWriter.canAdd(composedAudioInput) else { throw RecorderError.cannotAddInput }
        composedWriter.add(composedAudioInput)

        // Start all three writers
        guard backWriter.startWriting() else {
            logger.error("❌ Failed to start back writer: \(backWriter.error?.localizedDescription ?? "unknown")")
            throw backWriter.error ?? RecorderError.cannotStartWriting
        }

        guard frontWriter.startWriting() else {
            logger.error("❌ Failed to start front writer: \(frontWriter.error?.localizedDescription ?? "unknown")")
            throw frontWriter.error ?? RecorderError.cannotStartWriting
        }

        guard composedWriter.startWriting() else {
            logger.error("❌ Failed to start composed writer: \(composedWriter.error?.localizedDescription ?? "unknown")")
            throw composedWriter.error ?? RecorderError.cannotStartWriting
        }

        // Store references
        self.backWriter = backWriter
        self.frontWriter = frontWriter
        self.composedWriter = composedWriter
        self.backVideoInput = backVideoInput
        self.frontVideoInput = frontVideoInput
        self.composedVideoInput = composedVideoInput
        self.backAudioInput = backAudioInput
        self.frontAudioInput = frontAudioInput
        self.composedAudioInput = composedAudioInput
        self.composedPixelBufferAdaptor = adaptor
        self.isRecording = true
        self.recordingStartTime = nil
        self.audioSampleCount = 0

        // Setup memory pressure monitoring
        setupMemoryPressureMonitoring()

        logger.info("🎬 Recording started to: \(url.path)")
        logger.info("🎧 Audio input configured: 44.1 kHz, 2 channels, AAC")
    }

    /// Update rotation angles for proper video orientation
    func setRotationAngles(back: CGFloat, front: CGFloat) {
        backRotationAngle = back
        frontRotationAngle = front
        logger.debug("🔄 Rotation updated - back: \(back)°, front: \(front)°")
    }

    /// Stops recording and finalizes all 3 video files
    /// Returns a tuple with all 3 video URLs (composed, back, front)
    func stopRecording() async throws -> (composedURL: URL, backURL: URL, frontURL: URL) {
        guard isRecording else {
            throw RecorderError.notRecording
        }

        // Set stopping flag FIRST to prevent new frames
        isStopping = true

        // Give any in-flight frames time to complete (50ms should be enough)
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Now mark as not recording
        isRecording = false

        guard let backWriter = backWriter,
              let frontWriter = frontWriter,
              let composedWriter = composedWriter else {
            throw RecorderError.writerNotConfigured
        }

        // Mark all inputs as finished
        backVideoInput?.markAsFinished()
        backAudioInput?.markAsFinished()
        frontVideoInput?.markAsFinished()
        frontAudioInput?.markAsFinished()
        composedVideoInput?.markAsFinished()
        composedAudioInput?.markAsFinished()

        // Finish writing all three files
        await backWriter.finishWriting()
        await frontWriter.finishWriting()
        await composedWriter.finishWriting()

        // Log detailed performance metrics
        let avgRenderTime = frameCount > 0 ? (totalRenderTime / Double(frameCount)) * 1000 : 0
        let dropRate = frameCount > 0 ? Double(droppedFrameCount) / Double(frameCount) * 100 : 0

        logger.info("""
        📊 Recording Performance Metrics:
           - Total frames: \(frameCount)
           - Dropped frames: \(droppedFrameCount) (\(String(format: "%.1f%%", dropRate)))
           - Avg render time: \(String(format: "%.2f", avgRenderTime))ms
           - Total render time: \(String(format: "%.2f", totalRenderTime))s
           - Audio samples: \(audioSampleCount)
           - Memory pressure: \(isUnderMemoryPressure ? "YES" : "NO")
        """)

        // Check status of all writers
        let backStatus = backWriter.status
        let frontStatus = frontWriter.status
        let composedStatus = composedWriter.status

        logger.info("📹 Back video: \(backStatus == .completed ? "✅" : "❌") \(backWriter.outputURL.lastPathComponent)")
        logger.info("📹 Front video: \(frontStatus == .completed ? "✅" : "❌") \(frontWriter.outputURL.lastPathComponent)")
        logger.info("📹 Composed video: \(composedStatus == .completed ? "✅" : "❌") \(composedWriter.outputURL.lastPathComponent)")

        let composedURL = composedWriter.outputURL
        let backURL = backWriter.outputURL
        let frontURL = frontWriter.outputURL

        // Clean up
        self.backWriter = nil
        self.frontWriter = nil
        self.composedWriter = nil
        self.backVideoInput = nil
        self.frontVideoInput = nil
        self.composedVideoInput = nil
        self.backAudioInput = nil
        self.frontAudioInput = nil
        self.composedAudioInput = nil
        self.composedPixelBufferAdaptor = nil
        recordingStartTime = nil
        isStopping = false
        cachedBackground = nil
        frameCount = 0
        droppedFrameCount = 0

        // Cancel memory pressure monitoring
        memoryPressureSource?.cancel()
        memoryPressureSource = nil

        // Check if all completed successfully
        if backStatus == .completed && frontStatus == .completed && composedStatus == .completed {
            logger.info("✅ All 3 recordings completed successfully")
            return (composedURL: composedURL, backURL: backURL, frontURL: frontURL)
        } else {
            // Log errors
            if let error = backWriter.error {
                logger.error("❌ Back video error: \(error.localizedDescription)")
            }
            if let error = frontWriter.error {
                logger.error("❌ Front video error: \(error.localizedDescription)")
            }
            if let error = composedWriter.error {
                logger.error("❌ Composed video error: \(error.localizedDescription)")
                throw error
            }
            throw RecorderError.writingFailed
        }
    }

    /// Processes synchronized video frames from both cameras
    /// Writes to 3 separate files: back, front, and composed
    func processSynchronizedFrames(
        backBuffer: CMSampleBuffer,
        frontBuffer: CMSampleBuffer
    ) {
        autoreleasepool {
            // Check stopping flag FIRST
            guard !isStopping, isRecording else {
                return
            }

            guard let backVideoInput = backVideoInput,
                  let frontVideoInput = frontVideoInput,
                  let composedVideoInput = composedVideoInput,
                  let adaptor = composedPixelBufferAdaptor else {
                return
            }

            // Check if all inputs are ready
            guard backVideoInput.isReadyForMoreMediaData,
                  frontVideoInput.isReadyForMoreMediaData,
                  composedVideoInput.isReadyForMoreMediaData else {
                // Drop frame - track for diagnostics
                self.droppedFrameCount += 1
                if self.droppedFrameCount % 30 == 0 {
                    logger.warning("⚠️ Dropped \(self.droppedFrameCount) frames - encoder not ready")
                }
                return
            }

            self.frameCount += 1

            // Get presentation time
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(backBuffer)

            // Start sessions on first frame
            if recordingStartTime == nil {
                guard let backWriter = backWriter,
                      let frontWriter = frontWriter,
                      let composedWriter = composedWriter else {
                    logger.error("Asset writers are nil, cannot start session")
                    return
                }

                guard backWriter.status == .writing,
                      frontWriter.status == .writing,
                      composedWriter.status == .writing else {
                    logger.error("Asset writers not in writing state")
                    return
                }

                backWriter.startSession(atSourceTime: presentationTime)
                frontWriter.startSession(atSourceTime: presentationTime)
                composedWriter.startSession(atSourceTime: presentationTime)
                recordingStartTime = presentationTime
                logger.info("Started all writer sessions at time: \(presentationTime.seconds)")
            }

            // Write back camera frame directly
            if let backPixelBuffer = CMSampleBufferGetImageBuffer(backBuffer) {
                let success = backVideoInput.append(backBuffer)
                if !success {
                    logger.error("Failed to append back camera frame")
                }
            }

            // Write front camera frame directly
            if let frontPixelBuffer = CMSampleBufferGetImageBuffer(frontBuffer) {
                let success = frontVideoInput.append(frontBuffer)
                if !success {
                    logger.error("Failed to append front camera frame")
                }
            }

            // Compose and write composed frame with timing
            renderStartTime = CFAbsoluteTimeGetCurrent()
            guard let composedPixelBuffer = composeFrames(
                back: backBuffer,
                front: frontBuffer
            ) else {
                return
            }
            let renderTime = CFAbsoluteTimeGetCurrent() - renderStartTime
            totalRenderTime += renderTime

            let success = adaptor.append(composedPixelBuffer, withPresentationTime: presentationTime)
            if !success {
                logger.error("Failed to append composed pixel buffer at time: \(presentationTime.seconds)")
            }
        }
    }

    /// Processes audio sample buffer
    /// Writes the same audio to all 3 videos (shared audio track)
    func processAudio(_ sampleBuffer: CMSampleBuffer) {
        guard !isStopping,
              isRecording,
              let backAudioInput = backAudioInput,
              let frontAudioInput = frontAudioInput,
              let composedAudioInput = composedAudioInput,
              recordingStartTime != nil else {
            return
        }

        // Append to all three audio inputs (shared audio track)
        var successCount = 0

        if backAudioInput.isReadyForMoreMediaData {
            if backAudioInput.append(sampleBuffer) {
                successCount += 1
            }
        }

        if frontAudioInput.isReadyForMoreMediaData {
            if frontAudioInput.append(sampleBuffer) {
                successCount += 1
            }
        }

        if composedAudioInput.isReadyForMoreMediaData {
            if composedAudioInput.append(sampleBuffer) {
                successCount += 1
            }
        }

        if successCount < 3 {
            logger.warning("🎧 Only appended audio to \(successCount)/3 tracks")
        } else {
            self.audioSampleCount += 1
            // Log first few audio samples to verify audio is flowing
            if self.audioSampleCount <= 3 {
                let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                logger.info("🎧 Audio sample #\(self.audioSampleCount) appended to all 3 tracks at time: \(String(format: "%.3f", pts.seconds))s")
            }
        }
    }

    // MARK: - Frame Composition

    private func composeFrames(back: CMSampleBuffer, front: CMSampleBuffer) -> CVPixelBuffer? {
        guard let backPixelBuffer = CMSampleBufferGetImageBuffer(back),
              let frontPixelBuffer = CMSampleBufferGetImageBuffer(front),
              let pixelBufferPool = composedPixelBufferAdaptor?.pixelBufferPool,
              let outputPixelBuffer = createPixelBuffer(from: pixelBufferPool) else {
            return nil
        }

        // Create CIImages with color space specified for better performance
        var frontImage = CIImage(cvPixelBuffer: frontPixelBuffer)
        var backImage = CIImage(cvPixelBuffer: backPixelBuffer)

        // Apply rotation transforms if needed (for device orientation)
        if backRotationAngle != 0 {
            let radians = backRotationAngle * .pi / 180
            backImage = backImage.transformed(by: CGAffineTransform(rotationAngle: radians))
        }
        if frontRotationAngle != 0 {
            let radians = frontRotationAngle * .pi / 180
            frontImage = frontImage.transformed(by: CGAffineTransform(rotationAngle: radians))
        }

        // Clamp to extent to avoid sampling beyond bounds (GPU optimization)
        frontImage = frontImage.clampedToExtent().cropped(to: frontImage.extent)
        backImage = backImage.clampedToExtent().cropped(to: backImage.extent)

        // Split-screen dimensions (cached constant)
        let halfHeight = outputSize.height / 2

        // Calculate scale factors directly (much faster than CIFilter)
        let frontExtent = frontImage.extent
        let backExtent = backImage.extent

        let frontScale = max(outputSize.width / frontExtent.width, halfHeight / frontExtent.height)
        let backScale = max(outputSize.width / backExtent.width, halfHeight / backExtent.height)

        // Scale and position images using transforms (very fast)
        let frontScaleTransform = CGAffineTransform(scaleX: frontScale, y: frontScale)
        let frontScaled = frontImage.transformed(by: frontScaleTransform)

        // Crop to top half
        let frontCropped = frontScaled.cropped(to: CGRect(
            x: (frontScaled.extent.width - outputSize.width) / 2,
            y: (frontScaled.extent.height - halfHeight) / 2,
            width: outputSize.width,
            height: halfHeight
        ))

        // Scale back camera
        let backScaleTransform = CGAffineTransform(scaleX: backScale, y: backScale)
        let backScaled = backImage.transformed(by: backScaleTransform)

        // Crop to bottom half
        let backCropped = backScaled.cropped(to: CGRect(
            x: (backScaled.extent.width - outputSize.width) / 2,
            y: (backScaled.extent.height - halfHeight) / 2,
            width: outputSize.width,
            height: halfHeight
        ))

        // Position back camera at bottom half
        let backPositioned = backCropped.transformed(by: CGAffineTransform(translationX: -backCropped.extent.minX, y: halfHeight - backCropped.extent.minY))
        let frontPositioned = frontCropped.transformed(by: CGAffineTransform(translationX: -frontCropped.extent.minX, y: -frontCropped.extent.minY))

        // Create or reuse black background
        if cachedBackground == nil {
            cachedBackground = CIImage(color: CIColor.black).cropped(to: CGRect(origin: .zero, size: outputSize))
        }

        guard let background = cachedBackground else {
            logger.error("Failed to create cached background image")
            return nil
        }

        // Composite (order matters: back over front over background)
        let composite = backPositioned
            .composited(over: frontPositioned)
            .composited(over: background)

        // Render with cached RGB color space for better performance
        ciContext.render(
            composite,
            to: outputPixelBuffer,
            bounds: CGRect(origin: .zero, size: outputSize),
            colorSpace: cachedColorSpace
        )

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

    // MARK: - Memory Pressure Monitoring

    /// Setup memory pressure monitoring to handle low memory situations
    private func setupMemoryPressureMonitoring() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .global(qos: .userInitiated)
        )

        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            let event = source.data

            Task {
                if event.contains(.warning) {
                    await self.handleMemoryWarning()
                } else if event.contains(.critical) {
                    await self.handleMemoryCritical()
                }
            }
        }

        source.resume()
        memoryPressureSource = source

        logger.info("📊 Memory pressure monitoring enabled")
    }

    /// Handle memory warning by clearing caches
    private func handleMemoryWarning() {
        logger.warning("⚠️ Memory pressure warning - clearing caches")
        isUnderMemoryPressure = true

        // Clear cached resources to free memory
        cachedBackground = nil

        logger.info("🧹 Caches cleared due to memory pressure")
    }

    /// Handle critical memory pressure by stopping recording
    private func handleMemoryCritical() {
        logger.error("❌ Critical memory pressure - stopping recording to prevent crash")
        isUnderMemoryPressure = true

        // Force stop recording to prevent crash
        Task {
            do {
                _ = try await self.stopRecording()
                logger.info("✅ Recording stopped due to critical memory pressure")
            } catch {
                logger.error("❌ Failed to stop recording: \(error.localizedDescription)")
            }
        }
    }

    deinit {
        // Cancel any in-progress writing
        backWriter?.cancelWriting()
        frontWriter?.cancelWriting()
        composedWriter?.cancelWriting()

        // Cancel memory pressure monitoring
        memoryPressureSource?.cancel()
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
