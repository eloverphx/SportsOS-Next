import Foundation
import Network
import Combine

@MainActor
final class NetworkQualityMonitor: ObservableObject {
    enum ConnectionType: String {
        case wifi = "Wi-Fi"
        case cellular = "Cellular"
        case wired = "Ethernet"
        case other = "Network"
        case offline = "Offline"
    }

    enum Quality: String {
        case offline = "OFFLINE"
        case poor = "POOR"
        case limited = "LIMITED"
        case good = "GOOD"
        case excellent = "EXCELLENT"
        case testing = "TESTING"
    }

    enum StreamProfile: String, CaseIterable {
        case full1080p60 = "1080p60"
        case reduced1080p60 = "1080p60 · LOW"
        case hd720p60 = "720p60"
        case hd720p30 = "720p30"
        case sd540p30 = "540p30"

        var targetBitrateMbps: Double {
            switch self {
            case .full1080p60:
                return 8.0

            case .reduced1080p60:
                return 5.0

            case .hd720p60:
                return 3.5

            case .hd720p30:
                return 2.0

            case .sd540p30:
                return 1.2
            }
        }
    }

    enum TestState {
        case idle
        case testing
        case complete
        case failed
    }

    @Published private(set) var connected = false
    @Published private(set) var connectionType: ConnectionType = .offline
    @Published private(set) var quality: Quality = .offline

    @Published private(set) var isExpensive = false
    @Published private(set) var isConstrained = false

    @Published private(set) var measuredUploadMbps: Double?
    @Published private(set) var latencyMilliseconds: Double?

    @Published private(set) var recommendedProfile: StreamProfile = .hd720p30

    @Published private(set) var testState: TestState = .idle
    @Published private(set) var lastTestError: String?

    private let monitor = NWPathMonitor()

    private let monitorQueue = DispatchQueue(
        label: "online.crashthenet.sportsoscamera.network"
    )

    private var monitoring = false

    private let pingURL = URL(
        string: "https://api.crashthenet.online/streaming/network-test/ping"
    )!

    private let uploadURL = URL(
        string: "https://api.crashthenet.online/streaming/network-test/upload"
    )!

    func start() {
        guard !monitoring else {
            return
        }

        monitoring = true

        monitor.pathUpdateHandler = { [weak self] path in
            let isConnected = path.status == .satisfied
            let expensive = path.isExpensive
            let constrained = path.isConstrained

            let type: ConnectionType

            if !isConnected {
                type = .offline
            } else if path.usesInterfaceType(.wifi) {
                type = .wifi
            } else if path.usesInterfaceType(.cellular) {
                type = .cellular
            } else if path.usesInterfaceType(.wiredEthernet) {
                type = .wired
            } else {
                type = .other
            }

            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                self.connected = isConnected
                self.connectionType = type
                self.isExpensive = expensive
                self.isConstrained = constrained

                if !isConnected {
                    self.quality = .offline
                    self.measuredUploadMbps = nil
                    self.latencyMilliseconds = nil
                    self.testState = .idle
                }
            }
        }

        monitor.start(queue: monitorQueue)
    }

    func stop() {
        guard monitoring else {
            return
        }

        monitor.cancel()
        monitoring = false
    }

    func runSportsOSNetworkTest() async -> Bool {
        guard connected else {
            quality = .offline
            testState = .failed
            lastTestError = "No network connection"
            return false
        }

        testState = .testing
        quality = .testing
        lastTestError = nil

        do {
            let latency = try await measureLatency()
            let upload = try await measureUploadSpeed()

            latencyMilliseconds = latency
            measuredUploadMbps = upload

            chooseProfile(
                uploadMbps: upload,
                latencyMs: latency
            )

            testState = .complete

            return true
        } catch {
            testState = .failed
            quality = connected ? .poor : .offline

            lastTestError = error.localizedDescription

            recommendedProfile = .sd540p30

            return false
        }
    }

    private func measureLatency() async throws -> Double {
        var measurements: [Double] = []

        for _ in 0..<3 {
            var request = URLRequest(url: pingURL)

            request.httpMethod = "GET"
            request.timeoutInterval = 8
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.setValue(
                "no-cache",
                forHTTPHeaderField: "Cache-Control"
            )

            let started = CFAbsoluteTimeGetCurrent()

            let (_, response) = try await URLSession.shared.data(
                for: request
            )

            let elapsed = (
                CFAbsoluteTimeGetCurrent() - started
            ) * 1000.0

            guard
                let http = response as? HTTPURLResponse,
                http.statusCode == 200
            else {
                throw NetworkTestError.invalidResponse
            }

            measurements.append(elapsed)
        }

        let sorted = measurements.sorted()

        return sorted[sorted.count / 2]
    }

    private func measureUploadSpeed() async throws -> Double {
        /*
         1 MiB gives a more useful measurement than a very tiny request,
         while staying within the SportsOS API test limit.
        */

        let payloadSize = 1024 * 1024

        let payload = Data(
            repeating: 65,
            count: payloadSize
        )

        var measurements: [Double] = []

        /*
         Run twice and use the slower result.

         For live sports we would rather underestimate available bandwidth
         than choose a profile the connection cannot sustain.
        */

        for _ in 0..<2 {
            var request = URLRequest(url: uploadURL)

            request.httpMethod = "POST"
            request.timeoutInterval = 15

            request.setValue(
                "text/plain",
                forHTTPHeaderField: "Content-Type"
            )

            request.setValue(
                "no-cache",
                forHTTPHeaderField: "Cache-Control"
            )

            let started = CFAbsoluteTimeGetCurrent()

            let (_, response) = try await URLSession.shared.upload(
                for: request,
                from: payload
            )

            let elapsed = CFAbsoluteTimeGetCurrent() - started

            guard
                let http = response as? HTTPURLResponse,
                http.statusCode == 200
            else {
                throw NetworkTestError.invalidResponse
            }

            guard elapsed > 0 else {
                throw NetworkTestError.invalidMeasurement
            }

            let bits = Double(payloadSize) * 8.0

            let megabitsPerSecond =
                bits / elapsed / 1_000_000.0

            measurements.append(megabitsPerSecond)
        }

        guard let conservativeResult = measurements.min() else {
            throw NetworkTestError.invalidMeasurement
        }

        return conservativeResult
    }

    private func chooseProfile(
        uploadMbps: Double,
        latencyMs: Double
    ) {
        /*
         These thresholds intentionally leave substantial upload headroom.

         We are optimizing for uninterrupted hockey video rather than
         consuming every available bit of bandwidth.
        */

        if uploadMbps >= 14 && latencyMs <= 100 {
            recommendedProfile = .full1080p60
            quality = .excellent
            return
        }

        if uploadMbps >= 9 && latencyMs <= 150 {
            recommendedProfile = .reduced1080p60
            quality = .good
            return
        }

        if uploadMbps >= 6 && latencyMs <= 200 {
            recommendedProfile = .hd720p60
            quality = .good
            return
        }

        if uploadMbps >= 3 {
            recommendedProfile = .hd720p30
            quality = .limited
            return
        }

        recommendedProfile = .sd540p30
        quality = .poor
    }
}

private enum NetworkTestError: LocalizedError {
    case invalidResponse
    case invalidMeasurement

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "SportsOS network test returned an invalid response"

        case .invalidMeasurement:
            return "SportsOS could not measure network performance"
        }
    }
}
