import AVKit
import SwiftUI

@main
struct ClaudeControlApp: App {
    @StateObject private var model = ControlModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: ControlModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 14) {
                        Text(headline)
                            .font(.title.weight(.bold))
                            .multilineTextAlignment(.center)
                        Text(model.connected ? "Last: \(model.lastAction)" : (model.problem ?? "Connecting…"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        if model.stopped {
                            Button {
                                Task { await model.resume() }
                            } label: {
                                Label("Let Claude Continue", systemImage: "play.fill")
                                    .font(.title2.weight(.bold))
                                    .frame(maxWidth: .infinity, minHeight: 60)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .disabled(!model.connected)
                        } else {
                            Button {
                                Task { await model.stop() }
                            } label: {
                                Label("STOP", systemImage: "stop.fill")
                                    .font(.largeTitle.weight(.heavy))
                                    .frame(maxWidth: .infinity, minHeight: 80)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        }
                    }
                    .padding(.vertical, 8)
                }

                FloatingStopSection(pip: model.pip)

                Section {
                    TextField("192.168.1.20", text: $model.address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { Task { await model.refresh() } }
                    Label(model.connected ? "Connected" : "Not connected",
                          systemImage: model.connected ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(model.connected ? .green : .secondary)
                } header: {
                    Text("Your PC's address")
                } footer: {
                    Text("The IP address of the PC running the iPad MCP server (port 8765 is added automatically). On Windows, run ipconfig and use the IPv4 Address.")
                }
            }
            .navigationTitle("Claude Control")
        }
        .task {
            model.pip.setUp()
            await model.pollForever()
        }
    }

    private var headline: String {
        if !model.connected { return "Not connected" }
        return model.stopped ? "⛔ Claude is stopped" : "🟢 Claude can control this iPad"
    }
}

/// The PiP preview and its start button. Observes the PiP controller directly
/// so the button updates when PiP becomes possible or starts.
struct FloatingStopSection: View {
    @ObservedObject var pip: PiPController

    var body: some View {
        Section {
            PiPLayerView(layer: pip.displayLayer)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Button {
                pip.start()
            } label: {
                Label(pip.isActive ? "Floating Stop Button Is On" : "Show Floating Stop Button",
                      systemImage: "pip.enter")
            }
            .disabled(!pip.isPossible || pip.isActive)
        } header: {
            Text("Floating Stop Button")
        } footer: {
            Text(pip.isSupported
                 ? "This floats over every app. Press its ⏸ button to stop Claude and ▶ to let it continue. Drag it to a corner so it doesn't cover what Claude needs to see. Going to the Home Screen also opens it."
                 : "Picture in Picture isn't available on this device. Use the STOP button above or the web page on your PC.")
        }
    }
}

/// Hosts the PiP layer in the app; PiP needs it on screen to start.
struct PiPLayerView: UIViewRepresentable {
    let layer: AVSampleBufferDisplayLayer

    func makeUIView(context: Context) -> LayerHostView {
        let view = LayerHostView()
        view.backgroundColor = .black
        view.hosted = layer
        return view
    }

    func updateUIView(_ uiView: LayerHostView, context: Context) {}
}

final class LayerHostView: UIView {
    var hosted: CALayer? {
        didSet {
            oldValue?.removeFromSuperlayer()
            if let hosted { layer.addSublayer(hosted) }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        hosted?.frame = bounds
    }
}
