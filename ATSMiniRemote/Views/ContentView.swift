import SwiftUI

struct ContentView: View {
    @Environment(RadioState.self) private var radio
    @State private var showControls = false
    @State private var showConnect = false
    @State private var showVolume = false
    @State private var showAdvanced = false
    @State private var dragStart: Int?

    var body: some View {
        ZStack {
            Theme.background
            VStack(spacing: 12) {
                header
                tuningCard
                statTiles
                actions
                signalCard
                StationCarousel()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
        }
        .overlay(alignment: .top) {
            if let message = radio.deviceMessage {
                Text(verbatim: message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Theme.card, in: Capsule())
                    .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
                    .padding(.top, 58)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: radio.deviceMessage)
        .sheet(isPresented: $showControls) { ControlsSheet() }
        .sheet(isPresented: $showConnect) { ConnectSheet() }
        .sheet(isPresented: $showAdvanced) { AdvancedSheet() }
        .onChange(of: radio.isConnected) { _, connected in if connected { showConnect = false } }
        .sensoryFeedback(.selection, trigger: radio.frequency)
    }

    // MARK: 헤더

    private var header: some View {
        HStack {
            Button { showControls = true } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 40, height: 40)
                    .background(Theme.chip, in: Circle())
            }
            .accessibilityLabel("Controls")
            Text("Radio").font(.system(size: 22, weight: .bold))
            Spacer()
            Button { showAdvanced = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 36, height: 36)
                    .background(Theme.chip, in: Circle())
            }
            .accessibilityLabel("Advanced settings")
            ConnectionToggle(state: radio.linkState) {
                if radio.isConnected { radio.disconnect() } else { showConnect = true }
            }
        }
        .foregroundStyle(Theme.text)
        .padding(.top, 4)
    }

    // MARK: 튜닝 카드 (다이얼 + 큰 주파수)

    private var tuningCard: some View {
        VStack(spacing: 10) {
            HStack {
                CardLabel(symbol: "dot.radiowaves.left.and.right", text: "Now tuning")
                Spacer()
            }
            .padding(.horizontal, 4)

            dial

            HStack(spacing: 8) {
                arrow("chevron.left", steps: -1)
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(radio.frequencyText)
                        .font(.system(size: 58, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.2), value: radio.frequency)
                    Text(radio.band.unit)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.dim)
                }
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                Spacer(minLength: 0)
                arrow("chevron.right", steps: 1)
            }

            HStack(spacing: 8) {
                Text(verbatim: radio.bandLabel)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                Chip(symbol: "waveform", text: radio.modeLabel)
                Chip(symbol: "arrow.left.and.right", text: "\(radio.step) kHz")
            }
        }
        .card()
    }

    private var dial: some View {
        let spec = radio.band.dial
        return DialRuler(band: radio.band, center: Double(radio.frequency) / Double(spec.tick))
            .animation(.snappy(duration: 0.2), value: radio.frequency)
            .animation(.snappy(duration: 0.2), value: radio.band)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if dragStart == nil { dragStart = radio.frequency }
                        let ticks = Int((-v.translation.width / 14).rounded())
                        let raw = (dragStart ?? radio.frequency) + ticks * spec.tick
                        let step = radio.step
                        radio.setFrequency(Int((Double(raw) / Double(step)).rounded()) * step)
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .accessibilityElement()
            .accessibilityLabel("Frequency dial")
            .accessibilityValue("\(radio.frequencyText) \(radio.band.unit)")
            .accessibilityAdjustableAction { radio.tune(by: $0 == .increment ? 1 : -1) }
    }

    private func arrow(_ symbol: String, steps: Int) -> some View {
        Button { radio.tune(by: steps) } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 44, height: 44)
                .background(Theme.chip, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .accessibilityLabel(steps < 0 ? String(localized: "Tune down") : String(localized: "Tune up"))
    }

    // MARK: 상태 타일 (RSSI / SNR / 볼륨)

    private var statTiles: some View {
        HStack(spacing: 10) {
            tile("antenna.radiowaves.left.and.right", "\(radio.rssi)", "RSSI dBµV")
            tile("waveform.path", "\(radio.snr)", "SNR dB")
            Button { showVolume = true } label: {
                tile(radio.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                     radio.isMuted ? "—" : "\(radio.volume)", "Volume")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Volume \(radio.volume)")
            .accessibilityHint("Opens the volume slider")
            .popover(isPresented: $showVolume, arrowEdge: .bottom) { VolumePopup() }
        }
    }

    private func tile(_ symbol: String, _ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(Theme.dim)
            Text(value).font(.system(size: 26, weight: .bold)).foregroundStyle(.white)
                .contentTransition(.numericText())
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity)
        .card(padding: 12)
    }

    // MARK: 버튼 (흰색 알약 + 음소거)

    private var actions: some View {
        HStack(spacing: 10) {
            Button { radio.toggleFavorite() } label: {
                HStack(spacing: 8) {
                    Image(systemName: radio.isFavorite ? "heart.fill" : "heart")
                    (radio.isFavorite ? Text("Saved to presets") : Text("Save to presets"))
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(.white, in: Capsule())
            }
            .accessibilityLabel(radio.isFavorite ? String(localized: "Remove from presets") : String(localized: "Save to presets"))

            Button { radio.toggleMute() } label: {
                Image(systemName: radio.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(radio.isMuted ? Theme.pointer : Theme.text)
                    .frame(width: 52, height: 52)
                    .background(Theme.card, in: Circle())
                    .overlay(Circle().stroke(Theme.stroke, lineWidth: 1))
            }
            .accessibilityLabel(radio.isMuted ? String(localized: "Unmute") : String(localized: "Mute"))
        }
    }

    // MARK: 이퀄라이저 카드

    private var signalCard: some View {
        VStack(spacing: 10) {
            HStack {
                CardLabel(symbol: "chart.bar.fill", text: "Signal")
                Spacer()
                if radio.isSeeking {
                    Button { radio.stopSeek() } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "stop.fill").font(.system(size: 9))
                            (radio.isScanning ? Text("SCANNING") : Text("SEEKING"))
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.white, in: Capsule())
                    }
                    .accessibilityLabel("Stop seeking")
                } else {
                    (radio.isConnected ? Text("LIVE") : Text("OFFLINE"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(radio.isConnected ? Theme.mint : Theme.dim)
                }
            }
            Equalizer().frame(maxHeight: .infinity)
        }
        .card()
        .frame(maxHeight: .infinity)
    }
}

