import AVFoundation
import Combine
import CoreMedia
import Foundation

@MainActor
final class CameraController: NSObject, ObservableObject {

    enum CameraLens: String, CaseIterable, Identifiable {
        case ultraWide = "0.5×"
        case wide = "1×"
        case telephoto = "2×"

        var id: String { rawValue }
    }

    enum AudioMode: String, CaseIterable, Identifiable {
        case auto = "AUTO"
        case manual = "MANUAL"
        case raw = "RAW"

        var id: String { rawValue }
    }

    let session = AVCaptureSession()

    @Published var permissionGranted = false
    @Published var running = false

    @Published var selectedLens: CameraLens = .wide
    @Published var zoomFactor: CGFloat = 1.0
    @Published var stabilizationMode = "Auto"

    @Published var muted = false
    @Published var audioMode: AudioMode = .auto
    @Published var inputGain: Double = 0.62
    @Published var audioLevel: Double = 0
    @Published var clipping = false

    @Published var availableAudioInputs:
        [AVAudioSessionPortDescription] = []

    @Published var selectedAudioInputUID: String?

    @Published private(set) var activeAudioInputName =
        "Unknown"

    @Published private(set) var activeVideoWidth = 1920
    @Published private(set) var activeVideoHeight = 1080
    @Published private(set) var activeVideoFPS = 30

    @Published private(set) var encoderRunning = false
    @Published private(set) var encoderBitrateMbps = 0.0
    @Published private(set) var encoderFPS = 0.0
    @Published private(set) var encodedBytes: Int64 = 0
    @Published private(set) var encodedFrameCount: Int64 = 0
    @Published private(set) var keyFrameCount: Int64 = 0

    private let sessionQueue = DispatchQueue(
        label: "online.crashthenet.sportsoscamera.capture"
    )

    private let audioQueue = DispatchQueue(
        label: "online.crashthenet.sportsoscamera.audio"
    )

    private let videoQueue = DispatchQueue(
        label: "online.crashthenet.sportsoscamera.video"
    )

    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?

    private let audioOutput =
        AVCaptureAudioDataOutput()

    private let videoOutput =
        AVCaptureVideoDataOutput()

    private let encoder =
        H264Encoder()

    override init() {
        super.init()

        audioOutput.setSampleBufferDelegate(
            self,
            queue: audioQueue
        )

        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]

        videoOutput.alwaysDiscardsLateVideoFrames = true


        encoder.onMetrics = {
            [weak self] metrics in

            Task { @MainActor in
                guard let self else {
                    return
                }

                self.encoderBitrateMbps =
                    metrics.bitrateMbps

                self.encoderFPS =
                    metrics.framesPerSecond

                self.encodedBytes =
                    metrics.totalBytes
            }
        }

