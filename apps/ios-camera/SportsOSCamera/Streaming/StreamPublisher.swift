import Foundation

struct StreamPublisherMetrics: Sendable {
    let frameCount: Int64
    let keyFrameCount: Int64
    let totalBytes: Int64
}

protocol StreamPublisher: AnyObject {
    var onMetrics:
        (@Sendable (StreamPublisherMetrics) -> Void)?
        { get set }

    func start()
    func publish(_ frame: EncodedVideoFrame)
    func stop()
}

/*
 Debug transport used to prove the boundary between the
 H.264 encoder and a future network publisher.

 This publisher intentionally performs no network I/O.

 It accepts the same EncodedVideoFrame objects that will
 later be handed to SRT/RTMPS transport code and tracks
 exactly how many Annex-B frames and bytes crossed the
 publisher boundary.
*/
final class DebugStreamPublisher:
    StreamPublisher,
    @unchecked Sendable
{
    var onMetrics:
        (@Sendable (StreamPublisherMetrics) -> Void)?

    private let queue =
        DispatchQueue(
            label:
                "online.crashthenet.sportsoscamera.publisher.debug"
        )

    private var running = false

    private var frameCount: Int64 = 0
    private var keyFrameCount: Int64 = 0
    private var totalBytes: Int64 = 0

    private var lastMetricsAt =
        CFAbsoluteTimeGetCurrent()

    func start() {
        queue.async {
            [weak self] in

            guard let self else {
                return
            }

            self.running = true
            self.frameCount = 0
            self.keyFrameCount = 0
            self.totalBytes = 0
            self.lastMetricsAt =
                CFAbsoluteTimeGetCurrent()

            self.emitMetrics()
        }
    }

    func publish(
        _ frame: EncodedVideoFrame
    ) {
        queue.async {
            [weak self] in

            guard
                let self,
                self.running
            else {
                return
            }

            self.frameCount += 1

            if frame.isKeyFrame {
                self.keyFrameCount += 1
            }

            self.totalBytes +=
                Int64(frame.data.count)

            let now =
                CFAbsoluteTimeGetCurrent()

            /*
             UI telemetry does not need a callback for every
             60 fps video frame. Emit at most roughly twice
             per second while preserving exact internal
             counters.
            */
            if now - self.lastMetricsAt >= 0.5 {
                self.lastMetricsAt = now
                self.emitMetrics()
            }
        }
    }

    func stop() {
        queue.async {
            [weak self] in

            guard let self else {
                return
            }

            guard self.running else {
                return
            }

            self.running = false
            self.emitMetrics()
        }
    }

    private func emitMetrics() {
        let metrics =
            StreamPublisherMetrics(
                frameCount: frameCount,
                keyFrameCount: keyFrameCount,
                totalBytes: totalBytes
            )

        onMetrics?(metrics)
    }
}