/// 헤더 오른쪽의 연결 상태 칩. 누르면 연결 해제(연결 중) 또는 기기 검색 화면을 엽니다.
struct ConnectionToggle: View {
    let state: LinkState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 14).frame(height: 36)
            .background(Theme.chip, in: Capsule())
        }
        .accessibilityLabel("Connect device")
        .accessibilityValue(title)
    }

    private var title: String {
        switch state {
        case .connected: "ON"
        case .connecting: "…"
        case .disconnected: "OFF"
        }
    }
    private var color: Color {
        switch state {
        case .connected: Theme.mint
        case .connecting: .orange
        case .disconnected: .gray.opacity(0.6)
        }
    }
}

/// 하단 플로팅 알약 스테이션 바. 연결 중에는 수신기의 메모리 슬롯, 아니면 앱 프리셋을 보여주고,
/// 현재 주파수와 일치하는 항목이 밝은 캡슐로 강조됩니다.
struct StationCarousel: View {
    @Environment(RadioState.self) private var radio

    var body: some View {
        let stations = radio.stations
        let current = radio.currentStation
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if stations.isEmpty {
                        Text(radio.isConnected ? "No memory slots on the receiver." : "No presets yet. Tap Save to presets.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.dim)
                            .padding(.horizontal, 16).frame(height: 38)
                    }
                    ForEach(stations) { st in
                        let selected = st == current
                        Button { withAnimation(.snappy) { radio.select(station: st) } } label: {
                            Text(verbatim: st.label)
                                .font(.system(size: 14, weight: selected ? .semibold : .medium))
                                .foregroundStyle(selected ? .white : Theme.dim)
                                .lineLimit(1)
                                .padding(.horizontal, 16).frame(height: 38)
                                .background(selected ? Color.white.opacity(0.16) : .clear, in: Capsule())
                        }
                        .id(st.id)
                    }
                }
                .padding(6)
            }
            .onChange(of: current?.id) { _, id in
                if let id { withAnimation(.snappy) { proxy.scrollTo(id, anchor: .center) } }
            }
            .onAppear { if let id = current?.id { proxy.scrollTo(id, anchor: .center) } }
        }
        .background(Theme.card, in: Capsule())
        .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
        .frame(height: 52)
    }
}

/// 볼륨 타일을 누르면 뜨는 팝업: 음소거 버튼 + 0~63 슬라이더.
struct VolumePopup: View {
    @Environment(RadioState.self) private var radio

    var body: some View {
        HStack(spacing: 14) {
            Button { radio.toggleMute() } label: {
                Image(systemName: radio.isMuted ? "speaker.slash.fill" : "speaker.fill")
                    .foregroundStyle(radio.isMuted ? Theme.pointer : Theme.text)
                    .frame(width: 28)
            }
            .accessibilityLabel(radio.isMuted ? String(localized: "Unmute") : String(localized: "Mute"))

            Slider(value: Binding(get: { Double(radio.volume) }, set: { radio.setVolume(Int($0.rounded())) }),
                   in: 0...63, step: 1)
                .tint(.white)
                .accessibilityLabel("Volume")

            Text("\(radio.volume)")
                .font(.system(size: 17, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 32, alignment: .trailing)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 18)
        .frame(width: 300, height: 64)
        .background(Theme.card)
        .preferredColorScheme(.dark)
        .presentationCompactAdaptation(.popover)
        .sensoryFeedback(.selection, trigger: radio.volume)
    }
}
