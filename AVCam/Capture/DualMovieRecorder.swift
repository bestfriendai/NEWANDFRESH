import AVFoundation
import CoreImage
import Metal
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
    private var isStopping = false // Prevent new frames during stop

    // Metal-accelerated Core Image context for GPU rendering
    private let ciContext: CIContext = {
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: metalDevice, options: [.priorityRequestLow: true])
        } else {
            return CIContext(options: [.priorityRequestLow: true])
        }
    }()

    // Output configuration for split-screen (16:9 aspect ratio)
    private let outputSize = CGSize(width: 1920, height: 1080)

    // Cache for reusable Core Image components
    private var cachedBackground: CIImage?

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
                AVVideoExpectedSourceFrameRateKey: 30
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

        // Set stopping flag FIRST to prevent new frames
        isStopping = true

        // Give any in-flight frames time to complete (50ms should be enough)
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Now mark as not recording
        isRecording = false

        guard let writer = assetWriter else {
            throw RecorderError.writerNotConfigured
        }

        // Mark inputs as finished
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()

        // Finish writing with timeout protection
        await writer.finishWriting()

        let outputURL = writer.outputURL

        // Clean up
        assetWriter = nil
        videoInput = nil
        audioInput = nil
        pixelBufferAdaptor = nil
        recordingStartTime = nil
        isStopping = false
        cachedBackground = nil

        if writer.status == .completed {
            logger.info("Recording completed: \(outputURL.path)")
            return outputURL
        } else if let error = writer.error {
            logger.error("Recording failed with error: \(error.localizedDescription)")
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
        // Check stopping flag FIRST
        guard !isStopping, isRecording else {
            return
        }

        guard let videoInput = videoInput,
              let adaptor = pixelBufferAdaptor else {
            return
        }

        guard videoInput.isReadyForMoreMediaData else {
            // Drop frame instead of logging warning to reduce overhead
            return
        }

        // Get presentation time
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(backBuffer)

        // Start session on first frame
        if recordingStartTime == nil {
            assetWriter?.startSession(atSourceTime: presentationTime)
            recordingStartTime = presentationTime
            logger.info("Started writer session at time: \(presentationTime.seconds)")
        }

        // Compose frames
        guard let composedPixelBuffer = composeFrames(
            back: backBuffer,
            front: frontBuffer
        ) else {
            return
        }

        // Append to video
        let success = adaptor.append(composedPixelBuffer, withPresentationTime: presentationTime)
        if !success {
            logger.error("Failed to append pixel buffer at time: \(presentationTime.seconds)")
        }
    }

    /// Processes audio sample buffer
    func processAudio(_ sampleBuffer: CMSampleBuffer) {
        guard !isStopping,
              isRecording,
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
              let frontPixelBuffer = CMSampleBufferGetImageBuffer(front),
              let pixelBufferPool = pixelBufferAdaptor?.pixelBufferPool,
              let outputPixelBuffer = createPixelBuffer(from: pixelBufferPool) else {
            return nil
        }

        // Create CIImages
        let frontImage = CIImage(cvPixelBuffer: frontPixelBuffer)
        let backImage = CIImage(cvPixelBuffer: backPixelBuffer)

        // Split-screen dimensions
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

        // Composite (order matters: back over front over background)
        let composite = backPositioned
            .composited(over: frontPositioned)
            .composited(over: cachedBackground!)

        // Render with RGB color space
        ciContext.render(
            composite,
            to: outputPixelBuffer,
            bounds: CGRect(origin: .zero, size: outputSize),
            colorSpace: CGColorSpaceCreateDeviceRGB()
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

    deinit {
        // Cancel any in-progress writing
        assetWriter?.cancelWriting()
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
