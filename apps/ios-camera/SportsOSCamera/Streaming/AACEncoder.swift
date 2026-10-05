import AVFoundation
import CoreMedia
import Foundation

struct EncodedAudioFrame:
    @unchecked Sendable
{
    let data: Data
    let presentationTimeStamp: CMTime
    let sampleRate: Double
    let channelCount: UInt32
    let samplesPerPacket: UInt32
}

struct AudioEncoderMetrics: Sendable {
    let packetCount: Int64
    let totalBytes: Int64
}

final class AACEncoder:
    @unchecked Sendable
{
    var onEncodedFrame:
        (@Sendable (EncodedAudioFrame) -> Void)?

    var onMetrics:
        (@Sendable (AudioEncoderMetrics) -> Void)?

    private let queue =
        DispatchQueue(
            label:
                "online.crashthenet.sportsoscamera.aac"
        )

    private var converter:
        AVAudioConverter?

    private var inputFormat:
        AVAudioFormat?

    private var outputFormat:
        AVAudioFormat?

    private var pendingPCM =
        Data()

    private var nextPacketPTS:
        CMTime?

    private var lastInputEndPTS:
        CMTime?

    private var configuredSampleRate:
        Double = 0

    private var configuredChannels:
        UInt32 = 0

    private var packetCount:
        Int64 = 0

    private var totalBytes:
        Int64 = 0

    private var lastMetricsAt =
        CFAbsoluteTimeGetCurrent()

    private(set) var running =
        false

    private let samplesPerAACPacket =
        1024

    private let targetBitrate =
        128_000

    func start() {
        queue.async {
            [weak self] in

            guard let self else {
                return
            }

            self.running = true
            self.converter = nil
            self.inputFormat = nil
            self.outputFormat = nil

            self.pendingPCM.removeAll(
                keepingCapacity: true
            )

            self.nextPacketPTS = nil
            self.lastInputEndPTS = nil

            self.configuredSampleRate = 0
            self.configuredChannels = 0

            self.packetCount = 0
            self.totalBytes = 0

            self.lastMetricsAt =
                CFAbsoluteTimeGetCurrent()

            self.emitMetrics()
        }
    }

    func stop() {
        queue.async {
            [weak self] in

            guard let self else {
                return
            }

            self.running = false
            self.converter = nil
            self.inputFormat = nil
            self.outputFormat = nil

            self.pendingPCM.removeAll(
                keepingCapacity: false
            )

            self.nextPacketPTS = nil
            self.lastInputEndPTS = nil

            self.emitMetrics()
        }
    }

    func encode(
        sampleBuffer: CMSampleBuffer,
        muted: Bool
    ) {
        queue.async {
            [weak self] in

            guard
                let self,
                self.running
            else {
                return
            }

            self.encodeLocked(
                sampleBuffer:
                    sampleBuffer,
                muted:
                    muted
            )
        }
    }

    private func encodeLocked(
        sampleBuffer: CMSampleBuffer,
        muted: Bool
    ) {
        guard
            let formatDescription =
                CMSampleBufferGetFormatDescription(
                    sampleBuffer
                ),
            let asbd =
                CMAudioFormatDescriptionGetStreamBasicDescription(
                    formatDescription
                )?
                .pointee
        else {
            return
        }

        guard
            asbd.mFormatID ==
                kAudioFormatLinearPCM,
            asbd.mBitsPerChannel == 16,
            asbd.mChannelsPerFrame == 1,
            asbd.mBytesPerFrame == 2
        else {
            print(
                "[SportsOSCamera][AAC]",
                "unsupported PCM format",
                "rate=\(asbd.mSampleRate)",
                "channels=\(asbd.mChannelsPerFrame)",
                "bits=\(asbd.mBitsPerChannel)",
                "bytesPerFrame=\(asbd.mBytesPerFrame)"
            )

            return
        }

        let sampleRate =
            asbd.mSampleRate

        let channels =
            asbd.mChannelsPerFrame

        if
            converter == nil ||
            configuredSampleRate != sampleRate ||
            configuredChannels != channels
        {
            guard
                configureConverter(
                    sampleRate:
                        sampleRate,
                    channels:
                        channels
                )
            else {
                return
            }
        }

        let inputPTS =
            CMSampleBufferGetPresentationTimeStamp(
                sampleBuffer
            )

        let sampleCount =
            CMSampleBufferGetNumSamples(
                sampleBuffer
            )

        guard sampleCount > 0 else {
            return
        }

        if let lastInputEndPTS {
            let gap =
                CMTimeGetSeconds(
                    CMTimeSubtract(
                        inputPTS,
                        lastInputEndPTS
                    )
                )

            if
                gap.isFinite &&
                abs(gap) > 0.100
            {
                pendingPCM.removeAll(
                    keepingCapacity: true
                )

                converter?.reset()

                nextPacketPTS =
                    inputPTS
            }
        }

        if nextPacketPTS == nil {
            nextPacketPTS =
                inputPTS
        }

        lastInputEndPTS =
            CMTimeAdd(
                inputPTS,
                CMTime(
                    value:
                        CMTimeValue(
                            sampleCount
                        ),
                    timescale:
                        CMTimeScale(
                            sampleRate
                        )
                )
            )

        let byteCount =
            sampleCount * 2

        if muted {
            pendingPCM.append(
                Data(
                    repeating: 0,
                    count: byteCount
                )
            )
        } else {
            guard
                let blockBuffer =
                    CMSampleBufferGetDataBuffer(
                        sampleBuffer
                    )
            else {
                return
            }

            var source =
                Data(
                    count:
                        byteCount
                )

            let copyResult =
                source.withUnsafeMutableBytes {
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
                            dataLength:
                                byteCount,
                            destination:
                                base
                        )
                }

            guard
                copyResult ==
                    kCMBlockBufferNoErr
            else {
                return
            }

            pendingPCM.append(
                source
            )
        }

        let packetPCMBytes =
            samplesPerAACPacket * 2

        while
            pendingPCM.count >=
                packetPCMBytes
        {
            let pcmData =
                pendingPCM.prefix(
                    packetPCMBytes
                )

            pendingPCM.removeFirst(
                packetPCMBytes
            )

            encodePCMBlock(
                Data(pcmData)
            )
        }
    }

    private func configureConverter(
        sampleRate: Double,
        channels: UInt32
    ) -> Bool {
        guard
            let input =
                AVAudioFormat(
                    commonFormat:
                        .pcmFormatInt16,
                    sampleRate:
                        sampleRate,
                    channels:
                        AVAudioChannelCount(
                            channels
                        ),
                    interleaved:
                        true
                )
        else {
            return false
        }

        let outputSettings:
            [String: Any] = [
                AVFormatIDKey:
                    Int(
                        kAudioFormatMPEG4AAC
                    ),
                AVSampleRateKey:
                    sampleRate,
                AVNumberOfChannelsKey:
                    Int(channels),
                AVEncoderBitRateKey:
                    targetBitrate
            ]

        guard
            let output =
                AVAudioFormat(
                    settings:
                        outputSettings
                ),
            let converter =
                AVAudioConverter(
                    from:
                        input,
                    to:
                        output
                )
        else {
            print(
                "[SportsOSCamera][AAC]",
                "unable to create AAC converter"
            )

            return false
        }

        converter.bitRate =
            targetBitrate

        self.inputFormat =
            input

        self.outputFormat =
            output

        self.converter =
            converter

        configuredSampleRate =
            sampleRate

        configuredChannels =
            channels

        pendingPCM.removeAll(
            keepingCapacity: true
        )

        nextPacketPTS = nil
        lastInputEndPTS = nil

        print(
            "[SportsOSCamera][AAC]",
            "configured",
            "\(Int(sampleRate)) Hz",
            "\(channels) ch",
            "\(targetBitrate / 1000) kbps"
        )

        return true
    }

    private func encodePCMBlock(
        _ data: Data
    ) {
        guard
            let converter,
            let inputFormat,
            let outputFormat,
            let packetPTS =
                nextPacketPTS
        else {
            return
        }

        guard
            let pcmBuffer =
                AVAudioPCMBuffer(
                    pcmFormat:
                        inputFormat,
                    frameCapacity:
                        AVAudioFrameCount(
                            samplesPerAACPacket
                        )
                )
        else {
            return
        }

        pcmBuffer.frameLength =
            AVAudioFrameCount(
                samplesPerAACPacket
            )

        let audioBufferList =
            pcmBuffer
                .mutableAudioBufferList

        guard
            let destination =
                audioBufferList
                    .pointee
                    .mBuffers
                    .mData
        else {
            return
        }

        data.copyBytes(
            to:
                destination
                    .assumingMemoryBound(
                        to: UInt8.self
                    ),
            count:
                data.count
        )

        audioBufferList
            .pointee
            .mBuffers
            .mDataByteSize =
                UInt32(
                    data.count
                )

        let maximumPacketSize =
            max(
                converter
                    .maximumOutputPacketSize,
                1
            )

        let compressed =
            AVAudioCompressedBuffer(
                format:
                    outputFormat,
                packetCapacity:
                    1,
                maximumPacketSize:
                    maximumPacketSize
            )

        var suppliedInput =
            false

        var conversionError:
            NSError?

        let status =
            converter.convert(
                to:
                    compressed,
                error:
                    &conversionError
            ) {
                _, inputStatus in

                if suppliedInput {
                    inputStatus.pointee =
                        .noDataNow

                    return nil
                }

                suppliedInput = true

                inputStatus.pointee =
                    .haveData

                return pcmBuffer
            }

        if status == .error {
            print(
                "[SportsOSCamera][AAC]",
                "encode error:",
                conversionError?
                    .localizedDescription
                    ?? "unknown"
            )

            return
        }

        guard
            compressed.packetCount > 0,
            compressed.byteLength > 0
        else {
            return
        }

        let encodedData =
            Data(
                bytes:
                    compressed.data,
                count:
                    Int(
                        compressed.byteLength
                    )
            )

        let frame =
            EncodedAudioFrame(
                data:
                    encodedData,
                presentationTimeStamp:
                    packetPTS,
                sampleRate:
                    configuredSampleRate,
                channelCount:
                    configuredChannels,
                samplesPerPacket:
                    UInt32(
                        samplesPerAACPacket
                    )
            )

        packetCount += 1

        totalBytes +=
            Int64(
                encodedData.count
            )

        onEncodedFrame?(
            frame
        )

        nextPacketPTS =
            CMTimeAdd(
                packetPTS,
                CMTime(
                    value:
                        CMTimeValue(
                            samplesPerAACPacket
                        ),
                    timescale:
                        CMTimeScale(
                            configuredSampleRate
                        )
                )
            )

        let now =
            CFAbsoluteTimeGetCurrent()

        if
            now - lastMetricsAt >=
                0.5
        {
            lastMetricsAt = now
            emitMetrics()
        }
    }

    private func emitMetrics() {
        onMetrics?(
            AudioEncoderMetrics(
                packetCount:
                    packetCount,
                totalBytes:
                    totalBytes
            )
        )
    }
}
