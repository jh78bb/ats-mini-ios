import SwiftUI

/// 햄버거 메뉴: 기기 연결(맨 위), 밴드·모드·스텝·볼륨. 각 항목 제목 오른쪽의 `?`를 누르면 설명이 나옵니다.
/// 연결 중에는 밴드를 수신기의 밴드 목록에서, 모드를 분할 버튼으로 고릅니다.
struct ControlsSheet: View {
    @Environment(RadioState.self) private var radio
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                connectSection
                Section { bandControl } header: { HelpHeader(title: "BAND", topic: .band) }
                Section { modeControl } header: { HelpHeader(title: "MODE", topic: .mode) }
                Section {
                    seekControl
                } header: { HelpHeader(title: "SEEK", topic: .seek) }
                Section {
                    Picker("Step", selection: Binding(get: { radio.step }, set: { radio.setStep($0) })) {
                        ForEach(radio.band.steps, id: \.self) { Text("\($0) kHz").tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: { HelpHeader(title: "STEP", topic: .step) }
                Section {
                    HStack {
                        Image(systemName: "speaker.fill").foregroundStyle(Theme.dim)
                        Slider(value: Binding(get: { Double(radio.volume) }, set: { radio.setVolume(Int($0)) }), in: 0...63)
                        Image(systemName: "speaker.wave.3.fill").foregroundStyle(Theme.dim)
                    }
                } header: { HelpHeader(title: "VOLUME", topic: .volume) }
            }
            .navigationTitle("Controls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: 기기 연결 (맨 위)

    private var connectSection: some View {
        Section {
            NavigationLink {
                ConnectView()
            } label: {
                HStack {
                    Label("Connect Device", systemImage: "dot.radiowaves.left.and.right")
                    Spacer()
                    connectionLabel.foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var connectionLabel: some View {
        switch radio.linkState {
        case .connected(let name): Text(verbatim: name)
        case .connecting: Text("Connecting…")
        case .disconnected: Text("Not connected")
        }
    }

    // MARK: Seek / Scan

    @ViewBuilder
    private var seekControl: some View {
        @Bindable var radio = radio
        Group {
            HStack(spacing: 10) {
                Button { radio.seek(forward: false) } label: {
                    Label("Seek down", systemImage: "backward.end.fill").labelStyle(.iconOnly).frame(maxWidth: .infinity, minHeight: 30)
                }
                .accessibilityLabel("Seek down")
                Button {
                    if radio.isSeeking { radio.stopSeek() } else { radio.startScan() }
                } label: {
                    Label(radio.isSeeking ? "Stop" : "Scan", systemImage: radio.isSeeking ? "stop.fill" : "dot.radiowaves.forward")
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
                Button { radio.seek(forward: true) } label: {
                    Label("Seek up", systemImage: "forward.end.fill").labelStyle(.iconOnly).frame(maxWidth: .infinity, minHeight: 30)
                }
                .accessibilityLabel("Seek up")
            }
            .buttonStyle(.bordered)
            Picker("Sensitivity", selection: $radio.seekSensitivity) {
                Text("Strong").tag(RadioState.SeekSensitivity.strong)
                Text("Normal").tag(RadioState.SeekSensitivity.normal)
                Text("Weak").tag(RadioState.SeekSensitivity.weak)
            }
            .pickerStyle(.segmented)
            if !radio.isConnected {
                Label("Connect a receiver to seek.", systemImage: "antenna.radiowaves.left.and.right.slash")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .disabled(!radio.isConnected)
    }

    // MARK: 밴드

    @ViewBuilder
    private var bandControl: some View {
        if radio.isConnected {
            if let current = radio.currentDeviceBandIndex {
                Picker("Band", selection: Binding(get: { current }, set: { radio.selectBand(index: $0) })) {
                    ForEach(DeviceBand.all) { b in
                        HStack {
                            Text(verbatim: b.name)
                            Spacer()
                            Text(verbatim: b.rangeLabel).foregroundStyle(.secondary)
                        }
                        .tag(b.index)
                    }
                }
                .pickerStyle(.navigationLink)
            } else {
                cycleRow(title: radio.deviceBandName.isEmpty ? radio.band.rawValue : radio.deviceBandName,
                         previous: { radio.cycleBand(forward: false) },
                         next: { radio.cycleBand(forward: true) })
            }
        } else {
            Picker("Band", selection: Binding(get: { radio.band }, set: { radio.select(band: $0) })) {
                ForEach(Band.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: 모드

    @ViewBuilder
    private var modeControl: some View {
        if radio.isConnected {
            if radio.deviceMode.isEmpty {
                cycleRow(title: radio.modeLabel,
                         previous: { radio.cycleMode(forward: false) },
                         next: { radio.cycleMode(forward: true) })
            } else {
                Picker("Mode", selection: Binding(get: { radio.deviceMode }, set: { radio.selectMode($0) })) {
                    ForEach(radio.modeChoices, id: \.self) { Text(verbatim: $0).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        } else {
            Picker("Mode", selection: Binding(get: { radio.mode }, set: { radio.setMode($0) })) {
                ForEach(radio.band.modes, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private func cycleRow(title: String, previous: @escaping () -> Void, next: @escaping () -> Void) -> some View {
        HStack {
            Button(action: previous) { Image(systemName: "chevron.left") }
            Spacer()
            Text(verbatim: title).font(.system(size: 17, weight: .semibold))
            Spacer()
            Button(action: next) { Image(systemName: "chevron.right") }
        }
        .buttonStyle(.bordered)
    }
}
