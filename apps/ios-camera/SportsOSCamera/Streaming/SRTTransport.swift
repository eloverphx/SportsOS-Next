import Darwin
import Foundation

struct SRTTransportMetrics:
    @unchecked Sendable
{
    let connected: Bool
    let sentBytes: Int64
    let sendCalls: Int64
    let droppedBytes: Int64
    let bufferedBytes: Int
    let lastError: String?
}

final class SRTTransport:
    @unchecked Sendable
{
    var onMetrics:
        (@Sendable (SRTTransportMetrics) -> Void)?

    private let queue =
        DispatchQueue(
            label:
                "online.crashthenet.sportsoscamera.srt"
        )

    private let sendChunkSize =
        7 * 188

    /*
     Keep this bounded.

     This is only a safety buffer for TS fragments,
     not a reconnect/archive queue.
    */
    private let maximumBufferedBytes =
        256 * 1024

    private var socket:
        SRTSOCKET =
            SRT_INVALID_SOCK

    private var started =
        false

    private var connected =
        false

    private var pending =
        Data()

    private var sentBytes:
        Int64 = 0

    private var sendCalls:
        Int64 = 0

    private var droppedBytes:
        Int64 = 0

    private var lastError:
        String?

    func connect(
        host: String,
        port: UInt16,
        streamId: String,
        latencyMs: Int
    ) {
        queue.async {
            [weak self] in

            guard let self else {
                return
            }

            self.disconnectLocked(
                preserveMetrics:
                    false
            )

            self.sentBytes = 0
            self.sendCalls = 0
            self.droppedBytes = 0
            self.pending.removeAll(
                keepingCapacity:
                    true
            )

            self.lastError = nil

            let startup =
                srt_startup()

            guard startup == 0 else {
                self.lastError =
                    "srt_startup failed"

                self.emitMetrics()
                return
            }

            self.started = true

            let socket =
                srt_create_socket()

            guard
                socket !=
                    SRT_INVALID_SOCK
            else {
                self.lastError =
                    self.currentSRTError()

                self.disconnectLocked(
                    preserveMetrics:
                        true
                )

                self.emitMetrics()
                return
            }

            self.socket =
                socket

            /*
             Apply the server-issued session identity before connect.

             The listener can use this opaque stream ID to associate
             the caller with the intended SportsOS game/session.
            */
            let streamIdResult =
                streamId.withCString {
                    pointer in

                    srt_setsockflag(
                        socket,
                        SRTO_STREAMID,
                        pointer,
                        Int32(
                            streamId.utf8.count
                        )
                    )
                }

            guard streamIdResult == 0 else {
                self.lastError =
                    self.currentSRTError()

                print(
                    "[SportsOSCamera][SRT]",
                    "stream ID configuration failed:",
                    self.lastError ??
                        "unknown"
                )

                self.disconnectLocked(
                    preserveMetrics:
                        true
                )

                self.emitMetrics()
                return
            }

            var configuredLatency =
                Int32(
                    max(
                        latencyMs,
                        0
                    )
                )

            let latencyResult =
                withUnsafePointer(
                    to:
                        &configuredLatency
                ) {
                    pointer in

                    srt_setsockflag(
                        socket,
                        SRTO_LATENCY,
                        pointer,
                        Int32(
                            MemoryLayout<Int32>.size
                        )
                    )
                }

            guard latencyResult == 0 else {
                self.lastError =
                    self.currentSRTError()

                print(
                    "[SportsOSCamera][SRT]",
                    "latency configuration failed:",
                    self.lastError ??
                        "unknown"
                )

                self.disconnectLocked(
                    preserveMetrics:
                        true
                )

                self.emitMetrics()
                return
            }

            var address =
                sockaddr_in()

            address.sin_family =
                sa_family_t(
                    AF_INET
                )

            address.sin_port =
                port.bigEndian

            let converted =
                host.withCString {
                    hostPointer in

                    inet_pton(
                        AF_INET,
                        hostPointer,
                        &address.sin_addr
                    )
                }

            guard converted == 1 else {
                self.lastError =
                    "Invalid IPv4 address"

                self.disconnectLocked(
                    preserveMetrics:
                        true
                )

                self.emitMetrics()
                return
            }

            print(
                "[SportsOSCamera][SRT]",
                "connecting",
                "\(host):\(port)"
            )

            let result =
                withUnsafePointer(
                    to:
                        &address
                ) {
                    addressPointer in

                    addressPointer
                        .withMemoryRebound(
                            to:
                                sockaddr.self,
                            capacity:
                                1
                        ) {
                            sockaddrPointer in

                            srt_connect(
                                socket,
                                sockaddrPointer,
                                Int32(
                                    MemoryLayout<
                                        sockaddr_in
                                    >.size
                                )
                            )
                        }
                }

            guard result == 0 else {
                self.lastError =
                    self.currentSRTError()

                print(
                    "[SportsOSCamera][SRT]",
                    "connect failed:",
                    self.lastError ??
                        "unknown"
                )

                self.disconnectLocked(
                    preserveMetrics:
                        true
                )

                self.emitMetrics()
                return
            }

            self.connected =
                true

            print(
                "[SportsOSCamera][SRT]",
                "CONNECTED"
            )

            self.emitMetrics()
        }
    }

    /*
     Accept arbitrary MPEG-TS output boundaries.

     MPEGTSTestMuxer may hand us:
       188 bytes
       several TS packets
       an entire packetized PES

     We normalize those boundaries into 1316-byte
     SRT writes: exactly seven 188-byte TS packets.
    */
    func sendMPEGTS(
        _ data: Data
    ) {
        guard !data.isEmpty else {
            return
        }

        queue.async {
            [weak self] in

            guard let self else {
                return
            }

            guard self.connected else {
                /*
                 No remote backlog while disconnected.

                 Local recording continues, but remote MPEG-TS bytes
                 are deliberately discarded until SRT recovers.
                */
                self.droppedBytes +=
                    Int64(
                        data.count
                    )

                return
            }

            self.pending.append(
                data
            )

            if
                self.pending.count >
                    self.maximumBufferedBytes
            {
                let overflow =
                    self.pending.count -
                    self.maximumBufferedBytes

                self.pending.removeFirst(
                    overflow
                )

                self.droppedBytes +=
                    Int64(
                        overflow
                    )

                print(
                    "[SportsOSCamera][SRT]",
                    "buffer overflow",
                    "dropped=\(overflow)"
                )
            }

            while
                self.pending.count >=
                    self.sendChunkSize
            {
                let chunk =
                    self.pending.prefix(
                        self.sendChunkSize
                    )

                let sent =
                    chunk.withUnsafeBytes {
                        rawBuffer ->
                        Int32 in

                        guard
                            let base =
                                rawBuffer.baseAddress
                        else {
                            return Int32(
                                SRT_ERROR
                            )
                        }

                        return srt_send(
                            self.socket,
                            base.assumingMemoryBound(
                                to:
                                    CChar.self
                            ),
                            Int32(
                                self.sendChunkSize
                            )
                        )
                    }

                if sent == SRT_ERROR {
                    self.lastError =
                        self.currentSRTError()

                    print(
                        "[SportsOSCamera][SRT]",
                        "send failed:",
                        self.lastError ??
                            "unknown"
                    )

                    /*
                     The established ingest path is no longer usable.

                     Preserve transport metrics, but transition the
                     socket to disconnected immediately so CAMERA READY
                     cannot remain true after a real send failure.
                    */
                    self.disconnectLocked(
                        preserveMetrics:
                            true
                    )

                    self.emitMetrics()
                    return
                }

                guard
                    sent ==
                        self.sendChunkSize
                else {
                    self.lastError =
                        "short SRT send \(sent)/\(self.sendChunkSize)"

                    print(
                        "[SportsOSCamera][SRT]",
                        self.lastError ??
                            "short send"
                    )

                    self.disconnectLocked(
                        preserveMetrics:
                            true
                    )

                    self.emitMetrics()
                    return
                }

                self.pending.removeFirst(
                    self.sendChunkSize
                )

                self.sentBytes +=
                    Int64(
                        sent
                    )

                self.sendCalls += 1

                if
                    self.sendCalls %
                        50 ==
                        0
                {
                    self.emitMetrics()
                }
            }
        }
    }

    func disconnect(
        completion: (() -> Void)? = nil
    ) {
        queue.async {
            [weak self] in

            guard let self else {
                completion?()
                return
            }

            /*
             Normal sends use 1316-byte groups
             (7 MPEG-TS packets).

             At shutdown, however, preserve any
             remaining complete 188-byte TS packets.
             SRT does not require every final payload
             to contain exactly seven TS packets.
            */
            if
                self.connected,
                self.socket !=
                    SRT_INVALID_SOCK
            {
                let completeBytes =
                    (
                        self.pending.count /
                        188
                    ) *
                    188

                if completeBytes > 0 {
                    let finalChunk =
                        self.pending.prefix(
                            completeBytes
                        )

                    let sent =
                        finalChunk.withUnsafeBytes {
                            rawBuffer ->
                            Int32 in

                            guard
                                let base =
                                    rawBuffer.baseAddress
                            else {
                                return Int32(
                                    SRT_ERROR
                                )
                            }

                            return srt_send(
                                self.socket,
                                base.assumingMemoryBound(
                                    to:
                                        CChar.self
                                ),
                                Int32(
                                    completeBytes
                                )
                            )
                        }

                    if sent == SRT_ERROR {
                        self.lastError =
                            self.currentSRTError()

                        self.droppedBytes +=
                            Int64(
                                completeBytes
                            )
                    } else {
                        self.sentBytes +=
                            Int64(
                                sent
                            )

                        self.sendCalls += 1

                        self.pending.removeFirst(
                            Int(
                                sent
                            )
                        )
                    }
                }
            }

            if !self.pending.isEmpty {
                self.droppedBytes +=
                    Int64(
                        self.pending.count
                    )

                self.pending.removeAll(
                    keepingCapacity:
                        true
                )
            }

            /*
             srt_send() returning successfully means the payload was
             accepted by the local SRT socket. It does not guarantee
             that the remote receiver has consumed the final packets.

             Keep the connected socket alive briefly after the last
             send so SRT can transmit and acknowledge the stream tail
             before close.
            */
            let drainDelay:
                DispatchTimeInterval =
                    .milliseconds(
                        750
                    )

            print(
                "[SportsOSCamera][SRT]",
                "draining before close",
                "pending=\(self.pending.count)"
            )

            self.queue.asyncAfter(
                deadline:
                    .now() +
                    drainDelay
            ) {
                [weak self] in

                guard let self else {
                    completion?()
                    return
                }

                self.disconnectLocked(
                    preserveMetrics:
                        true
                )

                self.emitMetrics()
                completion?()
            }
        }
    }

    private func disconnectLocked(
        preserveMetrics: Bool
    ) {
        if
            socket !=
                SRT_INVALID_SOCK
        {
            _ = srt_close(
                socket
            )

            socket =
                SRT_INVALID_SOCK
        }

        if connected {
            print(
                "[SportsOSCamera][SRT]",
                "DISCONNECTED"
            )
        }

        connected =
            false

        if started {
            _ = srt_cleanup()
            started = false
        }

        pending.removeAll(
            keepingCapacity:
                true
        )

        if !preserveMetrics {
            sentBytes = 0
            sendCalls = 0
            droppedBytes = 0
            lastError = nil
        }
    }

    private func currentSRTError()
        -> String
    {
        guard
            let pointer =
                srt_getlasterror_str()
        else {
            return
                "Unknown SRT error"
        }

        return String(
            cString:
                pointer
        )
    }

    private func emitMetrics() {
        onMetrics?(
            SRTTransportMetrics(
                connected:
                    connected,
                sentBytes:
                    sentBytes,
                sendCalls:
                    sendCalls,
                droppedBytes:
                    droppedBytes,
                bufferedBytes:
                    pending.count,
                lastError:
                    lastError
            )
        )
    }
}
