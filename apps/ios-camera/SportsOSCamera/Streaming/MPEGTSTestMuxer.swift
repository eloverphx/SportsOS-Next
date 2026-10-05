import CoreMedia
import Foundation

struct MPEGTSTestMuxerMetrics:
    @unchecked Sendable
{
    let running: Bool
    let packetCount: Int64
    let totalBytes: Int64
    let videoFrames: Int64
    let audioFrames: Int64
    let outputURL: URL?
}

/*
 Test-only MPEG-TS muxer.

 Produces:
   PAT       PID 0x0000
   PMT       PID 0x1000
   H.264     PID 0x0100 / stream type 0x1B
   AAC ADTS  PID 0x0101 / stream type 0x0F

 This class intentionally performs no network I/O.
*/
final class MPEGTSTestMuxer:
    @unchecked Sendable
{
    var onMetrics:
        (@Sendable (MPEGTSTestMuxerMetrics) -> Void)?

    /*
     Emits the exact MPEG-TS bytes that were written
     to the local validation file.

     This does not alter mux generation.
    */
    var onOutputData:
        (@Sendable (Data) -> Void)?

    private let queue =
        DispatchQueue(
            label:
                "online.crashthenet.sportsoscamera.mpegts"
        )

    private let patPID:
        UInt16 = 0x0000

    private let pmtPID:
        UInt16 = 0x1000

    private let videoPID:
        UInt16 = 0x0100

    private let audioPID:
        UInt16 = 0x0101

    private var continuity:
        [UInt16: UInt8] = [:]

    private var fileHandle:
        FileHandle?

    private var outputURL:
        URL?

    private var running =
        false

    private var generation:
        UInt64 = 0

    private var packetCount:
        Int64 = 0

    private var totalBytes:
        Int64 = 0

    private var videoFrames:
        Int64 = 0

    private var audioFrames:
        Int64 = 0

    private var lastTablesPTS:
        Int64?

    private var lastMetricsAt =
        CFAbsoluteTimeGetCurrent()

    func start(
        durationSeconds:
            TimeInterval = 15
    ) {
        queue.async {
            [weak self] in

            guard let self else {
                return
            }

            self.stopLocked(
                emit:
                    false
            )

            self.generation &+= 1

            let thisGeneration =
                self.generation

            self.continuity.removeAll()
            self.packetCount = 0
            self.totalBytes = 0
            self.videoFrames = 0
            self.audioFrames = 0
            self.lastTablesPTS = nil

            let directory =
                FileManager
                    .default
                    .temporaryDirectory

            let formatter =
                DateFormatter()

            formatter.dateFormat =
                "yyyyMMdd-HHmmss"

            let filename =
                "sportsos-m41-mux-" +
                formatter.string(
                    from: Date()
                ) +
                ".ts"

            let url =
                directory
                    .appendingPathComponent(
                        filename
                    )

            try? FileManager
                .default
                .removeItem(
                    at: url
                )

            guard
                FileManager
                    .default
                    .createFile(
                        atPath:
                            url.path,
                        contents:
                            nil
                    ),
                let handle =
                    try? FileHandle(
                        forWritingTo:
                            url
                    )
            else {
                print(
                    "[SportsOSCamera][MPEGTS]",
                    "unable to create test file"
                )

                self.emitMetrics()
                return
            }

            self.outputURL =
                url

            self.fileHandle =
                handle

            self.running =
                true

            self.lastMetricsAt =
                CFAbsoluteTimeGetCurrent()

            self.writeTables()
            self.emitMetrics()

            print(
                "[SportsOSCamera][MPEGTS]",
                "started",
                url.path
            )

            self.queue.asyncAfter(
                deadline:
                    .now() +
                    durationSeconds
            ) {
                [weak self] in

                guard
                    let self,
                    self.running,
                    self.generation ==
                        thisGeneration
                else {
                    return
                }

                self.stopLocked(
                    emit:
                        true
                )
            }
        }
    }

    func stop() {
        queue.async {
            [weak self] in

            self?.stopLocked(
                emit:
                    true
            )
        }
    }

    func appendVideo(
        _ frame:
            EncodedVideoFrame
    ) {
        queue.async {
            [weak self] in

            guard
                let self,
                self.running
            else {
                return
            }

            let pts =
                self.pts90k(
                    frame
                        .presentationTimeStamp
                )

            if self.shouldWriteTables(
                at:
                    pts,
                force:
                    frame.isKeyFrame
            ) {
                self.writeTables()
                self.lastTablesPTS =
                    pts
            }

            let pes =
                self.makePES(
                    streamID:
                        0xE0,
                    payload:
                        frame.data,
                    pts:
                        pts,
                    video:
                        true
                )

            let packets =
                self.packetizePES(
                    pes,
                    pid:
                        self.videoPID,
                    pcr:
                        pts
                )

            self.write(
                packets
            )

            self.videoFrames += 1

            self.maybeEmitMetrics()
        }
    }

    func appendAudio(
        _ frame:
            EncodedAudioFrame
    ) {
        queue.async {
            [weak self] in

            guard
                let self,
                self.running
            else {
                return
            }

            guard
                let adts =
                    self.makeADTSFrame(
                        frame
                    )
            else {
                return
            }

            let pts =
                self.pts90k(
                    frame
                        .presentationTimeStamp
                )

            let pes =
                self.makePES(
                    streamID:
                        0xC0,
                    payload:
                        adts,
                    pts:
                        pts,
                    video:
                        false
                )

            let packets =
                self.packetizePES(
                    pes,
                    pid:
                        self.audioPID,
                    pcr:
                        nil
                )

            self.write(
                packets
            )

            self.audioFrames += 1

            self.maybeEmitMetrics()
        }
    }

    private func stopLocked(
        emit: Bool
    ) {
        guard
            running ||
            fileHandle != nil
        else {
            if emit {
                emitMetrics()
            }

            return
        }

        running = false

        if let fileHandle {
            fileHandle
                .synchronizeFile()

            fileHandle
                .closeFile()
        }

        self.fileHandle =
            nil

        if let outputURL {
            print(
                "[SportsOSCamera][MPEGTS]",
                "finalized",
                outputURL.path,
                "packets=\(packetCount)",
                "bytes=\(totalBytes)"
            )
        }

        if emit {
            emitMetrics()
        }
    }

    private func shouldWriteTables(
        at pts:
            Int64,
        force: Bool
    ) -> Bool {
        guard
            let last =
                lastTablesPTS
        else {
            return true
        }

        let elapsed =
            pts - last

        if elapsed >= 45_000 {
            return true
        }

        return
            force &&
            elapsed >= 9_000
    }

    private func writeTables() {
        write(
            makePSIPacket(
                pid:
                    patPID,
                section:
                    makePAT()
            )
        )

        write(
            makePSIPacket(
                pid:
                    pmtPID,
                section:
                    makePMT()
            )
        )
    }

    private func makePAT()
        -> Data
    {
        var section =
            Data()

        section.append(
            0x00
        )

        let sectionLength =
            13

        section.append(
            0xB0 |
            UInt8(
                (
                    sectionLength >>
                    8
                ) &
                0x0F
            )
        )

        section.append(
            UInt8(
                sectionLength &
                0xFF
            )
        )

        section.append(
            contentsOf: [
                0x00, 0x01,
                0xC1,
                0x00,
                0x00,
                0x00, 0x01,
                UInt8(
                    0xE0 |
                    (
                        pmtPID >>
                        8
                    )
                ),
                UInt8(
                    pmtPID &
                    0x00FF
                )
            ]
        )

        appendCRC(
            to:
                &section
        )

        return section
    }

    private func makePMT()
        -> Data
    {
        var section =
            Data()

        section.append(
            0x02
        )

        let sectionLength =
            23

        section.append(
            0xB0 |
            UInt8(
                (
                    sectionLength >>
                    8
                ) &
                0x0F
            )
        )

        section.append(
            UInt8(
                sectionLength &
                0xFF
            )
        )

        section.append(
            contentsOf: [
                0x00, 0x01,
                0xC1,
                0x00,
                0x00,

                UInt8(
                    0xE0 |
                    (
                        videoPID >>
                        8
                    )
                ),
                UInt8(
                    videoPID &
                    0x00FF
                ),

                0xF0,
                0x00,

                0x1B,
                UInt8(
                    0xE0 |
                    (
                        videoPID >>
                        8
                    )
                ),
                UInt8(
                    videoPID &
                    0x00FF
                ),
                0xF0,
                0x00,

                0x0F,
                UInt8(
                    0xE0 |
                    (
                        audioPID >>
                        8
                    )
                ),
                UInt8(
                    audioPID &
                    0x00FF
                ),
                0xF0,
                0x00
            ]
        )

        appendCRC(
            to:
                &section
        )

        return section
    }

    private func appendCRC(
        to data:
            inout Data
    ) {
        var crc:
            UInt32 = 0xFFFF_FFFF

        for byte in data {
            crc ^=
                UInt32(byte) << 24

            for _ in 0..<8 {
                if
                    crc &
                    0x8000_0000 != 0
                {
                    crc =
                        (
                            crc << 1
                        ) ^
                        0x04C1_1DB7
                } else {
                    crc <<= 1
                }
            }
        }

        data.append(
            UInt8(
                (
                    crc >>
                    24
                ) &
                0xFF
            )
        )

        data.append(
            UInt8(
                (
                    crc >>
                    16
                ) &
                0xFF
            )
        )

        data.append(
            UInt8(
                (
                    crc >>
                    8
                ) &
                0xFF
            )
        )

        data.append(
            UInt8(
                crc &
                0xFF
            )
        )
    }

    private func makePSIPacket(
        pid: UInt16,
        section: Data
    ) -> Data {
        var packet =
            Data(
                repeating:
                    0xFF,
                count:
                    188
            )

        packet[0] =
            0x47

        packet[1] =
            0x40 |
            UInt8(
                (
                    pid >>
                    8
                ) &
                0x1F
            )

        packet[2] =
            UInt8(
                pid &
                0xFF
            )

        packet[3] =
            0x10 |
            nextContinuity(
                for:
                    pid
            )

        packet[4] =
            0x00

        let sectionStart =
            5

        packet.replaceSubrange(
            sectionStart ..<
                sectionStart +
                section.count,
            with:
                section
        )

        return packet
    }

    private func makePES(
        streamID: UInt8,
        payload: Data,
        pts: Int64,
        video: Bool
    ) -> Data {
        var pes =
            Data()

        pes.append(
            contentsOf: [
                0x00,
                0x00,
                0x01,
                streamID
            ]
        )

        if video {
            pes.append(
                contentsOf: [
                    0x00,
                    0x00
                ]
            )
        } else {
            let length =
                min(
                    payload.count + 8,
                    0xFFFF
                )

            pes.append(
                UInt8(
                    (
                        length >>
                        8
                    ) &
                    0xFF
                )
            )

            pes.append(
                UInt8(
                    length &
                    0xFF
                )
            )
        }

        pes.append(
            contentsOf: [
                0x80,
                0x80,
                0x05
            ]
        )

        pes.append(
            contentsOf:
                encodePTS(
                    pts
                )
        )

        pes.append(
            payload
        )

        return pes
    }

    private func encodePTS(
        _ value:
            Int64
    ) -> [UInt8] {
        let pts =
            UInt64(
                value
            ) &
            0x1_FFFF_FFFF

        return [
            UInt8(
                0x20 |
                (
                    (
                        pts >>
                        29
                    ) &
                    0x0E
                ) |
                0x01
            ),

            UInt8(
                (
                    pts >>
                    22
                ) &
                0xFF
            ),

            UInt8(
                (
                    (
                        pts >>
                        14
                    ) &
                    0xFE
                ) |
                0x01
            ),

            UInt8(
                (
                    pts >>
                    7
                ) &
                0xFF
            ),

            UInt8(
                (
                    (
                        pts <<
                        1
                    ) &
                    0xFE
                ) |
                0x01
            )
        ]
    }

    private func packetizePES(
        _ pes: Data,
        pid: UInt16,
        pcr: Int64?
    ) -> Data {
        var output =
            Data()

        var offset =
            0

        var first =
            true

        while offset < pes.count {
            let needsPCR =
                first &&
                pcr != nil

            let maximumPayload =
                needsPCR
                ? 176
                : 184

            let remaining =
                pes.count -
                offset

            let payloadCount =
                min(
                    remaining,
                    maximumPayload
                )

            var packet =
                Data(
                    repeating:
                        0xFF,
                    count:
                        188
                )

            packet[0] =
                0x47

            packet[1] =
                (
                    first
                    ? 0x40
                    : 0x00
                ) |
                UInt8(
                    (
                        pid >>
                        8
                    ) &
                    0x1F
                )

            packet[2] =
                UInt8(
                    pid &
                    0xFF
                )

            let adaptationTotal =
                184 -
                payloadCount

            let needsAdaptation =
                adaptationTotal > 0

            let adaptationControl:
                UInt8 =
                    needsAdaptation
                    ? 0x30
                    : 0x10

            packet[3] =
                adaptationControl |
                nextContinuity(
                    for:
                        pid
                )

            var payloadOffset =
                4

            if needsAdaptation {
                let adaptationLength =
                    adaptationTotal -
                    1

                packet[payloadOffset] =
                    UInt8(
                        adaptationLength
                    )

                payloadOffset += 1

                if adaptationLength > 0 {
                    if
                        needsPCR,
                        let pcr
                    {
                        packet[payloadOffset] =
                            0x10

                        payloadOffset += 1

                        let pcrBytes =
                            encodePCR(
                                pcr
                            )

                        packet.replaceSubrange(
                            payloadOffset ..<
                                payloadOffset +
                                pcrBytes.count,
                            with:
                                pcrBytes
                        )

                        payloadOffset +=
                            pcrBytes.count

                    } else {
                        packet[payloadOffset] =
                            0x00

                        payloadOffset += 1
                    }

                    let adaptationEnd =
                        4 +
                        adaptationTotal

                    while
                        payloadOffset <
                        adaptationEnd
                    {
                        packet[payloadOffset] =
                            0xFF

                        payloadOffset += 1
                    }
                }
            }

            packet.replaceSubrange(
                payloadOffset ..<
                    payloadOffset +
                    payloadCount,
                with:
                    pes[
                        offset ..<
                        offset +
                        payloadCount
                    ]
            )

            output.append(
                packet
            )

            offset +=
                payloadCount

            first =
                false
        }

        return output
    }

    private func encodePCR(
        _ value:
            Int64
    ) -> Data {
        let base =
            UInt64(
                value
            ) &
            0x1_FFFF_FFFF

        return Data(
            [
                UInt8(
                    (
                        base >>
                        25
                    ) &
                    0xFF
                ),

                UInt8(
                    (
                        base >>
                        17
                    ) &
                    0xFF
                ),

                UInt8(
                    (
                        base >>
                        9
                    ) &
                    0xFF
                ),

                UInt8(
                    (
                        base >>
                        1
                    ) &
                    0xFF
                ),

                UInt8(
                    (
                        (
                            base &
                            0x01
                        ) <<
                        7
                    ) |
                    0x7E
                ),

                0x00
            ]
        )
    }

    private func makeADTSFrame(
        _ frame:
            EncodedAudioFrame
    ) -> Data? {
        guard
            Int(
                frame.sampleRate
            ) ==
                48_000,
            frame.channelCount ==
                1
        else {
            print(
                "[SportsOSCamera][MPEGTS]",
                "unsupported AAC format",
                "\(frame.sampleRate) Hz",
                "\(frame.channelCount) ch"
            )

            return nil
        }

        let profile =
            1

        let frequencyIndex =
            3

        let channelConfiguration =
            Int(
                frame.channelCount
            )

        let frameLength =
            frame.data.count +
            7

        guard frameLength < 8192 else {
            return nil
        }

        var adts =
            Data()

        adts.append(
            0xFF
        )

        adts.append(
            0xF1
        )

        adts.append(
            UInt8(
                (
                    profile <<
                    6
                ) |
                (
                    frequencyIndex <<
                    2
                ) |
                (
                    channelConfiguration >>
                    2
                )
            )
        )

        adts.append(
            UInt8(
                (
                    (
                        channelConfiguration &
                        0x03
                    ) <<
                    6
                ) |
                (
                    frameLength >>
                    11
                )
            )
        )

        adts.append(
            UInt8(
                (
                    frameLength >>
                    3
                ) &
                0xFF
            )
        )

        adts.append(
            UInt8(
                (
                    (
                        frameLength &
                        0x07
                    ) <<
                    5
                ) |
                0x1F
            )
        )

        adts.append(
            0xFC
        )

        adts.append(
            frame.data
        )

        return adts
    }

    private func pts90k(
        _ time:
            CMTime
    ) -> Int64 {
        guard
            time.isValid,
            time.isNumeric,
            time.timescale > 0
        else {
            return 0
        }

        let converted =
            CMTimeConvertScale(
                time,
                timescale:
                    90_000,
                method:
                    .default
            )

        let modulus:
            Int64 =
                1 << 33

        var value =
            converted.value %
            modulus

        if value < 0 {
            value +=
                modulus
        }

        return value
    }

    private func nextContinuity(
        for pid:
            UInt16
    ) -> UInt8 {
        let current =
            continuity[pid]
            ?? 0

        continuity[pid] =
            (
                current +
                1
            ) &
            0x0F

        return current
    }

    private func write(
        _ data:
            Data
    ) {
        guard
            running,
            let fileHandle,
            !data.isEmpty
        else {
            return
        }

        fileHandle.write(
            data
        )

        onOutputData?(
            data
        )

        let packets =
            data.count /
            188

        packetCount +=
            Int64(
                packets
            )

        totalBytes +=
            Int64(
                data.count
            )
    }

    private func maybeEmitMetrics() {
        let now =
            CFAbsoluteTimeGetCurrent()

        if
            now -
            lastMetricsAt >=
                0.5
        {
            lastMetricsAt =
                now

            emitMetrics()
        }
    }

    private func emitMetrics() {
        onMetrics?(
            MPEGTSTestMuxerMetrics(
                running:
                    running,
                packetCount:
                    packetCount,
                totalBytes:
                    totalBytes,
                videoFrames:
                    videoFrames,
                audioFrames:
                    audioFrames,
                outputURL:
                    outputURL
            )
        )
    }
}