        encoder.onEncodedFrame = {
            [weak self] frame in

            Task { @MainActor in
                guard let self else {
                    return
                }

                self.encodedFrameCount += 1

                if frame.isKeyFrame {
                    self.keyFrameCount += 1
                }
            }
        }
    }

    func requestPermissionsAndConfigure() async {
        let cameraAllowed =
            await AVCaptureDevice.requestAccess(
                for: .video
            )

        let micAllowed =
            await AVCaptureDevice.requestAccess(
                for: .audio
            )

        permissionGranted =
            cameraAllowed && micAllowed

        guard permissionGranted else {
            return
        }

        configureAudioSession()
        configureCaptureSession()
        refreshAudioInputs()
    }

    func applyStreamProfile(
        _ profile:
            NetworkQualityMonitor.StreamProfile
    ) async -> Bool {

        await withCheckedContinuation {
            continuation in

            sessionQueue.async {
                [weak self] in

                guard
                    let self,
                    let device =
                        self.videoInput?.device
                else {
                    continuation.resume(
                        returning: false
                    )
                    return
                }

                let requestedWidth: Int32
                let requestedHeight: Int32
                let requestedFPS: Double

                switch profile {

                case .full1080p60,
                     .reduced1080p60:

                    requestedWidth = 1920
                    requestedHeight = 1080
                    requestedFPS = 60

                case .hd720p60:

                    requestedWidth = 1280
                    requestedHeight = 720
                    requestedFPS = 60

                case .hd720p30:

                    requestedWidth = 1280
                    requestedHeight = 720
                    requestedFPS = 30

                case .sd540p30:

                    requestedWidth = 1280
                    requestedHeight = 720
                    requestedFPS = 30
                }

                let matchingFormats =
                    device.formats.filter {
                        format in

                        let dimensions =
                            CMVideoFormatDescriptionGetDimensions(
                                format.formatDescription
                            )

                        guard
                            dimensions.width ==
                                requestedWidth,
                            dimensions.height ==
                                requestedHeight
                        else {
                            return false
                        }

                        return format
                            .videoSupportedFrameRateRanges
                            .contains {
                                $0.minFrameRate <=
                                    requestedFPS &&
                                $0.maxFrameRate >=
                                    requestedFPS
                            }
                    }

                guard
                    let selectedFormat =
                        matchingFormats.first
                else {
                    continuation.resume(
                        returning: false
                    )
                    return
                }

                do {
                    try device
                        .lockForConfiguration()

                    device.activeFormat =
                        selectedFormat

                    let frameDuration =
                        CMTime(
                            value: 1,
                            timescale:
                                CMTimeScale(
                                    requestedFPS
                                )
                        )

                    device
                        .activeVideoMinFrameDuration =
                            frameDuration

                    device
                        .activeVideoMaxFrameDuration =
                            frameDuration

                    device.unlockForConfiguration()

                    Task { @MainActor in
                        self.activeVideoWidth =
                            Int(requestedWidth)

                        self.activeVideoHeight =
                            Int(requestedHeight)

                        self.activeVideoFPS =
                            Int(requestedFPS)
                    }

                    continuation.resume(
                        returning: true
                    )

                } catch {
                    continuation.resume(
                        returning: false
                    )
                }
            }
        }
    }

    func startEncoder(
        profile:
            NetworkQualityMonitor.StreamProfile
    ) {
        encodedFrameCount = 0
        keyFrameCount = 0
        encoderBitrateMbps = 0
        encoderFPS = 0
        encodedBytes = 0





        videoOutput.setSampleBufferDelegate(
            self,
            queue: videoQueue
        )

        encoder.start(


            width: activeVideoWidth,
            height: activeVideoHeight,
            fps: activeVideoFPS,
            bitrateMbps:
                profile.targetBitrateMbps
        )

        encoderRunning = true
    }

    func restartEncoderAfterInterruption(
        profile:
            NetworkQualityMonitor.StreamProfile
    ) {
        guard encoderRunning else {
            return
        }

        /*
         AVCaptureSession itself resumes after foregrounding.
         Recreate only the VideoToolbox compression session.

         Keep frame/key counters intact so interruption
         continuity remains visible during testing.
        */
        encoder.start(
            width: activeVideoWidth,
            height: activeVideoHeight,
            fps: activeVideoFPS,
            bitrateMbps:
                profile.targetBitrateMbps
        )
    }

    func stopEncoder() {
        videoOutput.setSampleBufferDelegate(
            nil,
            queue: nil
        )

        encoder.stop()

        encoderRunning = false
        encoderBitrateMbps = 0
        encoderFPS = 0
    }

    private func configureCaptureSession() {

        sessionQueue.async {
            [weak self] in

            guard let self else {
                return
            }

            self.session.usesApplicationAudioSession = true

            /*
             SportsOS owns microphone routing.

             AVCaptureSession's default automatic audio-session
             configuration can choose the built-in microphone based
             on camera position. Disable that behavior so an operator
             selected AVAudioSession preferredInput can become the
             actual capture route.
            */
            self.session
                .automaticallyConfiguresApplicationAudioSession =
                    false

            if #available(iOS 26.0, *) {
                self.session
                    .configuresApplicationAudioSessionForBluetoothHighQualityRecording =
                        true
            }

            self.session.beginConfiguration()

            self.session.sessionPreset =
                .inputPriority

            defer {
                self.session
                    .commitConfiguration()
            }

            self.removeVideoInput()

            guard
                let camera =
                    self.device(for: .wide),
                let input =
                    try? AVCaptureDeviceInput(
                        device: camera
                    ),
                self.session.canAddInput(
                    input
                )
            else {
                return
            }

            self.session.addInput(input)
            self.videoInput = input

            if
                let microphone =
                    AVCaptureDevice.default(
                        for: .audio
                    ),
                let micInput =
                    try? AVCaptureDeviceInput(
                        device: microphone
                    ),
                self.session.canAddInput(
                    micInput
                )
            {
                self.session.addInput(
                    micInput
                )

                self.audioInput =
                    micInput
            }

            if self.session.canAddOutput(
                self.audioOutput
            ) {
                self.session.addOutput(
                    self.audioOutput
                )
            }

            if self.session.canAddOutput(
                self.videoOutput
            ) {
                self.session.addOutput(
                    self.videoOutput
                )
            }

            self.applyVideoSettings()
        }
    }

    func start() {

        sessionQueue.async {
            [weak self] in

            guard let self else {
                return
            }

            if !self.session.isRunning {
                self.session.startRunning()
            }

            Task { @MainActor in
                self.running =
                    self.session.isRunning
            }
        }
    }

    func stop() {

        stopEncoder()

        sessionQueue.async {
            [weak self] in

            guard let self else {
                return
            }

            if self.session.isRunning {
                self.session.stopRunning()
            }

            Task { @MainActor in
                self.running = false
            }
        }
    }

    func selectLens(
        _ lens: CameraLens
    ) {
        selectedLens = lens

        sessionQueue.async {
            [weak self] in

            guard let self else {
                return
            }

            guard
                let device =
                    self.device(for: lens)
            else {
                return
            }

            let wasRunning =
                self.session.isRunning

            self.session
                .beginConfiguration()

            self.removeVideoInput()

            if
                let input =
                    try? AVCaptureDeviceInput(
                        device: device
                    ),
                self.session.canAddInput(
                    input
                )
            {
                self.session.addInput(
                    input
                )

                self.videoInput =
                    input
            }

            self.session
                .commitConfiguration()

            self.applyVideoSettings()

            if
                wasRunning &&
                !self.session.isRunning
            {
                self.session.startRunning()
            }
        }
    }

    func setZoom(
        _ value: CGFloat
    ) {
        zoomFactor = value

        sessionQueue.async {
            [weak self] in

            guard
                let self,
                let device =
                    self.videoInput?.device
            else {
                return
            }

            let minimum =
                device
                    .minAvailableVideoZoomFactor

            let maximum =
                min(
                    device
                        .maxAvailableVideoZoomFactor,
                    8.0
                )

            let requested =
                min(
                    max(
                        value,
                        minimum
                    ),
                    maximum
                )

            do {
                try device
                    .lockForConfiguration()

                device.videoZoomFactor =
                    requested

                device
                    .unlockForConfiguration()

            } catch {
                return
            }
        }
    }

    func setStabilization(
        _ value: String
    ) {
        stabilizationMode = value

        sessionQueue.async {
            [weak self] in

            self?.applyVideoSettings()
        }
    }

    private func applyVideoSettings() {

        guard
            let connection =
                videoOutput.connection(
                    with: .video
                )
                ?? session.connections.first(
                    where: {
                        $0.inputPorts.contains(
                            where: {
                                $0.mediaType ==
                                    .video
                            }
                        )
                    }
                )
        else {
            return
        }

        let preferred:
            AVCaptureVideoStabilizationMode

        switch stabilizationMode {

        case "Standard":
            preferred = .standard

        case "Cinematic":
            preferred = .cinematic

        case "Off":
            preferred = .off

        default:
            preferred = .auto
        }

        if connection
            .isVideoStabilizationSupported
        {
            connection
                .preferredVideoStabilizationMode =
                    preferred
        }
    }

    private func removeVideoInput() {

        if let videoInput {
            session.removeInput(
                videoInput
            )

            self.videoInput = nil
        }
    }

    private func device(
        for lens: CameraLens
    ) -> AVCaptureDevice? {

        let requestedType:
            AVCaptureDevice.DeviceType

        switch lens {

        case .ultraWide:
            requestedType =
                .builtInUltraWideCamera

        case .wide:
            requestedType =
                .builtInWideAngleCamera

        case .telephoto:
            requestedType =
                .builtInTelephotoCamera
        }

        return AVCaptureDevice.default(
            requestedType,
            for: .video,
            position: .back
        )
        ?? AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        )
    }

    private func configureAudioSession() {

        let audioSession =
            AVAudioSession
                .sharedInstance()

        do {
            try audioSession.setCategory(
                .playAndRecord,
                mode: .videoRecording,
                options: [
                    .allowBluetoothHFP,
                    .defaultToSpeaker
                ]
            )

            try audioSession
                .setActive(true)

        } catch {
            return
        }
    }

    func refreshAudioInputs() {

        let audioSession =
            AVAudioSession
                .sharedInstance()

        availableAudioInputs =
            audioSession.availableInputs
            ?? []

        if selectedAudioInputUID == nil {

            selectedAudioInputUID =
                audioSession
                    .preferredInput?
                    .uid
                ?? availableAudioInputs
                    .first?
                    .uid
        }

        refreshActiveAudioInput()
    }

    func refreshActiveAudioInput() {

        let audioSession =
            AVAudioSession
                .sharedInstance()

        if let input =
            audioSession
                .currentRoute
                .inputs
                .first
        {
            activeAudioInputName =
                input.portName

            return
        }

        if let preferred =
            audioSession
                .preferredInput
        {
            activeAudioInputName =
                preferred.portName

            return
        }

        activeAudioInputName =
            "No Active Input"
    }

    func selectAudioInput(
        uid: String
    ) {

        guard
            let input =
                availableAudioInputs
                    .first(
                        where: {
                            $0.uid == uid
                        }
                    )
        else {
            return
        }

        let audioSession =
            AVAudioSession
                .sharedInstance()

        do {
            print(
                "[SportsOSCamera][AUDIO] requesting input:",
                input.portName,
                "type:",
                input.portType.rawValue,
                "uid:",
                input.uid
            )

            try audioSession
                .setPreferredInput(
                    input
                )

            selectedAudioInputUID =
                uid

            print(
                "[SportsOSCamera][AUDIO] preferred input:",
                audioSession
                    .preferredInput?
                    .portName
                    ?? "nil"
            )

            print(
                "[SportsOSCamera][AUDIO] active input immediately after request:",
                audioSession
                    .currentRoute
                    .inputs
                    .first?
                    .portName
                    ?? "nil"
            )

        } catch {
            print(
                "[SportsOSCamera][AUDIO] setPreferredInput failed:",
                error.localizedDescription
            )
        }
    }

    private func encodeVideoSample(
        _ sampleBuffer:
            CMSampleBuffer
    ) {
        guard encoderRunning else {
            return
        }

        encoder.encode(
            sampleBuffer:
                sampleBuffer
        )
    }
}

