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
        port: UInt16
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
                self.droppedBytes +=
                    Int64(
                        data.count
                    )

                self.emitMetrics()
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

    func disconnect() {
        queue.async {
            [weak self] in

            guard let self else {
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

            self.disconnectLocked(
                preserveMetrics:
                    true
            )

            self.emitMetrics()
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
