Transforming AVCam into a Dual-Camera Powerhouse with AVFoundation and SwiftUIIntroductionObjectiveThis report provides a comprehensive, expert-level guide to transforming a standard single-camera iOS application, based on Apple's AVCam sample project , into a sophisticated dual-camera application. The final product will replicate the user interface and simultaneous capture functionality depicted in the provided screenshot. The core objectives of this transformation are to implement simultaneous video preview and recording from both the front and rear cameras, and to craft a modern user interface that incorporates Apple's "liquid glass" aesthetic.Target AudienceThis document is meticulously structured for junior-to-intermediate iOS developers. It assumes a foundational understanding of Swift, SwiftUI, and the Xcode environment. The explanations are designed to be pedagogical, breaking down complex, advanced topics into digestible, step-by-step instructions. The focus is not only on how to implement these features but, more importantly, on why specific architectural decisions are made, providing a deeper understanding of the underlying frameworks.Core Technologies OverviewThe transformation leverages a powerful suite of native Apple frameworks. A successful implementation requires a shift from basic to advanced concepts within AVFoundation and the adoption of modern styling APIs in SwiftUI. The key technologies at the heart of this project include:AVCaptureMultiCamSession: The cornerstone of the dual-camera functionality. This specialized subclass of AVCaptureSession is expressly designed to manage simultaneous data flow from multiple inputs of the same media type, such as two cameras.2 Its use necessitates a more explicit and manual configuration of the capture pipeline compared to its single-camera counterpart.AVAssetWriter: For recording the dual-camera stream into a single movie file, direct access to the raw video frames is required for composition. AVAssetWriter provides the necessary low-level control to take these processed frames and encode them, along with an audio track, into a standard video format like MP4 or MOV.3SwiftUI UIViewRepresentable: To display the live video feeds from AVFoundation within a SwiftUI application, a bridge to UIKit is necessary. AVCaptureVideoPreviewLayer, a CALayer subclass, is the designated tool for rendering camera previews.4 The UIViewRepresentable protocol allows for the wrapping of a UIView that hosts these layers, making them accessible to the declarative SwiftUI view hierarchy.SwiftUI .glassEffect(): To achieve the "liquid glass" aesthetic, this report moves beyond simple material blurs (.background(.thinMaterial)). It employs the modern .glassEffect() modifier and its associated GlassEffectContainer. This new API provides a dynamic, multi-layered effect that simulates the optical properties of glass, including fluidity, light reflection, and interactive feedback, which is central to the target UI's design.6Section 1: Architectural Evolution: From AVCaptureSession to AVCaptureMultiCamSessionThe foundational step in this transformation is a significant architectural refactoring of the capture pipeline. The existing AVCam project uses AVCaptureSession, which is robust for single-camera operations but fundamentally incapable of handling simultaneous streams from multiple cameras.5 This section details the migration to AVCaptureMultiCamSession, a change that introduces greater power at the cost of requiring more explicit configuration. This process involves modifying AVCam/CaptureService.swift and AVCam/Capture/DeviceLookup.swift.1.1 The Case for AVCaptureMultiCamSessionAn AVCaptureSession object coordinates the flow of data from input devices (like cameras and microphones) to outputs (like movie files or preview layers). However, a standard AVCaptureSession on iOS is constrained to a single active video device input at any given time.5 Attempting to add a second AVCaptureDeviceInput for another camera would result in a configuration error.To overcome this limitation, Apple introduced AVCaptureMultiCamSession, a direct subclass of AVCaptureSession specifically engineered for scenarios requiring simultaneous capture from multiple inputs of the same media type.2 This is precisely the requirement for a dual-camera application. The first modification is therefore to replace the captureSession property in CaptureService.swift from an instance of AVCaptureSession to AVCaptureMultiCamSession.1.2 Verifying Device SupportNot all iOS devices are capable of running a multi-camera session due to hardware constraints such as processing power, memory bandwidth, and thermal limits. Attempting to initialize an AVCaptureMultiCamSession on an unsupported device will lead to failure. Therefore, it is imperative to perform a runtime check before proceeding with any configuration.The AVCaptureMultiCamSession class provides a static property, isMultiCamSupported, which returns a Boolean value indicating the host device's capability.2 This check should be the first step in the capture service's setup or start sequence. If this property returns false, the application should gracefully disable dual-camera features and inform the user. This logic will be added to the start() method within CaptureService.swift.1.3 Discovering and Selecting Camera PairsThe original DeviceLookup.swift identifies individual cameras based on their position (front or back). For a multi-camera session, it's not enough to know that a front and a back camera exist; it's necessary to confirm that they can operate concurrently. AVFoundation provides a mechanism to discover pre-validated combinations of devices.The AVCaptureDevice.DiscoverySession class offers the supportedMultiCamDeviceSets property. This property returns an array of Set<AVCaptureDevice>, where each set represents a group of devices that the system guarantees can be used simultaneously in a multi-camera session.11 The implementation in DeviceLookup.swift will be modified to query these device sets, find a set that contains both a front-facing and a back-facing camera, and return that specific pair of AVCaptureDevice objects for the CaptureService to use. This ensures the application only attempts to configure a hardware combination that is certified to work, preventing runtime errors and performance issues.1.4 The Critical Shift: Manual Connection ManagementThe most significant conceptual and practical difference between AVCaptureSession and AVCaptureMultiCamSession lies in how connections are formed. A standard AVCaptureSession uses "implicit connection forming." When an input and an output are added, the session automatically finds compatible ports and creates an AVCaptureConnection between them.12 This is convenient for simple, unambiguous setups.However, in a multi-camera scenario with multiple inputs (e.g., front camera, back camera) and multiple outputs (e.g., front preview, back preview, front data output, back data output) of the same media type, the session cannot possibly infer the developer's intent. To resolve this ambiguity, AVCaptureMultiCamSession disables implicit connections and requires the developer to perform manual connection management.13The refactoring of CaptureService.swift must reflect this paradigm shift:Adding Inputs and Outputs without Connections: Instead of using the standard addInput(_:) and addOutput(_:) methods, the code must be changed to use addInputWithNoConnections(_:) and addOutputWithNoConnections(_:).13 This adds the components to the session's graph without creating any data pathways.Creating Explicit Connections: After adding the components, AVCaptureConnection objects must be created manually. An AVCaptureConnection is initialized with an array of input ports and an output. For example, to connect the back camera to its corresponding video data output, one must retrieve the camera's AVCaptureDeviceInput, find its video AVCaptureInputPort, and use that port to initialize a connection to the AVCaptureVideoDataOutput.Adding Connections to the Session: Once an AVCaptureConnection object is created, it is added to the session using the addConnection(_:) method.This manual "wiring" of the data flow graph is more verbose but provides the explicit control necessary for a complex pipeline. It ensures that the feed from the front camera is directed precisely to the front-camera preview layer and the front-camera data output, and likewise for the back camera, with no ambiguity. This explicit definition of the data flow is the key to building a stable and predictable multi-camera system.Section 2: Crafting the Dual-View User Interface in SwiftUIWith the backend architecture updated to support two camera streams, the next task is to render these streams on screen. This requires creating a user interface that can display two live video feeds simultaneously in the specified primary/secondary layout. As SwiftUI does not have a native component for camera previews, this section details how to build a custom UIViewRepresentable to host two AVCaptureVideoPreviewLayer instances and arrange them using SwiftUI's layout system.2.1 The Need for Two AVCaptureVideoPreviewLayersAn AVCaptureVideoPreviewLayer is a subclass of CALayer that displays video from a running AVCaptureSession.4 A single preview layer can only be connected to one video source at a time. Therefore, to display feeds from both the front and back cameras, two distinct instances of AVCaptureVideoPreviewLayer are required.The challenge is integrating these CALayer-based components into a declarative SwiftUI interface. The standard and most robust solution, as demonstrated in the original AVCam project, is to wrap a UIView that hosts the layer within a UIViewRepresentable struct.1 This approach will be extended to manage two layers instead of one.2.2 Building DualCameraPreviewView.swiftA new SwiftUI view, DualCameraPreviewView.swift, will be created to replace the original CameraPreview.swift. This new component will be a UIViewRepresentable responsible for creating and managing the UIKit views that host the two preview layers.Inside the makeUIViewController(context:) method of the representable, a main container UIViewController will be instantiated. Two UIView subclasses, PrimaryPreviewView and SecondaryPreviewView, will be created. Each of these views will override its layerClass property to return AVCaptureVideoPreviewLayer.self, effectively making a preview layer its backing layer.5 These two preview views will be added as subviews to the view controller's main view.This structure encapsulates the UIKit components, but a mechanism is needed for the CaptureService to access and configure the underlying AVCaptureVideoPreviewLayers. This is achieved through a coordinator class or by passing the layers back to the model upon creation. The makeUIViewController method will return the view controller, which holds references to the two preview layers, making them available to the broader application architecture for connection.2.3 Connecting Layers to the Multi-Cam SessionOnce the DualCameraPreviewView instantiates the two preview layers, they must be connected to the AVCaptureMultiCamSession. This process mirrors the manual connection logic established in the previous section and occurs within CaptureService.swift.Association without Connection: Similar to inputs and outputs, the preview layers must be associated with the session without forming automatic connections. The setSessionWithNoConnection(_:) method of AVCaptureVideoPreviewLayer is used for this purpose.4 This informs the layer which session it belongs to but does not yet establish a data flow.Explicit Connection: Two AVCaptureConnection objects are created. The first connects the video port of the back camera's AVCaptureDeviceInput to the primary AVCaptureVideoPreviewLayer. The second connects the video port of the front camera's input to the secondary preview layer.Adding to Session: These connections are then added to the AVCaptureMultiCamSession using addConnection(_:).This explicit wiring ensures that the video stream from the back camera is rendered in the primary preview view, and the stream from the front camera is rendered in the secondary, picture-in-picture view.2.4 Arranging the Previews with SwiftUIWith the backend connections established, the final step is to arrange the two preview views in the desired layout using SwiftUI. In CameraView.swift, the original CameraPreview is replaced with the new DualCameraPreviewView.The layout from the screenshot—a full-screen primary view with a smaller, rounded secondary view in the bottom corner—is achieved using a ZStack. The DualCameraPreviewView is placed at the bottom of the stack. A separate view representing the secondary camera feed is then overlaid on top.However, since both preview layers are managed within the single DualCameraPreviewView, the arrangement is handled within its updateUIViewController method by setting the frames of the two UIView subviews. SwiftUI's GeometryReader can be used to determine the available space and calculate the appropriate frames for the primary (full-size) and secondary (inset, smaller size) views. SwiftUI modifiers like .cornerRadius() and .overlay() can then be applied to a container around the DualCameraPreviewView to add borders or other styling to the secondary view's area, completing the visual replication. An alternative and more SwiftUI-native approach involves using two UIViewRepresentables, one for each preview layer, and composing them directly in a SwiftUI ZStack. This simplifies the layout code by leveraging SwiftUI's powerful modifiers for positioning and styling.Section 3: Replicating the "Liquid Glass" AestheticThe user interface in the target screenshot features a distinct, modern aesthetic known as "liquid glass." This is not a simple translucent material but a dynamic effect that simulates the properties of glass, including fluidity, subtle light reflections, and interactive feedback. Achieving this look requires moving beyond traditional blur effects and embracing the new styling APIs introduced in recent versions of SwiftUI. This section details the process of applying this effect to the app's toolbar and buttons.3.1 Understanding Liquid Glass vs. Material BlursFor years, SwiftUI developers have used material backgrounds like .background(.thinMaterial) or .background(.ultraThinMaterial) to create frosted-glass-like translucency.17 These materials apply a Gaussian blur to the content behind them, providing a sense of depth and context while maintaining legibility.However, the "liquid glass" design language is a more advanced visual system.6 It is implemented in SwiftUI via the .glassEffect() modifier. This modifier does more than just blur; it creates a multi-layered effect that reacts to light, color, and user interaction.7 When a user touches a button with a glass effect, it can illuminate from within, with the glow radiating across its surface and even blending into adjacent glass elements.19 This interactivity and fluidity are what distinguish it from a static material blur.3.2 Applying.glassEffect() to Toolbar ComponentsThe original AVCam project styles its toolbar buttons with a simple, semi-transparent black background: .background(.black.opacity(0.4)). To match the target UI, this styling will be replaced with the .glassEffect() modifier.The modification will be applied to the individual button views within the AVCam/Views/Toolbars/ directory, such as SwitchCameraButton.swift and ThumbnailButton.swift. The process involves:Removing the existing .background() modifier.Applying the .glassEffect() modifier. By default, this applies the effect within a Capsule shape, which is suitable for many standard buttons.8Adjusting padding and frame modifiers as needed. The glass effect has its own visual presence and may require slight layout tweaks to ensure the final button size and spacing are correct.For the central CaptureButton.swift, which consists of an outer ring and an inner circle, the .glassEffect() will be applied to the Circle view that forms the outer ring, replacing its simple white stroke. This will give the ring the desired glassy, three-dimensional appearance.3.3 Using GlassEffectContainer for Cohesive AnimationsA key characteristic of the liquid glass system is the seamless morphing and blending between adjacent elements.8 If multiple views with .glassEffect() are simply placed next to each other, they will render as distinct glass objects. To make them behave as a single, cohesive unit, they must be wrapped in a GlassEffectContainer.In MainToolbar.swift, the HStack that arranges the thumbnail, capture, and camera-switch buttons will be enclosed within a GlassEffectContainer.7 This container signals to the SwiftUI rendering engine that the glass effects of its children are related. As a result, when views are added, removed, or animated, their glass backgrounds will fluidly merge and separate rather than simply fading in and out independently. This creates the sophisticated, high-fidelity animation that is a hallmark of the liquid glass design language and is essential for accurately replicating the target UI's feel. The container's spacing parameter can be tuned to control how closely the elements must be before their glass effects begin to merge.8Section 4: Implementing Synchronized Dual-Stream RecordingThis section addresses the most technically demanding requirement: recording video from both cameras simultaneously into a single movie file with a picture-in-picture effect. This cannot be achieved with high-level APIs like AVCaptureMovieFileOutput, which are designed for simple, single-source recording. Instead, a custom recording pipeline must be constructed to manually capture, synchronize, composite, and write the video frames. This involves replacing MovieCapture.swift with a new, more advanced DualMovieRecorder.swift.4.1 The Limitation of AVCaptureMovieFileOutputThe original AVCam project uses AVCaptureMovieFileOutput in its MovieCapture.swift class. This class is a convenient "black box" that handles all the complexities of video and audio encoding and file writing. However, its simplicity is also its limitation: it is designed to be connected to a single video source and a single audio source. It offers no hooks for real-time frame manipulation, making it impossible to perform the composition required for a PiP effect. Therefore, this entire class must be replaced with a lower-level approach.4.2 Capturing Raw Frames with AVCaptureVideoDataOutputTo gain access to the raw pixel data from each camera, the pipeline must use AVCaptureVideoDataOutput. In CaptureService.swift, two instances of AVCaptureVideoDataOutput will be created: one for the front camera and one for the back. Each output will be configured with a delegate that conforms to the AVCaptureVideoDataOutputSampleBufferDelegate protocol. This delegate will have a captureOutput(_:didOutput:from:) method that the system calls for every single frame captured by the camera, providing the frame data as a CMSampleBuffer object.As with the preview layers, these two data outputs will be manually connected to their respective camera inputs within the AVCaptureMultiCamSession. This establishes two parallel data streams, delivering raw, uncompressed video frames from both cameras to the application's code in real-time.4.3 Synchronizing Video StreamsA critical challenge in multi-camera systems is synchronization. The front and back cameras are independent hardware components, and their frames will not arrive at the application at the exact same microsecond. Attempting to composite the most recently received frame from each stream can lead to temporal artifacts, where one stream appears slightly ahead of or behind the other, resulting in jittery or unnatural motion.To solve this, AVFoundation provides the AVCaptureDataOutputSynchronizer class.13 This object is initialized with an array of the data outputs that need to be synchronized (in this case, the two AVCaptureVideoDataOutput instances). Instead of using the individual delegates of each output, a single delegate is set on the synchronizer. This delegate's dataOutputSynchronizer(_:didOutput:) method is called with an AVCaptureSynchronizedDataCollection. This collection provides access to the synchronized data from each output, ensuring that the pair of CMSampleBuffers received in a single callback correspond to the same moment in time.4.4 Real-Time Frame CompositionInside the dataOutputSynchronizer(_:didOutput:) delegate method, the application receives a synchronized pair of CMSampleBuffer objects. The next step is to composite them into a single frame. The Core Image framework is ideally suited for this high-performance, GPU-accelerated task.Buffer to Image Conversion: The CVPixelBuffer from each CMSampleBuffer is converted into a CIImage object.Transformation and Compositing: The CIImage from the secondary camera (e.g., the front camera) is scaled down and translated to the desired PiP position. This is done using Core Image transformations.Overlaying: The transformed secondary image is then overlaid onto the primary image using a compositing filter, such as CISourceOverCompositing. This filter places one image on top of another, respecting transparency.Final Image: The output of the compositing filter is a single, final CIImage that represents the complete, composited frame with the PiP effect.4.5 Writing the Composite Stream with AVAssetWriterThe final step is to encode this stream of composite frames into a movie file. AVAssetWriter is the appropriate tool for this task.3 A new class, DualMovieRecorder.swift, will manage this process.Setup: An AVAssetWriter is initialized with an output file URL and file type.Input Configuration: Two AVAssetWriterInput objects are created and added to the writer:One video input, configured with the desired video settings (codec, dimensions, etc.).One audio input, configured with appropriate audio settings.Frame Processing Loop: In the data synchronizer's delegate method, after the CIImage is composited, it is rendered back into a new CVPixelBuffer. This pixel buffer, which now contains the final PiP image, is appended to the video AVAssetWriterInput.Audio Passthrough: The audio CMSampleBuffer received from the microphone's AVCaptureAudioDataOutput is passed directly to the audio AVAssetWriterInput without modification.Finalization: When recording stops, the finishWriting(completionHandler:) method is called on the AVAssetWriter to complete the file and write the necessary metadata.This complete pipeline—capturing two raw streams, synchronizing them, compositing them on the GPU with Core Image, and writing the result with AVAssetWriter—constitutes a professional-grade, real-time video processing system capable of producing the desired dual-camera recording.Section 5: The Complete Transformation: Code and DocumentationThis section presents the final deliverables: the complete, commented source code for all modified and newly created files, and a detailed before-and-after comparison document to serve as a high-level guide to the project's evolution.5.1 Full Modified Source CodeThe following are the complete source code files that have been created or modified to implement the dual-camera functionality and updated user interface. Each file includes extensive inline comments to clarify the purpose of key properties, methods, and logical blocks.AVCam/Capture/DeviceLookup.swift (Modified)Swift/*
See the LICENSE.txt file for this sample’s licensing information.
Abstract:
An object that retrieves camera and microphone devices, now updated for multi-camera support.
*/

