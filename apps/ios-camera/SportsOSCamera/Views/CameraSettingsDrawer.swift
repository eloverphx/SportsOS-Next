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

                    HStack {
                        Text("Active Source")

                        Spacer()

                        Text(
                            camera.activeAudioInputName
                        )
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                    }

                    if !camera.availableAudioInputs.isEmpty {
                        VStack(
                            alignment: .leading,
                            spacing: 8
                        ) {
                            Text("MICROPHONE INPUT")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)

                            ForEach(
                                camera.availableAudioInputs,
                                id: \.uid
                            ) { input in

                                let selected =
                                    camera
                                        .selectedAudioInputUID ==
                                        input.uid

                                Button {
                                    camera.selectAudioInput(
                                        uid: input.uid
                                    )
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(
                                            systemName:
                                                selected
                                                ? "checkmark.circle.fill"
                                                : "circle"
                                        )

                                        Text(input.portName)
                                            .lineLimit(1)

                                        Spacer()

                                        if selected {
                                            Text("SELECTED")
                                                .font(
                                                    .caption2.bold()
                                                )
                                                .foregroundStyle(
                                                    .secondary
                                                )
                                        }
                                    }
                                    .frame(
                                        maxWidth: .infinity,
                                        alignment: .leading
                                    )
                                    .padding(.vertical, 9)
                                    .padding(.horizontal, 12)
                                    .contentShape(
                                        Rectangle()
                                    )
                                }
                                .buttonStyle(.bordered)
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

                if
                    cameraRunState == .ready ||
                    cameraRunState == .ingestLost
                {
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
                    "Ending the camera session stops camera capture and ingest. The camera preview remains available."
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
