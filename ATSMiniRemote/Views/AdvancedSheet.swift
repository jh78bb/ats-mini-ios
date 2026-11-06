import SwiftUI

/// 오른쪽 위 톱니바퀴 버튼: 고급 사용자용 수신기 제어.
/// 대역폭, AGC/감쇠기, 보정, 슬립, 엔코더 버튼, 메모리 슬롯. 수신기에 연결해야 동작합니다.
/// 각 항목 제목 오른쪽의 `?`는 연결하지 않아도 눌러 볼 수 있습니다.
struct AdvancedSheet: View {
    @Environment(RadioState.self) private var radio
    @Environment(\.dismiss) private var dismiss
    @State private var slotName = ""
    @State private var slotToClear: MemorySlot?

    var body: some View {
        NavigationStack {
            Form {
                if !radio.isConnected {
                    Section {
                        Label("Connect to a receiver to use these controls.", systemImage: "antenna.radiowaves.left.and.right.slash")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Group {
                        stepRow("Bandwidth", value: radio.isConnected && !radio.bandwidthText.isEmpty ? radio.bandwidthText : nil,
                                down: RadioProtocol.bandwidthPrevious, up: RadioProtocol.bandwidthNext)
                        stepRow("AGC / Attenuator", value: radio.isConnected ? "#\(radio.agcIndex)" : nil,
                                down: RadioProtocol.agcDown, up: RadioProtocol.agcUp)
                        stepRow("Calibration", value: nil,
                                down: RadioProtocol.calibrationDown, up: RadioProtocol.calibrationUp)
                    }
                    .disabled(!radio.isConnected)
                } header: {
                    HelpHeader(title: "Reception", topic: .reception)
                }

                Section {
                    HStack(spacing: 12) {
                        Button { radio.send(RadioProtocol.sleepOn) } label: {
                            Label("Sleep on", systemImage: "moon.fill").frame(maxWidth: .infinity)
                        }
                        Button { radio.send(RadioProtocol.sleepOff) } label: {
                            Label("Wake up", systemImage: "sun.max.fill").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!radio.isConnected)
                } header: {
                    HelpHeader(title: "Sleep", topic: .sleep)
                }

                Section {
                    HStack(spacing: 8) {
                        encoderButton("chevron.left", label: "Encoder left", RadioProtocol.encoderDown)
                        encoderButton("hand.tap", label: "Click", RadioProtocol.encoderClick, text: "Click")
                        encoderButton("hand.tap.fill", label: "Short press", RadioProtocol.encoderShortPress, text: "Press")
                        encoderButton("chevron.right", label: "Encoder right", RadioProtocol.encoderUp)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!radio.isConnected)
                } header: {
                    HelpHeader(title: "Receiver encoder", topic: .encoder)
                }

                memorySection
                logSection
            }
            .navigationTitle("Advanced")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } } }
            .confirmationDialog("Clear this slot?", isPresented: Binding(get: { slotToClear != nil }, set: { if !$0 { slotToClear = nil } }),
                                titleVisibility: .visible) {
                Button("Clear on receiver", role: .destructive) {
                    if let s = slotToClear { radio.clearMemory(s) }
                    slotToClear = nil
                }
            } message: {
                if let s = slotToClear { Text("Slot \(s.slot): \(s.name.isEmpty ? frequencyText(s) : s.name + " " + frequencyText(s))") }
            }
        }
        .presentationDetents([.large])
        .onAppear { if radio.isConnected && radio.memorySlots.isEmpty { radio.refreshMemory() } }
    }

    // MARK: 메모리 슬롯

    private var memorySection: some View {
        Section {
            Group {
            Button { radio.refreshMemory() } label: { Label("Read slots", systemImage: "arrow.clockwise") }

            if radio.memorySlots.isEmpty {
                Text("No slots loaded.").foregroundStyle(.secondary)
            }
            ForEach(radio.memorySlots) { m in
                Button { radio.select(station: RadioState.Station(id: "slot\(m.slot)", label: m.name, kHz: m.frequencyKHz, bandName: m.band, mode: m.mode, slot: m.slot)); dismiss() } label: {
                HStack {
                    Text(String(format: "%02d", m.slot)).monospacedDigit().foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.name.isEmpty ? frequencyText(m) : m.name)
                        if !m.name.isEmpty {
                            Text(frequencyText(m)).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text("\(m.band) · \(m.mode)").font(.footnote).foregroundStyle(.secondary)
                }
                }
                .foregroundStyle(.primary)
                .swipeActions {
                    Button("Clear", role: .destructive) { slotToClear = m }
                }
            }

            HStack {
                TextField("Name (9 ASCII chars)", text: $slotName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: slotName) { _, new in
                        let clean = RadioProtocol.sanitizedMemoryName(new)
                        if clean != new { slotName = clean }
                    }
                Button("Save current frequency") {
                    radio.saveToMemory(name: slotName)
                    slotName = ""
                }
                .buttonStyle(.bordered)
            }
            }
            .disabled(!radio.isConnected)
        } header: {
            HelpHeader(title: "Memory slots", topic: .memory)
        }
    }

    // MARK: 통신 로그

    private var logSection: some View {
        Section {
            LabeledContent("Status lines received") { Text("\(radio.statusCount)").monospacedDigit() }
            if !radio.lastStatusLine.isEmpty {
                Text(verbatim: radio.lastStatusLine)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            ForEach(radio.log.suffix(40).reversed()) { e in
                Text(verbatim: (e.direction == .tx ? "→ " : "← ") + e.text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(e.direction == .tx ? Color.secondary : Color.primary)
                    .textSelection(.enabled)
            }
            HStack {
                Button("Copy log") {
                    UIPasteboard.general.string = (["status: \(radio.lastStatusLine)"] + radio.log.map { ($0.direction == .tx ? "-> " : "<- ") + $0.text }).joined(separator: "\n")
                }
                Spacer()
                Button("Clear log", role: .destructive) { radio.clearLog() }
            }
            .buttonStyle(.bordered)
        } header: {
            HelpHeader(title: "Communication log", topic: .log)
        }
    }

    // MARK: 부품

    private func frequencyText(_ m: MemorySlot) -> String {
        m.mode == "FM" ? String(format: "%.2f MHz", Double(m.frequencyHz) / 1_000_000) : "\(m.frequencyKHz) kHz"
    }

    private func stepRow(_ title: LocalizedStringKey, value: String?, down: String, up: String, presses: Int = 1) -> some View {
        HStack {
            Text(title)
            if let value { Text(value).foregroundStyle(.secondary).monospacedDigit() }
            Spacer()
            HStack(spacing: 8) {
                Button { radio.send(String(repeating: down, count: presses)) } label: { Image(systemName: "minus").frame(width: 28) }
                    .accessibilityLabel("Decrease")
                Button { radio.send(String(repeating: up, count: presses)) } label: { Image(systemName: "plus").frame(width: 28) }
                    .accessibilityLabel("Increase")
            }
            .buttonStyle(.bordered)
        }
    }

    private func encoderButton(_ symbol: String, label: LocalizedStringKey, _ command: String, text: LocalizedStringKey? = nil) -> some View {
        Button { radio.send(command) } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                if let text { Text(text).font(.caption2) }
            }
            .frame(maxWidth: .infinity, minHeight: 34)
        }
        .accessibilityLabel(label)
    }
}