import AVFoundation
import Combine

/// An object that retrieves camera and microphone devices, with support for multi-camera device sets.
final class DeviceLookup {
    
    // MARK: - Multi-Camera Properties
    
    /// Returns the primary dual-camera device set (back wide and front camera).
    var defaultDualCamera: (back: AVCaptureDevice, front: AVCaptureDevice)? {
        // Find a device set that includes a back wide-angle camera and a front camera.
        let dualCameraDeviceSet = AVCaptureDevice.DiscoverySession.supportedMultiCamDeviceSets.first { deviceSet in
            deviceSet.contains { $0.deviceType ==.builtInWideAngleCamera && $0.position ==.back } &&
            deviceSet.contains { $0.position ==.front }
        }
        
        guard let deviceSet = dualCameraDeviceSet,
              let backCamera = deviceSet.first(where: { $0.deviceType ==.builtInWideAngleCamera && $0.position ==.back }),
              let frontCamera = deviceSet.first(where: { $0.position ==.front }) else {
            logger.error("Could not find a supported multi-camera device set with back wide-angle and front cameras.")
            return nil
        }
        
        return (back: backCamera, front: frontCamera)
    }
    
    /// Returns the default microphone for the device.
    var defaultMic: AVCaptureDevice {
        get throws {
            guard let audioDevice = AVCaptureDevice.default(for:.audio) else {
                throw CameraError.audioDeviceUnavailable
            }
            return audioDevice
        }
    }
    
    // MARK: - Single Camera Properties (Legacy/Fallback)
    
    private let frontCameraDiscoverySession: AVCaptureDevice.DiscoverySession
    private let backCameraDiscoverySession: AVCaptureDevice.DiscoverySession
    
    init() {
        // These are kept for single-camera fallback or other features but are not primary for dual-cam setup.
        backCameraDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes:,
                                                                      mediaType:.video,
                                                                      position:.back)
        frontCameraDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes:,
                                                                       mediaType:.video,
                                                                       position:.front)
        
        // Set a reasonable default if no user preference is set.
        if AVCaptureDevice.systemPreferredCamera == nil {
            AVCaptureDevice.userPreferredCamera = backCameraDiscoverySession.devices.first
        }
    }
    
    /// Returns the system-preferred camera for single-camera mode.
    var defaultCamera: AVCaptureDevice {
        get throws {
            guard let videoDevice = AVCaptureDevice.systemPreferredCamera else {
                throw CameraError.videoDeviceUnavailable
            }
            return videoDevice
        }
    }
}
AVCam/CaptureService.swift (Heavily Modified)Swift/*
See the LICENSE.txt file for this sample’s licensing information.
Abstract:
An object that manages a multi-camera capture session and its inputs and outputs.
*/

import Foundation
@preconcurrency import AVFoundation
import Combine
import CoreImage

