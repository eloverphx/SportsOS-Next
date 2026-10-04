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

    @State private var cameraRunState:
        CameraRunState = .idle

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
