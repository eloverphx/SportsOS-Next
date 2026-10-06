import AVFoundation
import CoreMedia
import Foundation
import VideoToolbox

struct EncoderMetrics: Sendable {
    let bitrateMbps: Double
    let framesPerSecond: Double
    let totalBytes: Int64
    }
struct EncodedVideoFrame: @unchecked Sendable {
    let data: Data
    let presentationTimeStamp: CMTime
    let isKeyFrame: Bool
    }

final class H264Encoder: @unchecked Sendable {
    var onMetrics: (@Sendable (EncoderMetrics) -> Void)?
    var onEncodedFrame:
        (@Sendable (EncodedVideoFrame) -> Void)?

    private let queue = DispatchQueue(
        label: "online.crashthenet.sportsoscamera.h264"
    )

    private var compressionSession: VTCompressionSession?

    private var configuredWidth = 0
    private var configuredHeight = 0
    private var configuredFPS = 0
    private var configuredBitrate = 0

    private var totalBytes: Int64 = 0
    private var intervalBytes: Int64 = 0
    private var intervalFrames: Int64 = 0
    private var intervalStartedAt = CFAbsoluteTimeGetCurrent()

    private(set) var running = false

    private var forceNextKeyFrame =
        false

    func forceKeyFrame() {
        queue.async {
            [weak self] in

            guard
                let self,
                self.running
            else {
                return
            }

            self.forceNextKeyFrame =
                true
        }
    }

    func start(
        width: Int,
        height: Int,
        fps: Int,
        bitrateMbps: Double
    ) {
        queue.async { [weak self] in
            guard let self else {
                return
            }

            self.stopLocked()

            let bitrate = Int(
                bitrateMbps * 1_000_000.0
            )

            var session: VTCompressionSession?

            let status = VTCompressionSessionCreate(
                allocator: kCFAllocatorDefault,
                width: Int32(width),
                height: Int32(height),
                codecType: kCMVideoCodecType_H264,
                encoderSpecification: nil,
                imageBufferAttributes: nil,
                compressedDataAllocator: nil,
                outputCallback: Self.outputCallback,
                refcon: Unmanaged.passUnretained(self)
                    .toOpaque(),
                compressionSessionOut: &session
            )

            guard
                status == noErr,
                let session
            else {
                return
            }

            self.compressionSession = session
            self.configuredWidth = width
            self.configuredHeight = height
            self.configuredFPS = fps
            self.configuredBitrate = bitrate

            VTSessionSetProperty(
                session,
                key: kVTCompressionPropertyKey_RealTime,
                value: kCFBooleanTrue
            )

            VTSessionSetProperty(
                session,
                key: kVTCompressionPropertyKey_AllowFrameReordering,
                value: kCFBooleanFalse
            )

            VTSessionSetProperty(
                session,
                key: kVTCompressionPropertyKey_ProfileLevel,
                value: kVTProfileLevel_H264_Main_AutoLevel
            )

            let bitrateNumber =
                NSNumber(value: bitrate)

            VTSessionSetProperty(
                session,
                key: kVTCompressionPropertyKey_AverageBitRate,
                value: bitrateNumber
            )

            let expectedFPS =
                NSNumber(value: fps)

            VTSessionSetProperty(
                session,
                key: kVTCompressionPropertyKey_ExpectedFrameRate,
                value: expectedFPS
            )

            let keyFrameInterval =
                NSNumber(value: max(fps * 2, 30))

            VTSessionSetProperty(
                session,
                key: kVTCompressionPropertyKey_MaxKeyFrameInterval,
                value: keyFrameInterval
            )

            /*
             Limit short bursts to roughly 125% of target bitrate.
             VideoToolbox expects bytes/second here.
            */
            let bytesPerSecond =
                max(
                    Int(
                        Double(bitrate) /
                        8.0 *
                        1.25
                    ),
                    1
                )

            let dataRateLimits: NSArray = [
                NSNumber(value: bytesPerSecond),
                NSNumber(value: 1)
            ]

            VTSessionSetProperty(
                session,
                key: kVTCompressionPropertyKey_DataRateLimits,
                value: dataRateLimits
            )

            let prepareStatus =
                VTCompressionSessionPrepareToEncodeFrames(
                    session
                )

            guard prepareStatus == noErr else {
                self.stopLocked()
                return
            }

            self.totalBytes = 0
            self.intervalBytes = 0
            self.intervalFrames = 0
            self.intervalStartedAt =
                CFAbsoluteTimeGetCurrent()

            self.running = true
        }
    }

    func stop(
        completion: (() -> Void)? = nil
    ) {
        queue.async {
            [weak self] in

            self?.stopLocked()
            completion?()
        }
    }

    func encode(
        sampleBuffer: CMSampleBuffer
    ) {
        guard
            let imageBuffer =
                CMSampleBufferGetImageBuffer(
                    sampleBuffer
                )
        else {
            return
        }

        let presentationTime =
            CMSampleBufferGetPresentationTimeStamp(
                sampleBuffer
            )

        queue.async { [weak self] in
            guard
                let self,
                self.running,
                let session =
                    self.compressionSession
            else {
                return
            }

            var flags =
                VTEncodeInfoFlags()

            let frameProperties:
                CFDictionary?

            if self.forceNextKeyFrame {
                frameProperties = [
                    kVTEncodeFrameOptionKey_ForceKeyFrame:
                        true
                ] as CFDictionary

                self.forceNextKeyFrame =
                    false

                print(
                    "[SportsOSCamera][H264]",
                    "forcing reconnect keyframe"
                )
            } else {
                frameProperties =
                    nil
            }

            VTCompressionSessionEncodeFrame(
                session,
                imageBuffer: imageBuffer,
                presentationTimeStamp:
                    presentationTime,
                duration: .invalid,
                frameProperties:
                    frameProperties,
                sourceFrameRefcon: nil,
                infoFlagsOut: &flags
            )
        }
    }