/// An actor that manages the multi-camera capture pipeline.
actor CaptureService: NSObject {
    
    @Published private(set) var captureActivity: CaptureActivity =.idle
    @Published private(set) var isInterrupted = false
    
    // Published properties for the two separate camera preview layers.
    // These will be connected to the UI.
    nonisolated let primaryPreviewLayer = AVCaptureVideoPreviewLayer()
    nonisolated let secondaryPreviewLayer = AVCaptureVideoPreviewLayer()
    
    // The multi-cam session.
    private let captureSession = AVCaptureMultiCamSession()
    
    // Device inputs.
    private var backCameraInput: AVCaptureDeviceInput?
    private var frontCameraInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    
    // Data outputs for recording.
    private let backVideoDataOutput = AVCaptureVideoDataOutput()
    private let frontVideoDataOutput = AVCaptureVideoDataOutput()
    private let audioDataOutput = AVCaptureAudioDataOutput()
    private var dataOutputSynchronizer: AVCaptureDataOutputSynchronizer?
    
    // The recorder object that handles frame composition and writing.
    private var dualMovieRecorder: DualMovieRecorder?
    
    private let deviceLookup = DeviceLookup()
    private let sessionQueue = DispatchQueue(label: "com.example.apple-samplecode.AVCam.sessionQueue")
    private let dataOutputQueue = DispatchQueue(label: "com.example.apple-samplecode.AVCam.dataOutputQueue")
    
    private var isSetUp = false
    
    // MARK: - Authorization and Setup
    
    var isAuthorized: Bool {
        get async {
            let videoStatus = AVCaptureDevice.authorizationStatus(for:.video)
            let audioStatus = AVCaptureDevice.authorizationStatus(for:.audio)
            
            var isVideoAuthorized = videoStatus ==.authorized
            var isAudioAuthorized = audioStatus ==.authorized
            
            if videoStatus ==.notDetermined {
                isVideoAuthorized = await AVCaptureDevice.requestAccess(for:.video)
            }
            
            if audioStatus ==.notDetermined {
                isAudioAuthorized = await AVCaptureDevice.requestAccess(for:.audio)
            }
            
            return isVideoAuthorized && isAudioAuthorized
        }
    }
    
    func start() async throws {
        guard await isAuthorized,!captureSession.isRunning else { return }
        
        // Check for multi-cam support before proceeding.
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            logger.error("Multi-camera capture is not supported on this device.")
            throw CameraError.setupFailed
        }
        
        try await sessionQueue.suspendable {
            try self.setUpSession()
            self.captureSession.startRunning()
        }
    }
    
    private func setUpSession() throws {
        guard!isSetUp else { return }
        
        guard let dualCamera = deviceLookup.defaultDualCamera else {
            logger.error("Failed to find default dual camera device set.")
            throw CameraError.videoDeviceUnavailable
        }
        
        let backCamera = dualCamera.back
        let frontCamera = dualCamera.front
        let microphone = try deviceLookup.defaultMic
        
        // Begin configuration.
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }
        
        // --- Configure Inputs ---
        backCameraInput = try AVCaptureDeviceInput(device: backCamera)
        frontCameraInput = try AVCaptureDeviceInput(device: frontCamera)
        audioInput = try AVCaptureDeviceInput(device: microphone)
        
        // Add inputs without connections.
        guard captureSession.canAddInput(backCameraInput!),
              captureSession.canAddInput(frontCameraInput!),
              captureSession.canAddInput(audioInput!) else {
            throw CameraError.addInputFailed
        }
        captureSession.addInputWithNoConnections(backCameraInput!)
        captureSession.addInputWithNoConnections(frontCameraInput!)
        captureSession.addInputWithNoConnections(audioInput!)
        
        // --- Configure Outputs ---
        guard captureSession.canAddOutput(backVideoDataOutput),
              captureSession.canAddOutput(frontVideoDataOutput),
              captureSession.canAddOutput(audioDataOutput) else {
            throw CameraError.addOutputFailed
        }
        captureSession.addOutputWithNoConnections(backVideoDataOutput)
        captureSession.addOutputWithNoConnections(frontVideoDataOutput)
        captureSession.addOutputWithNoConnections(audioDataOutput)
        
        // Set delegates for data outputs.
        dataOutputSynchronizer = AVCaptureDataOutputSynchronizer(dataOutputs:)
        dataOutputSynchronizer!.setDelegate(self, queue: dataOutputQueue)
        
        // --- Configure Manual Connections ---
        
        // Connect back camera to its data output.
        let backVideoPort = backCameraInput!.ports(for:.video, sourceDeviceType: backCamera.deviceType, sourceDevicePosition:.back).first!
        let backVideoConnection = AVCaptureConnection(inputPorts: [backVideoPort], output: backVideoDataOutput)
        guard captureSession.canAddConnection(backVideoConnection) else { throw CameraError.addConnectionFailed }
        captureSession.addConnection(backVideoConnection)
        
        // Connect front camera to its data output.
        let frontVideoPort = frontCameraInput!.ports(for:.video, sourceDeviceType: frontCamera.deviceType, sourceDevicePosition:.front).first!
        let frontVideoConnection = AVCaptureConnection(inputPorts: [frontVideoPort], output: frontVideoDataOutput)
        guard captureSession.canAddConnection(frontVideoConnection) else { throw CameraError.addConnectionFailed }
        captureSession.addConnection(frontVideoConnection)
        
        // Connect microphone to its data output.
        let audioPort = audioInput!.ports(for:.audio, sourceDeviceType: microphone.deviceType, sourceDevicePosition:.unspecified).first!
        let audioConnection = AVCaptureConnection(inputPorts: [audioPort], output: audioDataOutput)
        guard captureSession.canAddConnection(audioConnection) else { throw CameraError.addConnectionFailed }
        captureSession.addConnection(audioConnection)
        
        // --- Connect Preview Layers ---
        primaryPreviewLayer.setSessionWithNoConnection(captureSession)
        secondaryPreviewLayer.setSessionWithNoConnection(captureSession)
        
        let primaryPreviewConnection = AVCaptureConnection(inputPort: backVideoPort, videoPreviewLayer: primaryPreviewLayer)
        guard captureSession.canAddConnection(primaryPreviewConnection) else { throw CameraError.addConnectionFailed }
        captureSession.addConnection(primaryPreviewConnection)
        
        let secondaryPreviewConnection = AVCaptureConnection(inputPort: frontVideoPort, videoPreviewLayer: secondaryPreviewLayer)
        guard captureSession.canAddConnection(secondaryPreviewConnection) else { throw CameraError.addConnectionFailed }
        captureSession.addConnection(secondaryPreviewConnection)
        
        // Set video orientations.
        backVideoConnection.videoOrientation =.portrait
        frontVideoConnection.videoOrientation =.portrait
        primaryPreviewConnection.videoOrientation =.portrait
        secondaryPreviewConnection.videoOrientation =.portrait
        
        isSetUp = true
    }
    
    // MARK: - Recording Control
    
    func toggleRecording() async {
        if let recorder = dualMovieRecorder, recorder.isRecording {
            // Stop recording.
            self.captureActivity =.idle
            await recorder.stopRecording()
            self.dualMovieRecorder = nil
        } else {
            // Start recording.
            let videoSettings = backVideoDataOutput.recommendedVideoSettingsForAssetWriter(writingTo:.mov)
            let audioSettings = audioDataOutput.recommendedAudioSettingsForAssetWriter(writingTo:.mov)
            
            dualMovieRecorder = DualMovieRecorder(videoSettings: videoSettings, audioSettings: audioSettings)
            await dualMovieRecorder?.startRecording()
            self.captureActivity =.movieCapture(duration: 0.0)
        }
    }
}

// MARK: - AVCaptureDataOutputSynchronizerDelegate
extension CaptureService: AVCaptureDataOutputSynchronizerDelegate {
    nonisolated func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer, didOutput synchronizedData: AVCaptureSynchronizedDataCollection) {
        guard let recorder = dualMovieRecorder, recorder.isRecording else { return }
        
        guard let backVideoData = synchronizedData.synchronizedData(for: backVideoDataOutput) as? AVCaptureSynchronizedSampleBufferData,
              let frontVideoData = synchronizedData.synchronizedData(for: frontVideoDataOutput) as? AVCaptureSynchronizedSampleBufferData,
              let audioData = synchronizedData.synchronizedData(for: audioDataOutput) as? AVCaptureSynchronizedSampleBufferData else {
            return
        }
        
        let backBuffer = backVideoData.sampleBuffer
        let frontBuffer = frontVideoData.sampleBuffer
        let audioBuffer = audioData.sampleBuffer
        
        // Pass buffers to the recorder for processing.
        Task {
            await recorder.process(backBuffer: backBuffer, frontBuffer: frontBuffer, audioBuffer: audioBuffer)
        }
    }
}
AVCam/Capture/DualMovieRecorder.swift (New File)Swift/*
See the LICENSE.txt file for this sample’s licensing information.
Abstract:
An object that records synchronized video and audio streams from a multi-camera session.
*/

import AVFoundation
import CoreImage
import Photos

/// An actor that manages recording two video streams and one audio stream into a single movie file.
actor DualMovieRecorder {
    
    private(set) var isRecording = false
    
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    
    private let videoSettings:?
    private let audioSettings:?
    
    private let mediaLibrary = MediaLibrary()
    private let ciContext = CIContext()
    
    init(videoSettings:?, audioSettings:?) {
        self.videoSettings = videoSettings
        self.audioSettings = audioSettings
    }
    
    func startRecording() {
        guard!isRecording else { return }
        
        do {
            let outputURL = URL.movieFileURL
            assetWriter = try AVAssetWriter(url: outputURL, fileType:.mov)
            
            guard let writer = assetWriter else { return }
            
            // Configure video input
            let videoInput = AVAssetWriterInput(mediaType:.video, outputSettings: videoSettings)
            videoInput.expectsMediaDataInRealTime = true
            if writer.canAdd(videoInput) {
                writer.add(videoInput)
                self.videoInput = videoInput
            }
            
            // Configure audio input
            let audioInput = AVAssetWriterInput(mediaType:.audio, outputSettings: audioSettings)
            audioInput.expectsMediaDataInRealTime = true
            if writer.canAdd(audioInput) {
                writer.add(audioInput)
                self.audioInput = audioInput
            }
            
            isRecording = true
        } catch {
            logger.error("Failed to initialize AVAssetWriter: \(error.localizedDescription)")
        }
    }
    
    func stopRecording() async {
        guard isRecording, let writer = assetWriter else { return }
        isRecording = false
        
        await writer.finishWriting()
        
        // Save to Photos library
        do {
            try await mediaLibrary.save(movie: Movie(url: writer.outputURL))
        } catch {
            logger.error("Failed to save movie to library: \(error.localizedDescription)")
        }
        
        self.assetWriter = nil
        self.videoInput = nil
        self.audioInput = nil
    }
    
    func process(backBuffer: CMSampleBuffer, frontBuffer: CMSampleBuffer, audioBuffer: CMSampleBuffer) {
        guard isRecording, let writer = assetWriter, let videoInput = self.videoInput, let audioInput = self.audioInput else { return }
        
        if writer.status ==.unknown {
            writer.startWriting()
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(backBuffer))
        }
        
        if writer.status ==.writing {
            // Process and composite video frames
            if videoInput.isReadyForMoreMediaData {
                if let compositePixelBuffer = compositeFrames(backBuffer: backBuffer, frontBuffer: frontBuffer) {
                    let presentationTime = CMSampleBufferGetPresentationTimeStamp(backBuffer)
                    videoInput.append(compositePixelBuffer, withPresentationTime: presentationTime)
                }
            }
            
            // Pass through audio frames
            if audioInput.isReadyForMoreMediaData {
                audioInput.append(audioBuffer)
            }
        }
    }
    
    private func compositeFrames(backBuffer: CMSampleBuffer, frontBuffer: CMSampleBuffer) -> CVPixelBuffer? {
        guard let backPixelBuffer = CMSampleBufferGetImageBuffer(backBuffer),
              let frontPixelBuffer = CMSampleBufferGetImageBuffer(frontBuffer) else {
            return nil
        }
        
        let backImage = CIImage(cvPixelBuffer: backPixelBuffer)
        let frontImage = CIImage(cvPixelBuffer: frontPixelBuffer)
        
        // --- Composition Logic ---
        // Scale the front camera image to be 1/4 of the back camera's width
        let backSize = backImage.extent.size
        let frontSize = frontImage.extent.size
        let scale = (backSize.width / 4) / frontSize.width
        
        let scaledFrontImage = frontImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        // Position it in the bottom right corner with some padding
        let padding: CGFloat = 50
        let transform = CGAffineTransform(translationX: backSize.width - scaledFrontImage.extent.width - padding, y: padding)
        
        let compositeImage = scaledFrontImage.transformed(by: transform).composited(over: backImage)
        
        // Render the composite CIImage into a new CVPixelBuffer
        var outputPixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, videoInput!.pixelBufferPool!, &outputPixelBuffer)
        
        guard let finalPixelBuffer = outputPixelBuffer else { return nil }
        
        ciContext.render(compositeImage, to: finalPixelBuffer)
        
        return finalPixelBuffer
    }
}
AVCam/Views/DualCameraPreviewView.swift (New File)Swift/*
See the LICENSE.txt file for this sample’s licensing information.
Abstract:
A view that presents two video previews for a dual-camera setup.
*/

