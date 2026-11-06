import SwiftUI

/// 기기 연결 화면: 연결 상태, 블루투스 LE 검색 목록, Wi-Fi TCP(호스트·포트 입력).
struct ConnectView: View {
    @Environment(RadioState.self) private var radio
    @Environment(\.openURL) private var openURL

    var body: some View {
        @Bindable var ble = radio.ble
        @Bindable var tcp = radio.tcp
        List {
            Section {
                statusRow
                if radio.isConnected {
                    Button("Disconnect", role: .destructive) { radio.disconnect() }
                }
            }

            Section {
                switch ble.bluetooth {
                case .unauthorized:
                    Button("Allow Bluetooth in Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                case .poweredOff:
                    Text("Turn on Bluetooth on your iPhone.").foregroundStyle(.secondary)
                case .unsupported:
                    Text("This device does not support Bluetooth LE.").foregroundStyle(.secondary)
                default: EmptyView()
                }
                if !radio.isConnected && ble.bluetooth == .ready {
                    if ble.devices.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Looking for nearby receivers…").foregroundStyle(.secondary)
                        }
                    }
                    ForEach(ble.devices) { d in
                        Button { ble.connect(d) } label: {
                            HStack {
                                Image(systemName: "radio")
                                Text(d.name)
                                Spacer()
                                Text("\(d.rssi) dBm").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Toggle("Show all BLE devices", isOn: $ble.scanAll)
                }
            } header: {
                Text("Bluetooth LE")
            } footer: {
                Text("On the ATS Mini, set Settings → Bluetooth → Ad hoc, then scan close to the receiver. If it is not listed, turn on “Show all BLE devices”.")
            }

            Section {
                LabeledContent("Host") {
                    TextField("atsmini.local", text: $tcp.host)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                LabeledContent("Port") {
                    TextField("60000", text: $tcp.port)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                }
                Button("Connect") { ble.stopScan(); tcp.connect() }
                    .disabled(radio.isConnected)
            } header: {
                Text("Wi-Fi TCP")
            } footer: {
                Text("On the ATS Mini, set Settings → TCP Port → Ad hoc and turn on Wi-Fi, then connect to atsmini.local or the receiver’s IP address on port 60000. There is no authentication or encryption, so use trusted networks only. To try the app in the iOS Simulator, run tools/mock_ats_mini.py on your Mac and connect to 127.0.0.1.")
            }
        }
        .navigationTitle("Connect Device")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { ble.startScan() }
        .onDisappear { ble.stopScan() }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch radio.linkState {
        case .connected(let name):
            Label("\(name) connected", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.mint)
        case .connecting(let name):
            HStack(spacing: 10) { ProgressView(); Text("Connecting to \(name)…") }
        case .disconnected:
            Label("Not connected", systemImage: "circle.dashed").foregroundStyle(.secondary)
        }
    }
}

struct ConnectSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ConnectView()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
