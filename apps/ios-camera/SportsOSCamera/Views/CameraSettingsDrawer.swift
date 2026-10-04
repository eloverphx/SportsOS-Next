import SwiftUI

struct CameraSettingsDrawer: View {
    @ObservedObject var camera: CameraController

    @Binding var showZoom: Bool
    @Binding var showScore: Bool
    @Binding var cameraRunState: CameraScreen.CameraRunState
    @Binding var isPresented: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Camera Settings")
                        .font(.title3.bold())

                    Spacer()

                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("DISPLAY")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    Toggle("Show Zoom Control", isOn: $showZoom)
                    Toggle("Show Scoreboard", isOn: $showScore)
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("STABILIZATION")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    Picker(
                        "Stabilization",
                        selection: Binding(
                            get: {
                                camera.stabilizationMode
                            },
                            set: {
                                camera.setStabilization($0)
                            }
                        )
                    ) {
                        Text("Auto").tag("Auto")
                        Text("Standard").tag("Standard")
                        Text("Cinematic").tag("Cinematic")
                        Text("Off").tag("Off")
                    }
                    .pickerStyle(.segmented)
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("AUDIO")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    Picker(
                        "Audio Mode",
                        selection: $camera.audioMode
                    ) {
                        ForEach(
                            CameraController.AudioMode.allCases
                        ) { mode in
                            Text(mode.rawValue)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Mute Audio", isOn: $camera.muted)

                    if !camera.availableAudioInputs.isEmpty {
                        Picker(
                            "Input",
                            selection: Binding(
                                get: {
                                    camera.selectedAudioInputUID
                                },
                                set: { newValue in
                                    guard let uid = newValue else {
                                        return
                                    }

                                    camera.selectAudioInput(uid: uid)
                                }
                            )
                        ) {
                            ForEach(
                                camera.availableAudioInputs,
                                id: \.uid
                            ) { input in
                                Text(input.portName)
                                    .tag(Optional(input.uid))
                            }
                        }
                    }

                    if camera.audioMode == .manual {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Input Gain")
                                    .font(.caption)

                                Spacer()

                                Text(
                                    "\(Int(camera.inputGain * 100))%"
                                )
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            }

                            Slider(
                                value: $camera.inputGain,
                                in: 0...1
                            )
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("STATUS")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    HStack {
                        Text("Zoom")

                        Spacer()

                        Text(
                            String(
                                format: "%.1fx",
                                camera.zoomFactor
                            )
                        )
                        .monospacedDigit()
                    }

                    HStack {
                        Text("Microphone")

                        Spacer()

                        Text(
                            camera.muted
                                ? "Muted"
                                : "Active"
                        )
                        .foregroundStyle(
                            camera.muted
                                ? .red
                                : .green
                        )
                    }
                }

                if cameraRunState == .ready {
                    Divider()
                        .padding(.top, 8)

                    Button(role: .destructive) {
                        camera.stopEncoder()
                        cameraRunState = .idle
                        isPresented = false
                    } label: {
                        Label(
                            "END CAMERA SESSION",
                            systemImage: "stop.fill"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }

                Text(
                    "Ending the camera session will stop the active SportsOS stream. The camera preview remains available."
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
            .padding(20)
        }
        .background(.ultraThinMaterial)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
        .padding(8)
    }
}