    private func stopLocked() {
        running = false
        forceNextKeyFrame = false

        if let session = compressionSession {
            VTCompressionSessionCompleteFrames(
                session,
                untilPresentationTimeStamp: .invalid
            )

            VTCompressionSessionInvalidate(
                session
            )
        }

        compressionSession = nil
    }

    private func handleEncodedFrame(
        _ sampleBuffer: CMSampleBuffer
    ) {
        guard
            CMSampleBufferDataIsReady(
                sampleBuffer
            )
        else {
            return
        }

        let attachments =
            CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer,
                createIfNecessary: false
            ) as? [[CFString: Any]]

        let isKeyFrame =
            !(attachments?.first?[
                kCMSampleAttachmentKey_NotSync
            ] as? Bool ?? false)

        var annexB = Data()

        /*
         For an IDR/key frame, prepend SPS and PPS so a receiver
         can begin decoding without depending on earlier packets.
        */
        if isKeyFrame,
           let formatDescription =
                CMSampleBufferGetFormatDescription(
                    sampleBuffer
                )
        {
            appendParameterSets(
                from: formatDescription,
                to: &annexB
            )
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

        var encodedData =
            Data(count: length)

        let copyStatus =
            encodedData.withUnsafeMutableBytes {
                bytes -> OSStatus in

                guard let base =
                    bytes.baseAddress
                else {
                    return -1
                }

                return CMBlockBufferCopyDataBytes(
                    blockBuffer,
                    atOffset: 0,
                    dataLength: length,
                    destination: base
                )
            }

        guard copyStatus == kCMBlockBufferNoErr else {
            return
        }

        /*
         VideoToolbox emits AVCC:
           [4-byte length][NAL][4-byte length][NAL]

         Convert it to Annex-B:
           00 00 00 01 [NAL]
        */
        var offset = 0

        while offset + 4 <= encodedData.count {
            /*
             Read the AVCC 4-byte big-endian NAL length
             byte-by-byte.

             Do not use UnsafeRawPointer.load(as: UInt32.self)
             here because Data does not guarantee that an
             arbitrary offset is naturally aligned for UInt32
             access on ARM64.
            */
            let nalLength =
                encodedData[
                    offset ..< offset + 4
                ]
                .reduce(0) {
                    ($0 << 8) |
                    Int($1)
                }

            offset += 4

            guard
                nalLength > 0,
                offset + nalLength <=
                    encodedData.count
            else {
                break
            }

            annexB.append(
                contentsOf: [
                    0x00,
                    0x00,
                    0x00,
                    0x01
                ]
            )

            annexB.append(
                encodedData[
                    offset ..<
                    offset + nalLength
                ]
            )

            offset += nalLength
        }

        guard !annexB.isEmpty else {
            return
        }

        let bytes = annexB.count

        totalBytes += Int64(bytes)
        intervalBytes += Int64(bytes)
        intervalFrames += 1

        let presentationTimeStamp =
            CMSampleBufferGetPresentationTimeStamp(
                sampleBuffer
            )

        onEncodedFrame?(
            EncodedVideoFrame(
                data: annexB,
                presentationTimeStamp:
                    presentationTimeStamp,
                isKeyFrame: isKeyFrame
            )
        )

        let now =
            CFAbsoluteTimeGetCurrent()

        let elapsed =
            now - intervalStartedAt

        guard elapsed >= 1.0 else {
            return
        }

        let bitrate =
            Double(intervalBytes) *
            8.0 /
            elapsed /
            1_000_000.0

        let fps =
            Double(intervalFrames) /
            elapsed

        let metrics =
            EncoderMetrics(
                bitrateMbps: bitrate,
                framesPerSecond: fps,
                totalBytes: totalBytes
            )

        intervalBytes = 0
        intervalFrames = 0
        intervalStartedAt = now

        onMetrics?(metrics)
    }
    private func appendParameterSets(
        from formatDescription:
            CMFormatDescription,
        to data: inout Data
    ) {
        var parameterSetCount = 0

        let countStatus =
            CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                formatDescription,
                parameterSetIndex: 0,
                parameterSetPointerOut: nil,
                parameterSetSizeOut: nil,
                parameterSetCountOut:
                    &parameterSetCount,
                nalUnitHeaderLengthOut: nil
            )

        guard countStatus == noErr else {
            return
        }

        for index in 0..<parameterSetCount {
            var pointer:
                UnsafePointer<UInt8>?

            var size = 0

            let status =
                CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                    formatDescription,
                    parameterSetIndex: index,
                    parameterSetPointerOut:
                        &pointer,
                    parameterSetSizeOut:
                        &size,
                    parameterSetCountOut: nil,
                    nalUnitHeaderLengthOut: nil
                )

            guard
                status == noErr,
                let pointer,
                size > 0
            else {
                continue
            }

            data.append(
                contentsOf: [
                    0x00,
                    0x00,
                    0x00,
                    0x01
                ]
            )

            data.append(
                pointer,
                count: size
            )
        }
    }
    private static let outputCallback:
        VTCompressionOutputCallback = {
            refcon,
            _,
            status,
            infoFlags,
            sampleBuffer in

            guard status == noErr else {
                return
            }

            guard
                !infoFlags.contains(
                    .frameDropped
                ),
                let sampleBuffer,
                let refcon
            else {
                return
            }

            let encoder =
                Unmanaged<H264Encoder>
                    .fromOpaque(refcon)
                    .takeUnretainedValue()

            encoder.queue.async {
                encoder.handleEncodedFrame(
                    sampleBuffer
                )
            }
        }
}