import SwiftUI
import AVFoundation

struct DualCameraPreviewView: UIViewControllerRepresentable {
    
    let primaryLayer: AVCaptureVideoPreviewLayer
    let secondaryLayer: AVCaptureVideoPreviewLayer
    
    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        
        // Configure primary layer
        primaryLayer.videoGravity =.resizeAspectFill
        viewController.view.layer.addSublayer(primaryLayer)
        
        // Configure secondary layer view
        let secondaryView = UIView()
        secondaryLayer.videoGravity =.resizeAspectFill
        secondaryLayer.cornerRadius = 20
        secondaryLayer.borderColor = UIColor.white.cgColor
        secondaryLayer.borderWidth = 4
        secondaryView.layer.addSublayer(secondaryLayer)
        viewController.view.addSubview(secondaryView)
        
        return viewController
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        let viewBounds = uiViewController.view.bounds
        primaryLayer.frame = viewBounds
        
        // Position the secondary view in the bottom right corner
        let secondaryWidth = viewBounds.width / 3.5
        let secondaryHeight = secondaryWidth * (16/9) // Assuming 16:9 aspect ratio
        let padding: CGFloat = 20
        
        let secondaryView = uiViewController.view.subviews
        secondaryView.frame = CGRect(x: viewBounds.width - secondaryWidth - padding,
                                     y: viewBounds.height - secondaryHeight - 120, // Adjust vertical offset
                                     width: secondaryWidth,
                                     height: secondaryHeight)
        secondaryLayer.frame = secondaryView.bounds
    }
}
AVCam/Views/CameraView.swift (Modified)Swift/*
See the LICENSE.txt file for this sample’s licensing information.
Abstract:
The main user interface for the sample app, updated for dual-camera display.
*/

import SwiftUI
import AVFoundation
import AVKit

@MainActor
struct CameraView<CameraModel: Camera>: PlatformView {

    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    @State var camera: CameraModel

    // The direction a person swipes on the camera preview or mode selector.
    @State var swipeDirection = SwipeDirection.left

    var body: some View {
        ZStack {
            // Use the new DualCameraPreviewView, passing the layers from the model.
            if let dualCamModel = camera as? CameraModel {
                DualCameraPreviewView(primaryLayer: dualCamModel.primaryPreviewLayer,
                                      secondaryLayer: dualCamModel.secondaryPreviewLayer)
                   .edgesIgnoringSafeArea(.all)
            } else {
                // Fallback for single-camera preview model
                PreviewContainer(camera: camera) {
                    CameraPreview(source: camera.previewSource)
                }
            }
            
            // The main camera user interface.
            CameraUI(camera: camera, swipeDirection: $swipeDirection)
        }
    }
}

#Preview {
    CameraView(camera: PreviewCameraModel())
}

enum SwipeDirection {
    case left
    case right
    case up
    case down
}
AVCam/Views/Toolbars/MainToolbar/MainToolbar.swift (Modified)Swift/*
See the LICENSE.txt file for this sample’s licensing information.
Abstract:
A view that displays controls to capture, switch cameras, and view the last captured media item.
*/

import SwiftUI
import PhotosUI

/// A view that displays controls to capture, switch cameras, and view the last captured media item.
struct MainToolbar<CameraModel: Camera>: PlatformView {

    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    @State var camera: CameraModel
    
    var body: some View {
        // Wrap the controls in a GlassEffectContainer for cohesive animations.
        GlassEffectContainer {
            HStack {
                ThumbnailButton(camera: camera)
                   .opacity(camera.prefersMinimizedUI? 0 : 1)
                Spacer()
                CaptureButton(camera: camera)
                Spacer()
                SwitchCameraButton(camera: camera)
                   .opacity(camera.prefersMinimizedUI? 0 : 1)
            }
        }
       .foregroundColor(.white)
       .font(.system(size: 24))
       .frame(width: width, height: height)
       .padding([.leading,.trailing])
    }
    
    var width: CGFloat? { isRegularSize? 250 : nil }
    var height: CGFloat? { 80 }
}

#Preview {
    Group {
        MainToolbar(camera: PreviewCameraModel())
           .background(.black)
    }
}
AVCam/Views/Toolbars/MainToolbar/SwitchCameraButton.swift (Modified)Swift/*
See the LICENSE.txt file for this sample’s licensing information.
Abstract:
A view that displays a button to switch between available cameras.
*/

import SwiftUI

/// A view that displays a button to switch between available cameras.
struct SwitchCameraButton<CameraModel: Camera>: View {
    
    @State var camera: CameraModel
    