extension CameraController:
    AVCaptureAudioDataOutputSampleBufferDelegate,
    AVCaptureVideoDataOutputSampleBufferDelegate {

    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer:
            CMSampleBuffer,
        from connection:
            AVCaptureConnection
    ) {

        if output
            is AVCaptureVideoDataOutput
        {
            Task {
                @MainActor [weak self] in

                self?
                    .encodeVideoSample(
                        sampleBuffer
                    )
            }

            return
        }

        guard
            let blockBuffer =
                CMSampleBufferGetDataBuffer(
                    sampleBuffer
                )
        else {
            return
        }

        let length =
            CMBlockBufferGetDataLength(
                blockBuffer
            )

        guard length > 0 else {
            return
        }

        var data =
            Data(count: length)

        let result =
            data.withUnsafeMutableBytes {
                bytes in

                guard
                    let base =
                        bytes.baseAddress
                else {
                    return
                        kCMBlockBufferBadCustomBlockSourceErr
                }

                return
                    CMBlockBufferCopyDataBytes(
                        blockBuffer,
                        atOffset: 0,
                        dataLength: length,
                        destination: base
                    )
            }

        guard
            result ==
                kCMBlockBufferNoErr
        else {
            return
        }

        let samples =
            data.withUnsafeBytes {
                raw -> [Int16] in

                let count =
                    raw.count /
                    MemoryLayout<Int16>
                        .size

                return Array(
                    raw.bindMemory(
                        to: Int16.self
                    )
                    .prefix(count)
                )
            }

        guard !samples.isEmpty else {
            return
        }

        let sum =
            samples.reduce(0.0) {

                let normalized =
                    Double($1) /
                    Double(Int16.max)

                return
                    $0 +
                    normalized *
                    normalized
            }

        let rms =
            sqrt(
                sum /
                Double(
                    samples.count
                )
            )

        let db =
            20.0 *
            log10(
                max(
                    rms,
                    0.000_001
                )
            )

        let normalizedLevel =
            min(
                max(
                    (db + 50.0) /
                        50.0,
                    0.0
                ),
                1.0
            )

        Task {
            @MainActor [weak self] in

            guard let self else {
                return
            }

            if self.muted {
                self.audioLevel = 0
                self.clipping = false
            } else {
                self.audioLevel =
                    normalizedLevel

                self.clipping =
                    db > -1.0
            }
        }
    }
}
