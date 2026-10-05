import AVFoundation
import SwiftUI
import UIKit

@MainActor
struct CameraScreen: View {

    enum CameraRunState {
        case idle
        case connecting
        case ready
    }

    @StateObject private var camera =
        CameraController()

    @StateObject private var network =
        NetworkQualityMonitor()

    @Environment(\.scenePhase)
    private var scenePhase

    @State private var cameraRunState:
        CameraRunState = .idle

    @State private var encoderNeedsInterruptionRecovery =
        false

    @State private var encoderRecoveryWaitActive =
        false

    @State private var menuOpen = false
    @State private var showZoom = true
    @State private var showScore = true

    @State private var scoreboard =
        ScoreboardState()

    var body: some View {

        GeometryReader {
            geometry in

            ZStack {

                CameraPreview(
                    session: camera.session
                )
                .frame(
                    width:
                        geometry.size.width,
                    height:
                        geometry.size.height
                )
                .clipped()
                .ignoresSafeArea()

                LinearGradient(
                    colors: [
                        .black.opacity(0.38),
                        .clear,
                        .black.opacity(0.55)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                VStack(spacing: 0) {

                    topBar

                    if camera.encoderRunning {
                        encoderTelemetry
                            .padding(
                                .top,
                                6
                            )
                    }

                    if
                        !camera.muxRunning,
                        let url =
                            camera.muxTestFileURL
                    {
                        ShareLink(
                            item:
                                url
                        ) {
                            Label(
                                "SHARE TS TEST",
                                systemImage:
                                    "square.and.arrow.up"
                            )
                            .font(
                                .caption2.bold()
                            )
                        }
                        .buttonStyle(
                            .borderedProminent
                        )
                        .tint(
                            .blue
                        )
                        .padding(
                            .top,
                            6
                        )
                    }

                    Spacer()

                    bottomControls
                }
                .padding(
                    .horizontal,
                    14
                )
                .padding(
                    .top,
                    10
                )
                .padding(
                    .bottom,
                    8
                )

                HStack {

                    audioControls

                    Spacer()

                    if showZoom {

                        VerticalZoomControl(
                            value:
                                Binding(
                                    get: {
                                        camera
                                            .zoomFactor
                                    },
                                    set: {
                                        camera
                                            .setZoom(
                                                $0
                                            )
                                    }
                                )
                        )
                    }
                }
                .padding(
                    .horizontal,
                    10
                )

                if menuOpen {

                    Color.black
                        .opacity(0.45)
                        .ignoresSafeArea()
                        .onTapGesture {
                            menuOpen =
                                false
                        }

                    HStack(spacing: 0) {

                        Spacer()

                        CameraSettingsDrawer(
                            camera: camera,
                            showZoom:
                                $showZoom,
                            showScore:
                                $showScore,
                            cameraRunState:
                                $cameraRunState,
                            isPresented:
                                $menuOpen
                        )
                        .frame(
                            width:
                                min(
                                    390,
                                    geometry
                                        .size
                                        .width *
                                    0.42
                                )
                        )
                    }
                    .transition(
                        .move(
                            edge: .trailing
                        )
                    )
                }
            }
            .frame(
                width:
                    geometry.size.width,
                height:
                    geometry.size.height
            )
            .clipped()
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .persistentSystemOverlays(
            .hidden
        )
        .task {

            network.start()

            await camera
                .requestPermissionsAndConfigure()

            if camera.permissionGranted {
                camera.start()
            }
        }
        .onDisappear {

            network.stop()

            camera.stopEncoder()

            camera.stop()
        }
        .onChange(
            of: scenePhase
        ) {
            newPhase in

            logScenePhase(
                newPhase
            )

            if newPhase == .active {
                scheduleEncoderRecoveryAfterInterruption()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for:
                    .AVCaptureSessionWasInterrupted,
                object:
                    camera.session
            )
        ) {
            notification in

            logCaptureInterruption(
                notification
            )
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for:
                    .AVCaptureSessionInterruptionEnded,
                object:
                    camera.session
            )
        ) {
            _ in

            diagnosticLog(
                "capture interruption ended" +
                diagnosticStateSuffix
            )

            scheduleEncoderRecoveryAfterInterruption()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for:
                    .AVCaptureSessionRuntimeError,
                object:
                    camera.session
            )
        ) {
            notification in

            logCaptureRuntimeError(
                notification
            )
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for:
                    AVAudioSession
                        .interruptionNotification
            )
        ) {
            notification in

            logAudioInterruption(
                notification
            )
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for:
                    AVAudioSession
                        .routeChangeNotification
            )
        ) {
            notification in

            logAudioRouteChange(
                notification
            )

            camera.refreshAudioInputs()
            camera.refreshActiveAudioInput()
        }
        .animation(
            .easeInOut(
                duration: 0.18
            ),
            value: menuOpen
        )
    }

    private var topBar:
        some View {

        HStack(spacing: 10) {

            VStack(
                alignment: .leading,
                spacing: 2
            ) {

                Text(
                    "SportsOS Camera"
                )
                .font(
                    .headline.bold()
                )

                Text(
                    "Game Camera · \(camera.activeVideoWidth)x\(camera.activeVideoHeight) · \(camera.activeVideoFPS)fps"
                )
                .font(.caption)
                .foregroundStyle(
                    .secondary
                )
            }

            statusPill

            networkPill

            Spacer()

            Button {

                menuOpen = true

            } label: {

                Image(
                    systemName:
                        "line.3.horizontal"
                )
                .font(
                    .title3.bold()
                )
                .frame(
                    width: 40,
                    height: 40
                )
            }
            .buttonStyle(
                .borderedProminent
            )
            .tint(
                .black.opacity(0.55)
            )
        }
    }

    private var encoderTelemetry:
        some View {

        VStack(spacing: 2) {

            Text(
                String(
                    format:
                        "H.264 · %.1f Mbps · %.0f fps",
                    camera
                        .encoderBitrateMbps,
                    camera
                        .encoderFPS
                )
            )
            .font(
                .caption2.bold()
            )
            .foregroundStyle(
                .green
            )

            Text(
                "Frames \(camera.encodedFrameCount) · Key \(camera.keyFrameCount)"
            )
            .font(.caption2)
            .foregroundStyle(
                .white.opacity(0.85)
            )

            if camera.audioEncoderRunning {
                Text(
                    "AAC · \(camera.encodedAudioPacketCount) packets · \(formattedAudioBytes)"
                )
                .font(.caption2)
                .foregroundStyle(
                    .orange
                )
            }

            Text(
                muxStatusText
            )
            .font(.caption2)
            .foregroundStyle(
                camera.muxRunning
                ? .yellow
                : camera.muxTestFileURL != nil
                    ? .green
                    : .secondary
            )

            if camera.publisherRunning {
                Text(
                    "Publisher · \(camera.publishedFrameCount) frames · \(formattedPublisherBytes)"
                )
                .font(.caption2)
                .foregroundStyle(
                    .cyan
                )
            }
        }
        .padding(
            .horizontal,
            10
        )
        .padding(
            .vertical,
            6
        )
        .background(
            .black.opacity(0.55)
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 8
            )
        )
    }

    private var muxStatusText:
        String {

        if camera.muxRunning {
            return
                "MPEG-TS TEST · \(camera.muxPacketCount) packets · V\(camera.muxVideoFrameCount) A\(camera.muxAudioFrameCount)"
        }

        if camera.muxTestFileURL != nil {
            return
                "MPEG-TS READY · \(formattedMuxBytes)"
        }

        return
            "MPEG-TS WAITING"
    }

    private var formattedMuxBytes:
        String {

        let bytes =
            Double(
                camera.muxBytes
            )

        if bytes >= 1_000_000 {
            return String(
                format:
                    "%.1f MB",
                bytes /
                    1_000_000.0
            )
        }

        if bytes >= 1_000 {
            return String(
                format:
                    "%.1f KB",
                bytes /
                    1_000.0
            )
        }

        return
            "\(camera.muxBytes) B"
    }

    private var formattedAudioBytes:
        String {

        let bytes =
            Double(
                camera.encodedAudioBytes
            )

        if bytes >= 1_000_000 {
            return String(
                format:
                    "%.1f MB",
                bytes / 1_000_000.0
            )
        }

        if bytes >= 1_000 {
            return String(
                format:
                    "%.1f KB",
                bytes / 1_000.0
            )
        }

        return "\(camera.encodedAudioBytes) B"
    }

    private var formattedPublisherBytes:
        String {

        let bytes =
            Double(
                camera.publishedBytes
            )

        if bytes >= 1_000_000 {
            return String(
                format:
                    "%.1f MB",
                bytes / 1_000_000.0
            )
        }

        if bytes >= 1_000 {
            return String(
                format:
                    "%.1f KB",
                bytes / 1_000.0
            )
        }

        return "\(camera.publishedBytes) B"
    }

    private var statusPill:
        some View {

        HStack(spacing: 6) {

            Circle()
                .fill(statusColor)
                .frame(
                    width: 8,
                    height: 8
                )

            Text(statusText)
                .font(
                    .caption2.bold()
                )
        }
        .padding(
            .horizontal,
            10
        )
        .padding(
            .vertical,
            7
        )
        .background(
            .black.opacity(0.5)
        )
        .clipShape(
            Capsule()
        )
    }

    private var networkPill:
        some View {

        HStack(spacing: 5) {

            Image(
                systemName:
                    networkIcon
            )

            if network.testState ==
                .testing
            {
                Text("TESTING")
                    .font(
                        .caption2.bold()
                    )

            } else {

                Text(
                    network
                        .quality
                        .rawValue
                )
                .font(
                    .caption2.bold()
                )

                if let upload =
                    network
                        .measuredUploadMbps
                {
                    Text(
                        String(
                            format:
                                "%.1f Mbps",
                            upload
                        )
                    )
                    .font(
                        .system(
                            size: 8,
                            weight:
                                .medium
                        )
                    )
                }
            }
        }
        .foregroundStyle(
            networkColor
        )
        .padding(
            .horizontal,
            9
        )
        .padding(
            .vertical,
            7
        )
        .background(
            .black.opacity(0.5)
        )
        .clipShape(
            Capsule()
        )
    }

    private var networkIcon:
        String {

        switch network.connectionType {

        case .wifi:
            return "wifi"

        case .cellular:
            return
                "antenna.radiowaves.left.and.right"

        case .wired:
            return "network"

        case .other:
            return "network"

        case .offline:
            return "wifi.slash"
        }
    }

    private var networkColor:
        Color {

        switch network.quality {

        case .excellent:
            return .green

        case .good:
            return .green

        case .limited:
            return .yellow

        case .poor:
            return .orange

        case .offline:
            return .red

        case .testing:
            return .yellow
        }
    }

    private var statusColor:
        Color {

        switch cameraRunState {

        case .idle:
            return .gray

        case .connecting:
            return .yellow

        case .ready:
            return .green
        }
    }

    private var statusText:
        String {

        switch cameraRunState {

        case .idle:
            return "OFFLINE"

        case .connecting:
            return "CONNECTING"

        case .ready:
            return "CAMERA READY"
        }
    }

    private var audioControls:
        some View {

        VStack(spacing: 7) {

            Text("AUDIO")
                .font(
                    .system(
                        size: 9,
                        weight: .bold
                    )
                )
                .foregroundStyle(
                    .secondary
                )

            Button {

                camera.muted.toggle()

            } label: {

                Image(
                    systemName:
                        camera.muted
                        ? "mic.slash.fill"
                        : "mic.fill"
                )
                .frame(
                    width: 28,
                    height: 28
                )
            }
            .buttonStyle(
                .borderedProminent
            )
            .tint(
                camera.muted
                ? .red
                : .black.opacity(0.48)
            )

            VerticalLevelMeter(
                value:
                    camera.audioLevel,
                clipping:
                    camera.clipping
            )
            .frame(
                width: 13,
                height: 115
            )

            Text(
                camera.muted
                ? "MUTED"
                : camera.clipping
                    ? "CLIP"
                    : camera
                        .audioMode
                        .rawValue
            )
            .font(
                .system(
                    size: 8,
                    weight: .bold
                )
            )
            .foregroundStyle(
                camera.clipping
                ? .red
                : .secondary
            )
        }
        .padding(
            .horizontal,
            7
        )
        .padding(
            .vertical,
            8
        )
        .background(
            .ultraThinMaterial
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 13
            )
        )
    }

    private var bottomControls:
        some View {

        VStack(spacing: 7) {

            HStack {

                Spacer()

                startCameraControl

                Spacer()

                VStack(
                    alignment: .trailing,
                    spacing: 2
                ) {

                    Text("SPORTSOS")
                        .font(
                            .system(
                                size: 8,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(
                            .secondary
                        )

                    Text(
                        connectionStatusText
                    )
                    .font(
                        .caption2.bold()
                    )

                    if cameraRunState ==
                        .ready
                    {
                        Text(
                            network
                                .recommendedProfile
                                .rawValue
                        )
                        .font(
                            .system(
                                size: 8,
                                weight:
                                    .semibold
                            )
                        )
                        .foregroundStyle(
                            .secondary
                        )
                    }
                }
            }

            if showScore {

                ScoreOverlayView(
                    state: scoreboard
                )
            }
        }
    }

    @ViewBuilder
    private var startCameraControl:
        some View {

        switch cameraRunState {

        case .idle:

            Button {

                beginCameraConnection()

            } label: {

                Label(
                    "START CAMERA",
                    systemImage:
                        "video.fill"
                )
                .font(
                    .caption.bold()
                )
                .padding(
                    .horizontal,
                    8
                )
            }
            .buttonStyle(
                .borderedProminent
            )
            .tint(.green)

        case .connecting:

            HStack(spacing: 8) {

                ProgressView()
                    .tint(.white)

                Text(
                    "CONNECTING…"
                )
                .font(
                    .caption.bold()
                )
            }
            .padding(
                .horizontal,
                16
            )
            .padding(
                .vertical,
                10
            )
            .background(
                .black.opacity(0.55)
            )
            .clipShape(
                Capsule()
            )

        case .ready:

            EmptyView()
        }
    }

    private var connectionStatusText:
        String {

        switch cameraRunState {

        case .idle:
            return "WAITING"

        case .connecting:
            return "CONNECTING"

        case .ready:
            return "READY"
        }
    }

    private var diagnosticStateSuffix:
        String {

        " | sessionRunning=" +
        String(
            camera.session.isRunning
        ) +
        " | encoderRunning=" +
        String(
            camera.encoderRunning
        ) +
        " | encodedFrames=" +
        String(
            camera.encodedFrameCount
        )
    }

    private func diagnosticLog(
        _ message: String
    ) {
        print(
            "[SportsOSCamera][DIAG] " +
            ISO8601DateFormatter()
                .string(
                    from: Date()
                ) +
            " " +
            message
        )
    }

    private func logScenePhase(
        _ phase: ScenePhase
    ) {
        let name: String

        switch phase {

        case .active:
            name = "active"

        case .inactive:
            name = "inactive"

        case .background:
            name = "background"

        @unknown default:
            name = "unknown"
        }

        diagnosticLog(
            "scene phase -> " +
            name +
            diagnosticStateSuffix
        )
    }

    private func logCaptureInterruption(
        _ notification:
            Notification
    ) {
        let raw =
            (
                notification.userInfo?[
                    AVCaptureSessionInterruptionReasonKey
                ] as? NSNumber
            )?.intValue

        let reasonName: String

        if
            let raw,
            let reason =
                AVCaptureSession
                    .InterruptionReason(
                        rawValue: raw
                    )
        {
            switch reason {

            case .videoDeviceNotAvailableInBackground:
                reasonName =
                    "videoDeviceNotAvailableInBackground"

                if
                    cameraRunState == .ready &&
                    camera.encoderRunning
                {
                    encoderNeedsInterruptionRecovery =
                        true
                }

            case .audioDeviceInUseByAnotherClient:
                reasonName =
                    "audioDeviceInUseByAnotherClient"

            case .videoDeviceInUseByAnotherClient:
                reasonName =
                    "videoDeviceInUseByAnotherClient"

            case .videoDeviceNotAvailableWithMultipleForegroundApps:
                reasonName =
                    "videoDeviceNotAvailableWithMultipleForegroundApps"

            case .videoDeviceNotAvailableDueToSystemPressure:
                reasonName =
                    "videoDeviceNotAvailableDueToSystemPressure"

            @unknown default:
                reasonName = "unknown"
            }

        } else {
            reasonName = "unknown"
        }

        diagnosticLog(
            "capture interruption began" +
            " | reason=" +
            reasonName +
            " | raw=" +
            String(
                raw ?? -1
            ) +
            diagnosticStateSuffix
        )
    }

    private func logCaptureRuntimeError(
        _ notification:
            Notification
    ) {
        let error =
            notification.userInfo?[
                AVCaptureSessionErrorKey
            ] as? NSError

        diagnosticLog(
            "capture runtime error" +
            " | domain=" +
            (
                error?.domain
                ?? "unknown"
            ) +
            " | code=" +
            String(
                error?.code
                ?? -1
            ) +
            " | description=" +
            (
                error?.localizedDescription
                ?? "unknown"
            ) +
            diagnosticStateSuffix
        )
    }

    private func logAudioInterruption(
        _ notification:
            Notification
    ) {
        let rawType =
            notification.userInfo?[
                AVAudioSessionInterruptionTypeKey
            ] as? UInt

        let rawOptions =
            notification.userInfo?[
                AVAudioSessionInterruptionOptionKey
            ] as? UInt

        let interruptionType =
            rawType.flatMap {
                AVAudioSession
                    .InterruptionType(
                        rawValue: $0
                    )
            }

        let typeName: String

        switch interruptionType {

        case .began:
            typeName = "began"

        case .ended:
            typeName = "ended"

        case nil:
            typeName = "unknown"

        @unknown default:
            typeName = "unknown"
        }

        let shouldResume =
            rawOptions.map {
                AVAudioSession
                    .InterruptionOptions(
                        rawValue: $0
                    )
                    .contains(
                        .shouldResume
                    )
            }
            ?? false

        diagnosticLog(
            "audio interruption" +
            " | type=" +
            typeName +
            " | shouldResume=" +
            String(
                shouldResume
            ) +
            diagnosticStateSuffix
        )
    }

    private func logAudioRouteChange(
        _ notification:
            Notification
    ) {
        let raw =
            notification.userInfo?[
                AVAudioSessionRouteChangeReasonKey
            ] as? UInt

        let reason =
            raw.flatMap {
                AVAudioSession
                    .RouteChangeReason(
                        rawValue: $0
                    )
            }

        diagnosticLog(
            "audio route change" +
            " | reason=" +
            String(
                describing: reason
            ) +
            " | raw=" +
            String(
                raw ?? 0
            ) +
            diagnosticStateSuffix
        )
    }

    private func scheduleEncoderRecoveryAfterInterruption() {

        guard
            encoderNeedsInterruptionRecovery,
            cameraRunState == .ready,
            camera.encoderRunning,
            !encoderRecoveryWaitActive
        else {
            return
        }

        encoderRecoveryWaitActive =
            true

        diagnosticLog(
            "waiting for capture session before H264 recovery" +
            diagnosticStateSuffix
        )

        Task { @MainActor in

            defer {
                encoderRecoveryWaitActive =
                    false
            }

            for attempt in 1...20 {

                guard
                    encoderNeedsInterruptionRecovery,
                    cameraRunState == .ready,
                    camera.encoderRunning
                else {
                    return
                }

                if camera.session.isRunning {

                    diagnosticLog(
                        "restarting H264 encoder after background interruption" +
                        " | attempt=" +
                        String(attempt) +
                        diagnosticStateSuffix
                    )

                    encoderNeedsInterruptionRecovery =
                        false

                    camera
                        .restartEncoderAfterInterruption(
                            profile:
                                network
                                    .recommendedProfile
                        )

                    return
                }

                try? await Task.sleep(
                    nanoseconds:
                        250_000_000
                )
            }

            diagnosticLog(
                "H264 recovery timed out waiting for capture session" +
                diagnosticStateSuffix
            )
        }
    }

    private func beginCameraConnection() {

        cameraRunState =
            .connecting

        Task {

            let networkPassed =
                await network
                    .runSportsOSNetworkTest()

            guard networkPassed else {
                cameraRunState = .idle
                return
            }

            let profileApplied =
                await camera
                    .applyStreamProfile(
                        network
                            .recommendedProfile
                    )

            guard profileApplied else {
                cameraRunState = .idle
                return
            }

            camera.startEncoder(
                profile:
                    network
                        .recommendedProfile
            )

            cameraRunState =
                .ready
        }
    }
}