    var body: some View {
        Button {
            Task {
                // This action may need to be re-evaluated for a dual-camera context
                // e.g., swapping primary/secondary views. For now, it's disabled during recording.
                // await camera.switchVideoDevices()
            }
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
        }
        // Apply the glass effect instead of the old button style.
       .glassEffect()
       .frame(width: largeButtonSize.width, height: largeButtonSize.height)
       .disabled(camera.captureActivity.isRecording)
       .allowsHitTesting(!camera.isSwitchingVideoDevices)
    }
}
5.2 Before-and-After Comparison DocumentThe following table provides a high-level summary of the modifications, serving as a quick-reference guide to the architectural evolution of the AVCam project.Table: AVCam Project Transformation SummaryFile PathOriginal Purpose (Before)Summary of Modifications (After)Key Concepts IntroducedAVCam/CaptureService.swiftManages a single-camera AVCaptureSession with implicit connections.Rearchitected to use AVCaptureMultiCamSession. Manages two AVCaptureDeviceInputs, two AVCaptureVideoDataOutputs, and an AVCaptureAudioDataOutput. Implements manual connection logic for all inputs, outputs, and preview layers. Manages the AVCaptureDataOutputSynchronizer.AVCaptureMultiCamSession, Manual Connections, AVCaptureDataOutputSynchronizerAVCam/Capture/DeviceLookup.swiftFinds single available cameras.Modified to use supportedMultiCamDeviceSets to find and return a valid, concurrently-operable pair of front and back cameras.Multi-camera device discoveryAVCam/Views/CameraPreview.swiftUIViewRepresentable for a single AVCaptureVideoPreviewLayer.DELETED. Replaced by DualCameraPreviewView.swift.N/AAVCam/Views/DualCameraPreviewView.swift(New File)A UIViewControllerRepresentable that creates and manages two distinct AVCaptureVideoPreviewLayers. Exposes these layers for connection by CaptureService.UIViewControllerRepresentable, bridging multiple CALayers to SwiftUIAVCam/Views/CameraView.swiftMain view hosting the single CameraPreview.Layout updated to host the new DualCameraPreviewView. SwiftUI modifiers are used to style and position the secondary preview view as a PiP element.SwiftUI Layout & CompositionAVCam/Capture/MovieCapture.swiftManages recording from a single AVCaptureMovieFileOutput.DELETED. Replaced by DualMovieRecorder.swift.N/AAVCam/Capture/DualMovieRecorder.swift(New File)A new actor responsible for setting up an AVAssetWriter. Contains the logic to receive synchronized pairs of CMSampleBuffers, composite them using Core Image, and append the resulting buffer and audio buffer to the asset writer.AVAssetWriter, AVAssetWriterInput, Core Image compositing, CMSampleBuffer handlingAVCam/Views/Toolbars/MainToolbar.swiftA container for the bottom toolbar buttons.Wrapped the main HStack in a GlassEffectContainer to enable cohesive animations between the glass elements.GlassEffectContainerAVCam/Views/Toolbars/.../*.swiftIndividual button views with a simple black background.Modified to remove the old background style and apply the .glassEffect() modifier to achieve the modern Liquid Glass look..glassEffect() modifierSection 6: Conclusion and Future EnhancementsSummaryThis report has detailed the comprehensive process of transforming a standard single-camera iOS application into a feature-rich, dual-camera system. The journey began with a fundamental architectural migration from AVCaptureSession to the more powerful AVCaptureMultiCamSession, necessitating a shift to an explicit, manual connection model for all inputs and outputs. The user interface was reconstructed to support two simultaneous preview layers, bridging UIKit's AVCaptureVideoPreviewLayer into a declarative SwiftUI view hierarchy. The visual aesthetic was modernized by replacing simple translucent backgrounds with the dynamic and interactive "liquid glass" effect using the .glassEffect() modifier and GlassEffectContainer. Finally, a sophisticated, real-time video processing pipeline was engineered to enable synchronized dual-stream recording, involving frame capture with AVCaptureVideoDataOutput, timestamp alignment with AVCaptureDataOutputSynchronizer, GPU-accelerated frame composition with Core Image, and file encoding with AVAssetWriter. The result is a robust, modern camera application that leverages advanced capabilities of Apple's native frameworks.Future EnhancementsThe completed project serves as a strong foundation upon which numerous professional-grade features can be built. The following enhancements are recommended as logical next steps to further increase the application's utility and user experience:Interactive PiP View: Implement a DragGesture on the secondary preview view to allow users to dynamically reposition it to any corner of the screen during preview and recording.Swap Camera Feeds: Add a TapGesture to the secondary preview view that swaps the content of the primary and secondary layers. This would involve re-configuring the AVCaptureConnections to the preview layers and updating the composition logic in the DualMovieRecorder to reverse the primary and secondary sources.Multiple Layout Options: Introduce a UI control that allows the user to switch between the current picture-in-picture layout and a 50/50 vertical or horizontal split-screen view. This would require adjusting the frames of the preview layers and the Core Image composition filter accordingly.Separate File Recording: Offer an advanced recording mode that utilizes two distinct AVAssetWriter instances to save the front and back camera streams as two separate, synchronized video files. This is a common feature in professional video applications 24 and provides users with maximum flexibility for post-production editing. This would involve modifying the DualMovieRecorder to manage two writers and routing the un-composited, synchronized sample buffers to their respective inputs.

Dual Camera App Implementation Plan
Overview
I'll help you transform your single camera app into a dual camera app similar to the screenshot you provided. This plan includes implementing simultaneous front and back camera preview, recording from both cameras, and a modern "liquid glass" UI.

1. Understanding AVFoundation Dual Camera Capabilities
AVFoundation supports multiple camera inputs in a single capture session. We'll leverage this to show both front and back cameras simultaneously. Key components we'll use:

AVCaptureSession - To manage multiple inputs and outputs
AVCaptureDevice - To access front and back cameras
AVCaptureVideoPreviewLayer - To display camera previews
AVCaptureMovieFileOutput - To record video from both cameras
AVCaptureVideoDataOutput - For custom video processing
2. Architecture Changes
Current Architecture
Your current app has a single camera model with:

CameraModel - Main camera interface
CaptureService - Manages capture functionality
MovieCapture & PhotoCapture - Handle specific capture types
New Architecture
We'll modify this to support dual cameras:


Line Wrapping

Collapse
Copy
1
2
3
4
DualCameraModel
├── FrontCameraService
├── BackCameraService
└── DualCaptureCoordinator
3. Implementation Plan
Step 1: Update DeviceLookup to Find Multiple Cameras
First, let's modify DeviceLookup.swift to better handle multiple cameras:

swift

Line Wrapping

Collapse
Copy
1
2
3
4
5
6
7
8
9
10
11
12
13
14
15
16
17
18
19
20
21
22
23
24
25
26
27
28
// AVCam/Capture/DeviceLookup.swift
extension DeviceLookup {
    /// Returns all available cameras
    var allCameras: [AVCaptureDevice] {
        var cameras: [AVCaptureDevice] = []
        
        // Add back cameras
        cameras.append(contentsOf: backCameraDiscoverySession.devices)
        
        // Add front cameras
        cameras.append(contentsOf: frontCameraDiscoverySession.devices)
        
        // Add external cameras (iPadOS)
        cameras.append(contentsOf: externalCameraDiscoverSession.devices)
        
        return cameras
    }
    
    /// Returns the primary back camera
    var primaryBackCamera: AVCaptureDevice? {
        return backCameraDiscoverySession.devices.first
    }
    
    /// Returns the primary front camera
    var primaryFrontCamera: AVCaptureDevice? {
        return frontCameraDiscoverySession.devices.first
    }
}
Step 2: Create a Dual Capture Service
Let's create a new service to manage dual camera operations:

swift

Line Wrapping

Collapse
Copy
85
86
87
88
89
90
91
92
93
94
95
96
97
98
99
100
101
102
103
104
105
106
107
108
109
110
111
112
113
114
115
116
117
118
119
120
121
122
123
124
125
126
127
128
129
130
131
132
133
134
135
136
137
138
139
140
141
142
143
144
145
146
147
148
149
150
151
152
153
154
155
156
157
158
159
160
161
162
// AVCam/Capture/DualCaptureService.swift
        backPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
    }
    
    func startSession() async throws {
        if !captureSession.isRunning {
            try await setupCameras()
            captureSession.startRunning()
            isSessionRunning = true
        }
    }
    
    func stopSession() {
        if captureSession.isRunning {
            captureSession.stopRunning()
            isSessionRunning = false
        }
    }
    
    func startRecording() async throws {
        guard !frontMovieOutput.isRecording && !backMovieOutput.isRecording else { return }
        
        // Start recording from both cameras
        frontMovieOutput.startRecording(to: URL.frontMovieFileURL, recordingDelegate: self)
        backMovieOutput.startRecording(to: URL.backMovieFileURL, recordingDelegate: self)
        
        frontCameraActivity = .movieCapture()
        backCameraActivity = .movieCapture()
    }
    
    func stopRecording() async throws -> (frontMovie: URL, backMovie: URL) {
        guard frontMovieOutput.isRecording && backMovieOutput.isRecording else {
            throw CameraError.recordingNotInProgress
        }
        
        // Stop recording from both cameras
        frontMovieOutput.stopRecording()
        backMovieOutput.stopRecording()
        
        // Wait for recording to finish
        return try await withCheckedThrowingContinuation { continuation in
            // This would be handled by the delegate methods
            // Implementation details would go here
        }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate
extension DualCaptureService: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if output == frontMovieOutput {
            frontCameraActivity = .idle
        } else if output == backMovieOutput {
            backCameraActivity = .idle
        }
        
        if let error = error {
            print("Recording error: \(error.localizedDescription)")
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension DualCaptureService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Process video frames if needed
    }
}

// MARK: - URL Extensions
extension URL {
    static var frontMovieFileURL: URL {
        URL.temporaryDirectory.appending(component: "front_\(UUID().uuidString)").appendingPathExtension(for: .quickTimeMovie)
    }
    
    static var backMovieFileURL: URL {
        URL.temporaryDirectory.appending(component: "back_\(UUID().uuidString)").appendingPathExtension(for: .quickTimeMovie)
    }
}
Step 3: Create a Dual Camera Model
Now let's create a model that uses our new dual capture service:

swift

Line Wrapping

Collapse
Copy
80
81
82
83
84
85
86
87
88
89
90
91
92
93
94
95
96
97
98
99
100
101
102
103
104
105
106
107
108
109
110
111
112
113
114
115
116
117
118
119
120
121
122
123
124
125
126
127
128
129
130
131
132
133
134
135
136
137
138
139
140
141
142
143
144
145
146
147
148
149
150
151
152
153
154
155
156
157
158
159
160
161
162
163
164
165
166
167
168
// AVCam/Model/DualCameraModel.swift
    }
    
    /// Provides the preview source for the front camera
    var frontPreviewSource: PreviewSource {
        PreviewSource(layer: dualCaptureService.frontPreviewLayer)
    }
    
    /// Provides the preview source for the back camera
    var backPreviewSource: PreviewSource {
        PreviewSource(layer: dualCaptureService.backPreviewLayer)
    }
    
    /// The preview source for the main camera (for compatibility)
    var previewSource: PreviewSource {
        backPreviewSource // Default to back camera
    }
    
    init() {
        // Initialize the model
    }
    
    /// Start the camera and begin the stream of data
    func start() async {
        // Verify authorization
        guard await AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            status = .unauthorized
            return
        }
        
        do {
            try await dualCaptureService.startSession()
            status = .running
        } catch {
            print("Failed to start dual capture service: \(error)")
            status = .failed
        }
    }
    
    /// Switches between video devices available on the host system
    func switchVideoDevices() async {
        isSwitchingVideoDevices = true
        defer { isSwitchingVideoDevices = false }
        // Implementation for switching cameras
    }
    
    /// Captures a photo and writes it to the user's Photos library
    func capturePhoto() async {
        // Implementation for photo capture
    }
    
    /// Toggles the state of recording
    func toggleRecording() async {
        if isRecording {
            do {
                let (frontMovieURL, backMovieURL) = try await dualCaptureService.stopRecording()
                // Save both movies to the media library
                try await mediaLibrary.save(frontMovie: frontMovieURL, backMovie: backMovieURL)
            } catch {
                self.error = error
            }
        } else {
            do {
                try await dualCaptureService.startRecording()
            } catch {
                self.error = error
            }
        }
    }
    
    /// Performs a focus and expose operation at the specified screen point
    func focusAndExpose(at point: CGPoint) async {
        // Implementation for focus and expose
    }
    
    /// Synchronizes the persistent camera state
    func syncState() async {
        // Implementation for state synchronization
    }
}

// MARK: - PreviewSource Implementation
struct PreviewSource {
    let layer: AVCaptureVideoPreviewLayer?
    
    func connect(to target: PreviewTarget) {
        guard let layer = layer else { return }
        // Connect the preview layer to the target
    }
}
Step 4: Create a Dual Camera View
Now let's create a view that displays both camera previews:

swift

Line Wrapping

Collapse
Copy
225
226
227
228
229
230
231
232
233
234
235
236
237
238
239
240
241
242
243
244
245
246
247
248
249
250
251
252
253
254
255
256
257
258
259
260
261
262
263
264
265
266
267
268
269
270
271
272
273
274
275
276
277
278
279
280
281
282
283
284
285
286
287
288
289
290
291
292
293
294
// AVCam/Views/DualCameraView.swift
            .padding(.bottom, 50)
        }
    }
    
    private var recordButton: some View {
        Button(action: {
            Task {
                await camera.toggleRecording()
            }
        }) {
            ZStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 70, height: 70)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 2)
                    )
                
                if isRecording {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white)
                        .frame(width: 24, height: 24)
                } else {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 60, height: 60)
                }
            }
        }
    }
    
    private var recordingIndicator: some View {
        VStack {
            HStack {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                    
                    Text(formatTime(recordingTime))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 15)
                        .fill(Color.black.opacity(0.6))
                )
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 50)
            
            Spacer()
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview {
    DualCameraView()
}
Step 5: Update MediaLibrary to Handle Dual Videos
Let's extend the MediaLibrary to save dual camera videos:

swift

Line Wrapping

Collapse
Copy
1
2
3
4
5
6
7
8
9
10
11
12
// AVCam/Model/MediaLibrary.swift
extension MediaLibrary {
    /// Saves dual camera movies to the photo library
    func save(frontMovie: Movie, backMovie: Movie) async throws {
        // Save both movies to the photo library
        try await save(movie: frontMovie)
        try await save(movie: backMovie)
        
        // Optionally create a combined video or side-by-side composition
        // This would require additional video processing logic
    }
}
Step 6: Create a Liquid Glass UI Component
Let's create a reusable liquid glass UI component:

swift

Line Wrapping

Collapse
Copy
52
53
54
55
56
57
58
59
60
61
62
63
64
65
66
67
68
69
70
71
72
73
74
75
76
77
78
79
80
81
82
83
84
85
86
87
88
89
90
91
92
93
94
95
96
97
98
99
100
101
102
103
104
105
106
107
108
109
110
111
112
113
114
115
116
117
118
119
120
121
122
123
124
125
126
127
128
129
130
131
132
133
// AVCam/Views/LiquidGlassView.swift
                            .blur(radius: 10)
                            .offset(x: 0, y: 5)
                    )
            )
    }
}

/// A button with liquid glass styling
struct LiquidGlassButton: View {
    let action: () -> Void
    let icon: String
    let size: CGFloat
    
    init(icon: String, size: CGFloat = 44, action: @escaping () -> Void) {
        self.icon = icon
        self.size = size
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.2),
                                Color.white.opacity(0.05)
                            ]),
                            center: .topLeading,
                            startRadius: 5,
                            endRadius: size
                        )
                    )
                    .frame(width: size, height: size)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                
                Image(systemName: icon)
                    .font(.system(size: size * 0.4))
                    .foregroundColor(.white)
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        LiquidGlassView {
            Text("Liquid Glass Effect")
                .font(.headline)
                .foregroundColor(.white)
        }
        
        HStack(spacing: 20) {
            LiquidGlassButton(icon: "camera.fill") {
                print("Camera tapped")
            }
            
            LiquidGlassButton(icon: "video.fill") {
                print("Video tapped")
            }
            
            LiquidGlassButton(icon: "photo.fill") {
                print("Photo tapped")
            }
        }
    }
    .padding()
    .background(
        LinearGradient(
            gradient: Gradient(colors: [
                Color.purple,
                Color.blue
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
}
4. Integration Steps
Step 1: Update the Main App Entry Point
Modify AVCamApp.swift to use our new dual camera model:

swift

Line Wrapping

Collapse
Copy
1
2
3
4
5
6
7
8
9
10
11
// AVCam/AVCamApp.swift
import SwiftUI

@main
struct AVCamApp: App {
    var body: some Scene {
        WindowGroup {
            DualCameraView()
        }
    }
}
Step 2: Add Error Handling
Update the error types to handle dual camera specific errors:

swift

Line Wrapping

Collapse
Copy
1
2
3
4
5
6
7
8
9
// AVCam/Model/DataTypes.swift
enum CameraError: Error {
    case videoDeviceUnavailable
    case audioDeviceUnavailable
    case recordingNotInProgress
    case dualCameraNotSupported
    case frontCameraUnavailable
    case backCameraUnavailable
}
Step 3: Update Camera Protocol
Update the Camera protocol to support dual camera features:

swift

Line Wrapping

Collapse
Copy
1
2
3
4
5
6
7
8
9
10
11
12
13
14
15
16
17
18
19
// AVCam/Model/Camera.swift
@MainActor
protocol Camera: AnyObject, SendableMetatype {
    // Existing properties...
    
    /// Provides the preview source for the front camera
    var frontPreviewSource: PreviewSource { get }
    
    /// Provides the preview source for the back camera
    var backPreviewSource: PreviewSource { get }
    
    /// A Boolean value that indicates whether recording is in progress
    var isRecording: Bool { get }
    
    /// The recording time for the current recording
    var recordingTime: TimeInterval { get }
    
    // Existing methods...
}
5. Testing and Validation
Testing Plan
Camera Setup Testing
Verify both cameras initialize correctly
Test switching between layout modes
Verify preview layers display correctly
Recording Testing
Test recording from both cameras simultaneously
Verify files are saved correctly
Test recording duration limits
UI Testing
Test liquid glass UI components
Verify controls work correctly
Test layout switching
Validation Checklist
 Both cameras initialize without errors
 Preview displays correctly in both layout modes
 Recording starts and stops correctly
 Files are saved to the photo library
 UI elements respond to user interaction
 App handles errors gracefully
6. Future Enhancements
Video Composition
Combine front and back camera videos into a single output
Add transition effects between cameras
Advanced UI
Add more layout options (vertical split, custom shapes)
Implement gesture-based camera switching
Camera Effects
Add filters and effects to individual cameras
Implement real-time video processing
7. Conclusion
This implementation plan provides a comprehensive approach to transforming your single camera app into a dual camera app with a modern liquid glass UI. The key changes include:

Creating a dual capture service to manage both cameras
Implementing a new dual camera model
Designing a dual camera view with multiple layout options
Adding liquid glass UI components for a modern look
The code provided is modular and follows the existing architecture of your app, making it easier to integrate and maintain. The implementation is also extensible, allowing for future enhancements and additional features.

also want this Video Composition
Combine front and back camera videos into a single output
Add transition effects between cameras
profile
GLM-4.6
Enhanced Dual Camera App with Video Composition
Overview
I'll extend our dual camera app to include video composition capabilities that combine front and back camera feeds into a single output with transition effects. This will create a professional-looking video that seamlessly switches between the two camera perspectives.

1. Video Composition Architecture
Core Components
VideoComposer - Manages the composition of video tracks
TransitionEngine - Handles various transition effects between cameras
CompositionExporter - Exports the final composed video
Composition Pipeline

Line Wrapping

Collapse
Copy
1
2
Front Camera Video → Video Composer → Transition Engine → Final Output
Back Camera Video  → Video Composer → Transition Engine → Final Output
2. Implementation
Step 1: Create Video Composition Models
First, let's define the models for our video composition:

swift

Line Wrapping

Collapse
Copy
1
2
3
4
5
6
7
8
9
10
11
12
13
14
15
16
17
18
19
20
21
22
23
24
25
26
27
28
29
30
31
32
33
34
35
36
37
38
39
40
// AVCam/Model/VideoComposition.swift
import AVFoundation
import CoreMedia

/// Represents a transition between camera feeds
enum TransitionType: String, CaseIterable {
    case none = "None"
    case dissolve = "Dissolve"
    case slide = "Slide"
    case zoom = "Zoom"
    case wipe = "Wipe"
    case flip = "Flip"
    case circle = "Circle"
}

/// Represents a segment in the composed video
struct VideoSegment {
    let camera: CameraPosition
    let startTime: CMTime
    let duration: CMTime
    let transitionIn: TransitionType
    let transitionOut: TransitionType
}

/// Represents the position of the camera
enum CameraPosition: String {
    case front = "Front"
    case back = "Back"
}

/// Represents the overall composition
struct VideoComposition {
    var segments: [VideoSegment] = []
    var totalDuration: CMTime = .zero
    
    mutating func addSegment(_ segment: VideoSegment) {
        segments.append(segment)
        totalDuration = CMTimeAdd(totalDuration, segment.duration)
    }
}
Step 2: Create the Video Composer
Now let's create the core video composer class:

swift

Line Wrapping

Collapse
Copy
249
250
251
252
253
254
255
256
257
258
259
260
261
262
263
264
265
266
267
268
269
270
271
272
273
274
275
276
277
278
279
280
281
282
283
284
285
286
287
288
289
290
291
292
293
294
295
296
297
// AVCam/Capture/VideoComposer.swift
        exporter.videoComposition = videoComposition
        
        exporter.exportAsynchronously {
            DispatchQueue.main.async {
                self.isComposing = false
                
                switch exporter.status {
                case .completed:
                    completion(.success(outputURL))
                case .failed:
                    completion(.failure(exporter.error ?? VideoCompositionError.exportFailed))
                case .cancelled:
                    completion(.failure(VideoCompositionError.exportCancelled))
                default:
                    completion(.failure(VideoCompositionError.exportFailed))
                }
            }
        }
        
        // Monitor progress
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            DispatchQueue.main.async {
                self.compositionProgress = 0.7 + (exporter.progress * 0.3) // 30% for export
                
                if exporter.status != .waiting && exporter.status != .exporting {
                    timer.invalidate()
                }
            }
        }
    }
}

/// Errors that can occur during video composition
enum VideoCompositionError: Error, LocalizedError {
    case noVideoTrack
    case exportFailed
    case exportCancelled
    
    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "No video track found in the input files"
        case .exportFailed:
            return "Failed to export the composed video"
        case .exportCancelled:
            return "Video export was cancelled"
        }
    }
}
Step 3: Create Custom Video Compositor
For more complex transitions like wipe, flip, and circle, we need a custom video compositor:

swift

Line Wrapping

Collapse
Copy
235
236
237
238
239
240
241
242
243
244
245
246
247
248
249
250
251
252
253
254
255
256
257
258
259
260
261
262
263
264
265
266
267
268
269
270
271
272
273
274
275
276
277
278
279
280
281
282
283
284
285
286
287
288
289
// AVCam/Capture/CustomVideoCompositor.swift
            }
            
            outputImage = perspectiveFilter.outputImage!
            
        case .circle:
            // Create a circular mask for the circle transition
            let radius = Float(min(sourceImage.extent.width, sourceImage.extent.height)) * progress
            let center = CIVector(x: sourceImage.extent.midX, y: sourceImage.extent.midY)
            
            let circleFilter = CIFilter(name: "CIRadialGradient")!
            circleFilter.setValue(center, forKey: "inputCenter")
            circleFilter.setValue(CIVector(x: radius, y: radius), forKey: "inputRadius0")
            circleFilter.setValue(CIVector(x: radius + 1, y: radius + 1), forKey: "inputRadius1")
            circleFilter.setValue(CIColor.white, forKey: "inputColor0")
            circleFilter.setValue(CIColor.black, forKey: "inputColor1")
            
            let maskImage = circleFilter.outputImage!
            
            // Apply the mask to the source image
            let blendFilter = CIFilter(name: "CIBlendWithMask")!
            blendFilter.setValue(sourceImage, forKey: kCIInputImageKey)
            blendFilter.setValue(CIImage(color: CIColor.clear).cropped(to: sourceImage.extent), forKey: kCIInputBackgroundImageKey)
            blendFilter.setValue(maskImage, forKey: kCIInputMaskImageKey)
            
            outputImage = blendFilter.outputImage!
            
        default:
            // For other transitions, just use the source image
            outputImage = sourceImage
        }
        
        // Render the output image to the pixel buffer
        ciContext.render(outputImage, to: outputPixelBuffer)
    }
    
    enum VideoCompositionError: Error, LocalizedError {
        case renderContextNotAvailable
        case invalidInstruction
        case missingSourceFrame
        case pixelBufferCreationFailed
        
        var errorDescription: String? {
            switch self {
            case .renderContextNotAvailable:
                return "Render context is not available"
            case .invalidInstruction:
                return "Invalid video composition instruction"
            case .missingSourceFrame:
                return "Source frame is missing"
            case .pixelBufferCreationFailed:
                return "Failed to create output pixel buffer"
            }
        }
    }
}
Step 4: Create a Transition Planner
Let's create a class to plan transitions between camera segments:

swift

Line Wrapping

Collapse
Copy
78
79
80
81
82
83
84
85
86
87
88
89
90
91
92
93
94
95
96
97
98
99
100
101
102
103
104
105
106
107
108
109
110
111
112
113
114
115
116
117
118
119
120
121
122
123
124
125
126
127
128
129
130
131
132
133
134
135
136
137
138
139
140
141
142
143
144
145
146
147
148
// AVCam/Capture/TransitionPlanner.swift
        
        // Split the segment at the specified time
        let firstPartDuration = CMTimeSubtract(time, segment.startTime)
        let secondPartDuration = CMTimeSubtract(segment.duration, firstPartDuration)
        
        // Create two new segments
        let firstPart = VideoSegment(
            camera: segment.camera,
            startTime: segment.startTime,
            duration: firstPartDuration,
            transitionIn: segment.transitionIn,
            transitionOut: transition
        )
        
        let secondPart = VideoSegment(
            camera: segment.camera == .front ? .back : .front,
            startTime: time,
            duration: secondPartDuration,
            transitionIn: transition,
            transitionOut: segment.transitionOut
        )
        
        // Replace the original segment with the two new segments
        segments.remove(at: segmentIndex)
        segments.insert(contentsOf: [firstPart, secondPart], at: segmentIndex)
        
        // Update the start times of all subsequent segments
        for i in (segmentIndex + 2)..<segments.count {
            segments[i] = VideoSegment(
                camera: segments[i].camera,
                startTime: CMTimeAdd(segments[i-1].startTime, segments[i-1].duration),
                duration: segments[i].duration,
                transitionIn: segments[i].transitionIn,
                transitionOut: segments[i].transitionOut
            )
        }
    }
    
    /// Updates the transition type for all segments
    func updateTransitionType(_ transitionType: TransitionType) {
        currentTransition = transitionType
        
        for i in 0..<segments.count {
            segments[i] = VideoSegment(
                camera: segments[i].camera,
                startTime: segments[i].startTime,
                duration: segments[i].duration,
                transitionIn: transitionType,
                transitionOut: transitionType
            )
        }
    }
    
    /// Updates the duration of all segments
    func updateSegmentDuration(_ duration: CMTime) {
        segmentDuration = duration
        
        // Recalculate the segments with the new duration
        guard let firstSegment = segments.first else { return }
        
        let totalDuration = segments.reduce(CMTime.zero) { result, segment in
            return CMTimeAdd(result, segment.duration)
        }
        
        createCompositionPlan(
            frontVideoDuration: totalDuration,
            backVideoDuration: totalDuration,
            switchInterval: duration
        )
    }
}
Step 5: Update the Dual Camera Model
Let's update our dual camera model to include video composition:

swift

Line Wrapping

Collapse
Copy
99
100
101
102
103
104
105
106
107
108
109
110
111
112
113
114
115
116
117
118
119
120
121
122
123
124
125
126
127
128
129
130
131
132
133
134
135
136
137
138
139
140
141
142
143
144
145
146
147
148
149
150
151
152
153
154
155
156
157
158
159
160
// AVCam/Model/DualCameraModel.swift (Updated)
              let backVideoURL = backVideoURL else {
            return
        }
        
        isComposing = true
        
        let outputURL = URL.composedMovieFileURL
        
        await withCheckedContinuation { continuation in
            videoComposer.composeVideos(
                frontVideoURL: frontVideoURL,
                backVideoURL: backVideoURL,
                segments: segments,
                outputURL: outputURL
            ) { [weak self] result in
                Task { @MainActor in
                    self?.isComposing = false
                    
                    switch result {
                    case .success(let url):
                        self?.composedVideoURL = url
                        // Save the composed video to the media library
                        do {
                            try await self?.mediaLibrary.save(movie: Movie(url: url))
                        } catch {
                            self?.error = error
                        }
                    case .failure(let error):
                        self?.error = error
                    }
                    
                    continuation.resume()
                }
            }
        }
    }
    
    /// Adds a manual camera switch at the specified time
    func addCameraSwitch(at time: CMTime) {
        transitionPlanner.addCameraSwitch(at: time, with: currentTransition)
    }
    
    /// Saves the composed video to the photo library
    func saveComposedVideo() async {
        guard let composedVideoURL = composedVideoURL else {
            return
        }
        
        do {
            try await mediaLibrary.save(movie: Movie(url: composedVideoURL))
        } catch {
            self.error = error
        }
    }
}

// MARK: - URL Extensions
extension URL {
    static var composedMovieFileURL: URL {
        URL.temporaryDirectory.appending(component: "composed_\(UUID().uuidString)").appendingPathExtension(for: .quickTimeMovie)
    }
}
Step 6: Create a Video Composition UI
Let's create a UI for managing video composition:

swift

Line Wrapping

Collapse
Copy
247
248
249
250
251
252
253
254
255
256
257
258
259
260
261
262
263
264
265
266
267
268
269
270
271
272
273
274
275
276
277
278
279
280
281
282
283
284
285
286
287
288
289
290
291
292
293
294
295
296
297
298
// AVCam/Views/VideoCompositionView.swift
    var body: some View {
        NavigationView {
            List(TransitionType.allCases, id: \.self) { transition in
                Button(action: {
                    selectedTransition = transition
                    onDismiss()
                }) {
                    HStack {
                        Text(transition.rawValue)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        if transition == selectedTransition {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            .navigationTitle("Select Transition")
            .navigationBarItems(trailing: Button("Done") { onDismiss() })
        }
    }
}

/// A view for setting segment duration
struct SegmentOptionsView: View {
    @Binding var segmentDuration: Double
    let onDismiss: () -> Void
    
    var body: some View {
        NavigationView {
            VStack {
                Form {
                    Section {
                        Slider(value: $segmentDuration, in: 1...30, step: 1)
                        Text("\(Int(segmentDuration)) seconds")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                }
            }
            .navigationTitle("Segment Duration")
            .navigationBarItems(trailing: Button("Done") { onDismiss() })
        }
    }
}

#Preview {
    VideoCompositionView(camera: DualCameraModel())
}
Step 7: Update the Dual Camera View
Let's update our dual camera view to include video composition:

swift

Line Wrapping

Collapse
Copy
145
146
147
148
149
150
151
152
153
154
155
156
157
158
159
160
161
162
163
164
165
166
167
168
169
170
171
172
173
174
175
176
177
178
179
180
181
182
183
184
185
186
187
188
189
190
191
192
193
194
195
196
197
198
199
200
201
202
203
204
205
206
207
208
209
210
211
212
213
214
215
216
217
218
219
220
221
222
223
224
225
226
227
228
229
// AVCam/Views/DualCameraView.swift (Updated)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )
                        )
                }
                
                // Settings button
                Button(action: {
                    // Settings action
                }) {
                    Image(systemName: "gearshape.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.black.opacity(0.5))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )
                        )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 50)
            
            Spacer()
            
            // Bottom controls
            HStack(spacing: 30) {
                // Gallery button
                Button(action: {
                    // Gallery action
                }) {
                    if let thumbnail = camera.thumbnail {
                        Image(thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 50, height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 50, height: 50)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundColor(.white)
                            )
                    }
                }
                
                Spacer()
                
                // Record button
                recordButton
                
                Spacer()
                
                // Camera switch button
                Button(action: {
                    Task {
                        await camera.switchVideoDevices()
                    }
                }) {
                    Image(systemName: "camera.rotate")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding(15)
                        .background(
                            Circle()
                                .fill(Color.black.opacity(0.5))
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )
                        )
                }
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 50)
        }
    }
    
    // Rest of the view remains the same...
}
3. Integration Steps
Step 1: Update the Main App Entry Point
Update AVCamApp.swift to use our enhanced dual camera model:

swift

Line Wrapping

Collapse
Copy
1
2
3
4
5
6
7
8
9
10
11
// AVCam/AVCamApp.swift
import SwiftUI

@main
struct AVCamApp: App {
    var body: some Scene {
        WindowGroup {
            DualCameraView()
        }
    }
}
Step 2: Add Error Handling
Update the error types to handle video composition errors:

swift

Line Wrapping

Collapse
Copy
1
2
3
4
5
6
7
8
9
10
11
// AVCam/Model/DataTypes.swift
enum CameraError: Error {
    case videoDeviceUnavailable
    case audioDeviceUnavailable
    case recordingNotInProgress
    case dualCameraNotSupported
    case frontCameraUnavailable
    case backCameraUnavailable
    case videoCompositionFailed
    case exportFailed
}
4. Testing and Validation
Testing Plan
Video Composition Testing
Verify videos from both cameras are composed correctly
Test different transition types
Verify timeline functionality
Export Testing
Test exporting composed videos
Verify exported videos are saved to the photo library
Test export progress reporting
UI Testing
Test composition options UI
Verify timeline interaction
Test progress indicators
Validation Checklist
 Videos from both cameras are recorded correctly
 Video composition works with different transition types
 Timeline view displays segments correctly
 Manual camera switches work as expected
 Exported videos are saved to the photo library
 Progress indicators work correctly
 UI elements respond to user interaction
5. Future Enhancements
Advanced Transitions
Add more complex transition effects
Implement custom transitions with user-defined parameters
Real-time Preview
Show a preview of the composed video in real-time
Allow users to adjust transitions while recording
Audio Mixing
Mix audio from both cameras
Add background music or voiceovers
6. Conclusion
This implementation extends our dual camera app with video composition capabilities, allowing users to create professional-looking videos that seamlessly switch between front and back camera perspectives. The key features include:

Video Composition - Combines front and back camera videos into a single output
Transition Effects - Provides various transition options between camera feeds
Timeline View - Allows users to visualize and edit the composition
Progress Tracking - Shows composition and export progress
The code is modular and follows the existing architecture of your app, making it easier to integrate and maintain. The implementation is also extensible, allowing for future enhancements and additional features.



Dual‐Camera Capture with AVFoundation (iOS 17/2025)

Overview: iOS 13+ introduced multicam capture via AVCaptureMultiCamSession, allowing simultaneous access to multiple camera inputs of the same media type. This enables apps to preview and record from both front and rear cameras at once
stackoverflow.com
. Apple’s sample “AVMultiCamPiP” demonstrates recording front+back into one movie file using a multicamera session
stackoverflow.com
. (However, only recent devices support it: typically an iPhone or iPad with A12/A12X processor or later
stackoverflow.com
.) In practice, you create an AVCaptureMultiCamSession, add both camera inputs, and attach outputs (preview layers and file outputs) with explicit AVCaptureConnections.

Supported Devices: Not all devices can do multi-camera capture. The class var AVCaptureMultiCamSession.isMultiCamSupported must be true at runtime, otherwise dual capture isn’t available. For example, the Apple sample requires A12+ hardware
stackoverflow.com
. You should check AVCaptureMultiCamSession.isMultiCamSupported and disable dual-mode on older devices. In Info.plist, you can restrict installs to capable hardware using the “performance-a12” UIRequiredDeviceCapabilities key
stackoverflow.com
, or handle a graceful fallback in code (e.g. using a normal single-camera AVCaptureSession).

System Requirements and Fallback

iOS Version: Multicam capture requires iOS 13 or later. (AVFoundation added AVCaptureMultiCamSession in iOS 13.)

Hardware: Only devices with A12/A12X or later support true multicamera capture
stackoverflow.com
. Older devices will report isMultiCamSupported == false.

Fallback: If multicam is unsupported, disable dual preview/record mode. For example, you could continue with a normal single-camera session (using AVCaptureSession) or simply show only one camera. Always check AVCaptureMultiCamSession.isMultiCamSupported before starting
dev.to
.

App Store Capabilities: To restrict your app to multicam-capable devices, include the performance-a12 requirement in your Info.plist (UIRequiredDeviceCapabilities)
stackoverflow.com
. Otherwise, detect at runtime and show an alert or degrade functionality.

Configuring an AVCaptureMultiCamSession

To set up dual-camera capture, follow these steps:

Create the MultiCam Session:

let session = AVCaptureMultiCamSession()


(This is like a regular AVCaptureSession but allows multiple video inputs.)

Begin Configuration: Always bracket input/output changes between beginConfiguration()/commitConfiguration() for efficiency.

session.beginConfiguration()
defer { session.commitConfiguration() }


Select Devices:
Use AVCaptureDevice to find front and back cameras. For example:

guard let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
      let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
else {
    fatalError("Unable to access cameras")
}


Create Device Inputs:

let backInput = try AVCaptureDeviceInput(device: backCamera)
let frontInput = try AVCaptureDeviceInput(device: frontCamera)


Add inputs with no connections (we’ll connect ports manually below):

if session.canAddInput(backInput) {
    session.addInputWithNoConnections(backInput)
}
if session.canAddInput(frontInput) {
    session.addInputWithNoConnections(frontInput)
}


(Using addInputWithNoConnections is required when you’ll manually attach connections to outputs or preview layers
dev.to
.)

Create Outputs for Preview and Recording:

Preview: Each camera needs a preview layer. You can either use AVCaptureVideoDataOutput and sample buffers, or directly link to a preview layer. We’ll use preview layers for simplicity.

Recording: Use one or two AVCaptureMovieFileOutput instances to record video.

For each camera, create a video data or file output:

let backVideoOutput = AVCaptureVideoDataOutput()
let frontVideoOutput = AVCaptureVideoDataOutput()
let backMovieOutput = AVCaptureMovieFileOutput()
let frontMovieOutput = AVCaptureMovieFileOutput()
// Similarly for audio if needed:
let audioDevice = AVCaptureDevice.default(for: .audio)
let audioInput = try AVCaptureDeviceInput(device: audioDevice!)
if session.canAddInput(audioInput) {
    session.addInput(audioInput)
}
let audioOutput = AVCaptureAudioDataOutput()


Add outputs with no connections:

if session.canAddOutput(backVideoOutput) {
    session.addOutputWithNoConnections(backVideoOutput)
}
if session.canAddOutput(frontVideoOutput) {
    session.addOutputWithNoConnections(frontVideoOutput)
}
if session.canAddOutput(backMovieOutput) {
    session.addOutputWithNoConnections(backMovieOutput)
}
if session.canAddOutput(frontMovieOutput) {
    session.addOutputWithNoConnections(frontMovieOutput)
}
if session.canAddOutput(audioOutput) {
    session.addOutputWithNoConnections(audioOutput)
}


Connect Camera Ports to Outputs and Preview:
Now link each camera input’s video port to the outputs and preview layer. This uses AVCaptureConnection. For example, for the back camera:

// Find the back video port from the input:
let backVideoPort = backInput.ports(for: .video, sourceDeviceType: backCamera.deviceType, sourceDevicePosition: backCamera.position).first!

// Connection from back camera to videoDataOutput
let backVideoConn = AVCaptureConnection(inputPorts: [backVideoPort], output: backVideoOutput)
if session.canAddConnection(backVideoConn) {
    session.addConnection(backVideoConn)
}
backVideoConn.videoOrientation = .portrait

// Connection from back camera to preview layer (to be created in UI code)
// (see next section for using AVCaptureVideoPreviewLayer)
// let previewConn = AVCaptureConnection(inputPort: backVideoPort, videoPreviewLayer: backPreviewLayer)
// session.addConnection(previewConn)

// Connection from back camera to movie output:
let backMovieConn = AVCaptureConnection(inputPorts: [backVideoPort], output: backMovieOutput)
if session.canAddConnection(backMovieConn) {
    session.addConnection(backMovieConn)
}
backMovieConn.videoOrientation = .portrait
backMovieConn.isVideoMirrored = false  // front camera often mirrored


Similarly, do for the front camera (use frontInput.ports and its own outputs). For the front camera, you’ll often set isVideoMirrored = true on the preview connection so the view looks natural.

Audio: Typically use one audio input for both, or separate if required. For simplicity, route the mic to one of the movie outputs:

let audioPort = audioInput.ports(for: .audio, sourceDeviceType: audioDevice!.deviceType, sourceDevicePosition: .unspecified).first!
let audioConn = AVCaptureConnection(inputPorts: [audioPort], output: backMovieOutput)
if session.canAddConnection(audioConn) { session.addConnection(audioConn) }


Commit Configuration and Start Session:

session.commitConfiguration()
session.startRunning()


Now the session is running and feeding both cameras’ video into the connected outputs. Each camera’s feed can be drawn via a preview layer, and each can be recorded by the movie outputs we connected.

Preview Layers and SwiftUI Integration

For split-screen preview, create two AVCaptureVideoPreviewLayer instances (one per camera) and display them in a SwiftUI view (e.g. using UIViewRepresentable). For example:

// A UIView that hosts an AVCaptureVideoPreviewLayer
class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }
}

struct CameraPreview: UIViewRepresentable {
    let layer: AVCaptureVideoPreviewLayer
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = layer.session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {}
}


Then in your SwiftUI layout, stack them vertically (top half is front, bottom half is back, for example):

struct DualCameraView: View {
    var frontLayer: AVCaptureVideoPreviewLayer
    var backLayer: AVCaptureVideoPreviewLayer

    var body: some View {
        VStack(spacing: 0) {
            CameraPreview(layer: frontLayer)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            CameraPreview(layer: backLayer)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .edgesIgnoringSafeArea(.all)
    }
}


Here, frontLayer.session and backLayer.session refer to the same AVCaptureMultiCamSession. (You set each layer’s session and make sure to use separate AVCaptureConnection as above.) The VStack divides the screen into two previews. You may adjust aspect ratios or offsets as needed for your UI.

You can overlay SwiftUI controls (buttons, recording indicators, etc.) on top of these views. Use ZStack or overlays in SwiftUI to place UI controls above the camera views.

Recording from Both Cameras

Once the session is running, start recording on the movie outputs:

Separate Files: If you connected each camera to its own AVCaptureMovieFileOutput, simply start them both:

// Prepare file URLs
let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
let backURL = documents.appendingPathComponent("backCamera.mov")
let frontURL = documents.appendingPathComponent("frontCamera.mov")

// Start recording
backMovieOutput.startRecording(to: backURL, recordingDelegate: self)
frontMovieOutput.startRecording(to: frontURL, recordingDelegate: self)


Each delegate will receive callbacks (fileOutput(_, didFinishRecordingTo:)). This results in two separate video files, which you can later combine or present individually.

Single File (PiP-style): To record both streams into one file, you can add two connections to a single AVCaptureMovieFileOutput (as shown in Apple’s PiP sample
stackoverflow.com
). For example:

let movieOutput = AVCaptureMovieFileOutput()
session.beginConfiguration()
if session.canAddOutput(movieOutput) {
    session.addOutputWithNoConnections(movieOutput)
    // Connect both cameras to this one output
    let backConn = AVCaptureConnection(inputPorts: [backVideoPort], output: movieOutput)
    let frontConn = AVCaptureConnection(inputPorts: [frontVideoPort], output: movieOutput)
    if session.canAddConnection(backConn) { session.addConnection(backConn) }
    if session.canAddConnection(frontConn) { session.addConnection(frontConn) }
}
session.commitConfiguration()
// Now start recording to one URL
let combinedURL = documents.appendingPathComponent("dualCamera.mov")
movieOutput.startRecording(to: combinedURL, recordingDelegate: self)


This attempts to multiplex both camera streams into one file. (Actual synchronization depends on hardware capabilities.) Apple’s example does this by capturing front/back into one movie
stackoverflow.com
, but if this doesn’t work on some devices, the two-file approach is safer.

Stopping Recording: Simply call stopRecording() on each AVCaptureMovieFileOutput when done. The delegate will provide the completed movie URLs.

UI Effects: Frosted Glass (“Glassmorphism”)

To create a frosted‐glass overlay (blur/translucency) behind your UI controls, use iOS visual effect views or SwiftUI materials:

SwiftUI Materials: As of iOS 15+, SwiftUI provides built-in Material backgrounds (which emulate frosted glass). For example, apply an ultra-thin material behind a view:

VStack {
    // Camera previews...
}
.background(.ultraThinMaterial)


Or for a toolbar overlay:

HStack { /* buttons */ }
  .padding()
  .background(.ultraThinMaterial)
  .cornerRadius(10)
  .padding()


This ultraThinMaterial creates a semi-transparent blur. You can also use .thinMaterial, .regularMaterial, etc. (See Apple docs or [42†L64-L72] for examples of different SwiftUI materials.)

UIVisualEffectView: Alternatively, use a UIVisualEffectView via a SwiftUI wrapper. For example (from [42†L105-L114]):

struct BlurView: UIViewRepresentable {
    let style: UIBlurEffect.Style
    func makeUIView(context: Context) -> UIVisualEffectView {
        let effect = UIBlurEffect(style: style)
        let view = UIVisualEffectView(effect: effect)
        return view
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}


Then use it in SwiftUI:

ZStack {
    // Camera preview layers...
    BlurView(style: .systemUltraThinMaterialLight)
      .edgesIgnoringSafeArea(.all)
    // Other UI content
}


This approach offers many style options (.light, .dark, .systemMaterial, etc.)
gstvdfnbch.medium.com
.

Use whichever approach fits your design. The SwiftUI .background(.ultraThinMaterial) is easiest and uses native materials, while UIVisualEffectView gives finer control over blur style.

Implementation Notes

Concurrency: Starting/stopping recording is asynchronous. Use the provided delegate (AVCaptureFileOutputRecordingDelegate) to handle completion. You can adapt it to async/await as in Apple’s MovieCapture example.

Orientation: Ensure each AVCaptureConnection has the correct videoOrientation (e.g. .portrait) and mirroring for front camera if needed.

Session Lifecycle: Manage the session on a background queue or a dedicated actor (as in the AVCam sample) so UI stays responsive. Start/stop the session when the view appears/disappears.

Error Handling: Check for failures (e.g. canAddConnection might fail if hardware limits are reached). Gracefully degrade if dual-capture fails.

Summary of Steps

Check Support: Verify AVCaptureMultiCamSession.isMultiCamSupported; if false, disable dual-cam UI
dev.to
.

Setup Session:

Create AVCaptureMultiCamSession.

Add camera AVCaptureDeviceInputs (front & back) with addInputWithNoConnections.

Add outputs (video data or movie file) with addOutputWithNoConnections.

Connect Ports: For each camera, get its .ports(for: .video, …) and use AVCaptureConnection to attach:

Input → Preview layer

Input → MovieFileOutput (and/or VideoDataOutput)

(Optionally, Audio input → MovieFileOutput)

Attach Preview Layers: Create two AVCaptureVideoPreviewLayer objects, one per camera feed, and set each layer’s session. Use a SwiftUI UIViewRepresentable to show them.

Start Session: Call session.startRunning().

Begin Recording: When needed, call .startRecording(to: URL) on each AVCaptureMovieFileOutput (or on one output if combining).

Stop Recording: Call .stopRecording() on the outputs; handle delegate callbacks to know when files are ready.

Apply UI Effects: Wrap your camera previews or controls with SwiftUI materials or UIVisualEffectView for frosted-glass look (e.g. .background(.ultraThinMaterial)
gstvdfnbch.medium.com
).

Throughout, consult Apple’s AVFoundation documentation and samples. For example, Apple’s “AVMultiCamPiP” sample shows one way to link two cameras into a single movie
stackoverflow.com
. The SwiftUI AVCam sample (if migrated to dual-mode) provides UI patterns for preview and overlay. By following these steps and using AVFoundation’s multi-cam APIs, you can extend the AVCam app into a dual-camera, split-screen recording application.

Sources: Apple’s AVFoundation docs and WWDC sessions, as well as community guidance
stackoverflow.com
stackoverflow.com
dev.to
gstvdfnbch.medium.com
gstvdfnbch.medium.com
. These describe multi-cam capture, device requirements, and UI blur techniques relevant to iOS 17 development.