import Foundation
import Observation

enum Band: String, CaseIterable, Identifiable {
    case fm = "FM", lw = "LW", mw = "MW", sw = "SW"
    var id: String { rawValue }

    /// 주파수는 모두 kHz 정수로 다룹니다.
    var range: ClosedRange<Int> {
        switch self {
        case .fm: 64_000...108_000
        case .lw: 153...279
        case .mw: 520...1_710
        case .sw: 2_300...26_100
        }
    }
    var steps: [Int] {
        switch self {
        case .fm: [10, 50, 100, 200]
        case .lw, .mw: [1, 5, 9, 10]
        case .sw: [1, 5, 10, 100]
        }
    }
    var defaultFrequency: Int {
        switch self {
        case .fm: 101_700
        case .lw: 198
        case .mw: 999
        case .sw: 9_620
        }
    }
    var modes: [String] { self == .fm ? ["FM"] : ["AM", "LSB", "USB"] }

    /// 다이얼 눈금: 눈금 한 칸(kHz), 굵은 눈금 간격(칸 수), 라벨 나눗수, 라벨 소수 자릿수.
    var dial: (tick: Int, major: Int, divisor: Double, decimals: Int) {
        switch self {
        case .fm: (100, 10, 1000, 0)
        case .lw: (1, 10, 1, 0)
        case .mw: (10, 10, 1, 0)
        case .sw: (10, 10, 1000, 1)
        }
    }
    var unit: String { self == .fm ? "MHz" : "kHz" }
}

struct Preset: Identifiable, Hashable {
    let band: Band
    let frequency: Int
    var id: String { "\(band.rawValue)-\(frequency)" }

    var label: String {
        band == .fm ? String(format: "FM %.1f", Double(frequency) / 1000) : "\(band.rawValue) \(frequency)"
    }
}

/// 화면이 보는 라디오 상태. 기기에 연결되면 수신기가 보내는 상태가 값을 덮어쓰고,
/// 연결이 없으면 데모 값으로 동작합니다.
@Observable
final class RadioState {
    let ble = BLERadioLink()
    let tcp = TCPRadioLink()

    /// 지금 쓰는 전송 계층 (TCP가 연결되어 있으면 TCP, 아니면 BLE).
    private var link: RadioTransport { tcp.isConnected ? tcp as RadioTransport : ble as RadioTransport }

    var linkState: LinkState { tcp.linkState != .disconnected ? tcp.linkState : ble.linkState }
    func disconnect() { tcp.disconnect(); ble.disconnect() }

    var band: Band = .fm
    private(set) var frequencies: [Band: Int] = Dictionary(uniqueKeysWithValues: Band.allCases.map { ($0, $0.defaultFrequency) })
    private(set) var stepIndex: [Band: Int] = [.fm: 2, .lw: 1, .mw: 2, .sw: 1]
    private(set) var modeIndex: [Band: Int] = [:]

    var volume = 24              // 0...63
    var isMuted = false
    var rssi = 42
    var snr = 18
    private(set) var deviceBandName = ""
    private(set) var voltage: Double?
    private(set) var bandwidthText = ""
    private(set) var stepText = ""
    private(set) var agcIndex = 0
    /// 수신기가 보낸 오류 메시지 (몇 초 뒤 사라짐).
    private(set) var deviceMessage: String?
    private(set) var log: [LogEntry] = []
    private(set) var lastStatusLine = ""
    private(set) var statusCount = 0
    private(set) var memorySlots: [MemorySlot] = []

    /// 연결하지 않았을 때 쓰는 앱 프리셋. 직접 저장한 것만 보관하고(기본값 없음), 앱을 껐다 켜도 유지됩니다.
    /// 연결 중에는 수신기의 메모리 슬롯이 스테이션 목록이 됩니다.
    private(set) var presets: [Preset] = RadioState.loadPresets()
    private(set) var deviceMode = ""
    private(set) var deviceFrequencyKHz = 0
    private(set) var memoryLoaded = false
    @ObservationIgnored private var readingMemory = false
    @ObservationIgnored private var pendingSlots: [MemorySlot] = []
    @ObservationIgnored private var expectedSlot: Int?
    @ObservationIgnored private var memoryGeneration = 0

    var isConnected: Bool { tcp.isConnected || ble.isConnected }

    /// 연결 중에는 수신기가 알려 주는 밴드 이름(VHF, 31M …), 아니면 앱의 밴드 이름.
    /// 연결 중에는 수신기가 알려 주는 모드, 아니면 앱의 모드.
    var modeLabel: String { isConnected && !deviceMode.isEmpty ? deviceMode : mode }

    var bandLabel: String { isConnected && !deviceBandName.isEmpty ? deviceBandName : band.rawValue }

    struct LogEntry: Identifiable {
        enum Direction { case tx, rx }
        let id = UUID()
        let date = Date()
        let direction: Direction
        let text: String
    }

    // 명령 합치기 / 상태 되먹임 억제용
    // 주파수 적용 확인: 보낸 목표가 상태 줄에 반영될 때까지 오래된 상태 줄로 표시를 덮어쓰지 않습니다.
    @ObservationIgnored private var tuneTarget: Int?
    @ObservationIgnored private var tuneDeadline = Date.distantPast
    @ObservationIgnored private var verifyTask: Task<Void, Never>?
    @ObservationIgnored private var seekTask: Task<Void, Never>?
    @ObservationIgnored private var lastStatusAt = Date.distantPast
    @ObservationIgnored private var useEncoderTuning = false
    @ObservationIgnored private var lastLocalVolume = Date.distantPast
    @ObservationIgnored private var pendingFrequency: Int?
    @ObservationIgnored private var pendingVolume: Int?
    @ObservationIgnored private var sendTask: Task<Void, Never>?
    @ObservationIgnored private var deviceVolume = 0
    @ObservationIgnored private var preMuteVolume = 24
    @ObservationIgnored private var statusSeen = false
    @ObservationIgnored private var messageTask: Task<Void, Never>?
    @ObservationIgnored private var gotoTask: Task<Void, Never>?

    init() {
        for t in [ble as RadioTransport, tcp as RadioTransport] {
            t.onLine = { [weak self] line in self?.handle(line: line) }
            t.onConnected = { [weak self] in self?.linkDidConnect() }
            t.onDisconnected = { [weak self] in
                self?.statusSeen = false
                self?.tuneTarget = nil
                self?.verifyTask?.cancel()
                self?.stopSeek()
            }
            t.onSend = { [weak self] text in self?.record(.tx, text) }
        }
        ble.resumeIfPossible()
    }

    // MARK: 주파수 / 밴드

    var frequency: Int { frequencies[band] ?? band.defaultFrequency }
    var step: Int { band.steps[stepIndex[band] ?? 0] }
    var mode: String { band.modes[min(modeIndex[band] ?? 0, band.modes.count - 1)] }

    var frequencyText: String {
        band == .fm ? String(format: "%.2f", Double(frequency) / 1000) : "\(frequency)"
    }

    func select(band: Band) { self.band = band }

    func tune(by steps: Int) { setFrequency(frequency + steps * step) }

    /// 사용자가 주파수를 바꾸면 진행 중인 Seek/Scan은 멈춥니다.
    func setFrequency(_ value: Int) {
        if isSeeking { stopSeek() }
        applyFrequency(value)
    }

    private func applyFrequency(_ value: Int) {
        let r = band.range
        let v = min(max(value, r.lowerBound), r.upperBound)
        frequencies[band] = v
        guard isConnected else { return }
        tuneTarget = v
        tuneDeadline = Date().addingTimeInterval(2.5)
        pendingFrequency = v
        flushSoon()
    }

    func setStep(_ value: Int) {
        if let i = band.steps.firstIndex(of: value) { stepIndex[band] = i }
    }

    func setMode(_ value: String) {
        if let i = band.modes.firstIndex(of: value) { modeIndex[band] = i }
    }

    /// 연결 중에는 수신기에 B/b, M/m을 보내고, 결과는 상태 줄로 돌아옵니다.
    func cycleBand(forward: Bool) {
        if isConnected { link.send(forward ? RadioProtocol.nextBand : RadioProtocol.previousBand); return }
        let all = Band.allCases, i = all.firstIndex(of: band) ?? 0
        band = all[(i + (forward ? 1 : all.count - 1)) % all.count]
    }

    func cycleMode(forward: Bool) {
        if isConnected { link.send(forward ? RadioProtocol.nextMode : RadioProtocol.previousMode); return }
        let m = band.modes, i = m.firstIndex(of: mode) ?? 0
        setMode(m[(i + (forward ? 1 : m.count - 1)) % m.count])
    }

    /// 고급 제어용 원시 명령 전송 (연결 중일 때만 동작).
    func send(_ command: String) { link.send(command) }

    // MARK: 스테이션 (연결 중: 수신기 메모리 슬롯, 아니면 앱 프리셋)

    struct Station: Identifiable, Hashable {
        let id: String
        let label: String
        let kHz: Int
        let bandName: String   // 수신기 밴드 이름(연결 중) 또는 앱 밴드 이름
        let mode: String
        let slot: Int?         // 수신기 슬롯 번호 (앱 프리셋이면 nil)
    }

    static func frequencyLabel(kHz: Int, fm: Bool) -> String {
        fm ? String(format: "FM %.1f", Double(kHz) / 1000) : "\(kHz) kHz"
    }

    var stations: [Station] {
        if isConnected {
            return memorySlots.map {
                Station(id: "slot\($0.slot)",
                        label: $0.name.isEmpty ? Self.frequencyLabel(kHz: $0.frequencyKHz, fm: $0.mode == "FM") : $0.name,
                        kHz: $0.frequencyKHz, bandName: $0.band, mode: $0.mode, slot: $0.slot)
            }
        }
        return presets.map {
            Station(id: $0.id, label: Self.frequencyLabel(kHz: $0.frequency, fm: $0.band == .fm),
                    kHz: $0.frequency, bandName: $0.band.rawValue, mode: $0.band.modes[0], slot: nil)
        }
    }

    /// 현재 밴드·주파수와 일치하는 스테이션.
    var currentStation: Station? {
        let name = isConnected ? deviceBandName : band.rawValue
        return stations.first { $0.kHz == frequency && $0.bandName == name }
    }

    var isFavorite: Bool { currentStation != nil }

    func select(station s: Station) {
        if isConnected { goTo(s) } else {
            if let b = Band(rawValue: s.bandName) { band = b }
            setFrequency(s.kHz)
        }
    }

    /// 하트: 연결 중이면 수신기 슬롯을 저장/삭제하고, 아니면 앱 프리셋을 저장/삭제합니다.
    func toggleFavorite() {
        if isConnected {
            if let slot = currentStation?.slot, let m = memorySlots.first(where: { $0.slot == slot }) {
                clearMemory(m)
            } else {
                saveToMemory(name: "")
            }
            return
        }
        let p = Preset(band: band, frequency: frequency)
        if let i = presets.firstIndex(of: p) { presets.remove(at: i) } else {
            presets.append(p)
            presets.sort { ($0.band.rawValue, $0.frequency) < ($1.band.rawValue, $1.frequency) }
        }
        Self.savePresets(presets)
    }

    private static let presetsKey = "localPresets"

    private static func loadPresets() -> [Preset] {
        (UserDefaults.standard.stringArray(forKey: presetsKey) ?? []).compactMap {
            let parts = $0.split(separator: ":")
            guard parts.count == 2, let b = Band(rawValue: String(parts[0])), let f = Int(parts[1]) else { return nil }
            return Preset(band: b, frequency: f)
        }
    }

    private static func savePresets(_ list: [Preset]) {
        UserDefaults.standard.set(list.map { "\($0.band.rawValue):\($0.frequency)" }, forKey: presetsKey)
    }

    // MARK: 밴드·모드 선택 (연결 중)

    /// 수신기의 현재 밴드가 `DeviceBand.all`의 몇 번째인지. 표에 없으면 nil.
    var currentDeviceBandIndex: Int? {
        guard isConnected, !deviceBandName.isEmpty else { return nil }
        return DeviceBand.index(name: deviceBandName, kHz: frequency, mode: deviceMode)
    }

    /// 모드 선택지. FM 밴드는 FM만, 나머지는 AM/LSB/USB입니다.
    var modeChoices: [String] { deviceMode == "FM" ? ["FM"] : ["AM", "LSB", "USB"] }

    /// 목록에서 고른 밴드로 이동합니다. `B`/`b`를 한 칸씩 보내며 상태 줄로 확인합니다.
    func selectBand(index: Int) {
        gotoTask?.cancel()
        gotoTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if currentDeviceBandIndex != index { showMessage(String(localized: "Switching band…")) }
            if await switchBand(to: index) { clearMessage() } else {
                showMessage(String(localized: "Could not switch to band \(DeviceBand.all[index].name)"))
            }
        }
    }

    func selectMode(_ mode: String) {
        gotoTask?.cancel()
        gotoTask = Task { @MainActor [weak self] in await self?.switchMode(to: mode) }
    }

    /// 수신기를 슬롯의 밴드·모드로 옮긴 뒤 주파수를 지정합니다.
    /// `F` 명령은 현재 밴드 안에서만 동작하므로 밴드·모드를 먼저 맞춥니다.
    private func goTo(_ s: Station) {
        gotoTask?.cancel()
        gotoTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard let target = DeviceBand.index(name: s.bandName, kHz: s.kHz, mode: s.mode) else {
                showMessage(String(localized: "Could not switch to band \(s.bandName)"))
                return
            }
            if currentDeviceBandIndex != target { showMessage(String(localized: "Switching band…")) }
            guard await switchBand(to: target) else {
                showMessage(String(localized: "Could not switch to band \(s.bandName)"))
                return
            }
            clearMessage()
            await switchMode(to: s.mode)
            guard !Task.isCancelled else { return }
            frequencies[band] = s.kHz
            tuneTarget = s.kHz
            tuneDeadline = Date().addingTimeInterval(2.5)
            sendTune(s.kHz)
        }
    }

    /// 가까운 방향으로 `B`/`b`를 한 칸씩 보내며, 매번 상태 줄이 바뀔 때까지 기다립니다.
    private func switchBand(to target: Int) async -> Bool {
        let n = DeviceBand.all.count
        var tries = 0
        while !Task.isCancelled, tries < n + 2 {
            guard let current = currentDeviceBandIndex else { return false }
            if current == target { return true }
            let forward = (target - current + n) % n
            let before = "\(deviceBandName)|\(frequency)"
            link.send(forward <= n - forward ? RadioProtocol.nextBand : RadioProtocol.previousBand)
            tries += 1
            await waitUntil(timeout: 1.5) { "\(self.deviceBandName)|\(self.frequency)" != before }
        }
        return currentDeviceBandIndex == target
    }

    private func switchMode(to target: String) async {
        var tries = 0
        while !Task.isCancelled, !deviceMode.isEmpty, deviceMode != target, tries < 4 {
            let before = deviceMode
            link.send(RadioProtocol.nextMode)
            tries += 1
            await waitUntil(timeout: 1.5) { self.deviceMode != before }
        }
    }

    // MARK: Seek / Scan (앱이 한 스텝씩 옮기며 신호 세기를 확인)

    enum SeekSensitivity: String, CaseIterable, Identifiable {
        case strong, normal, weak
        var id: String { rawValue }
        /// 이 값 이상의 RSSI(dBµV)와 SNR(dB)이면 방송국으로 봅니다.
        var rssi: Int { switch self { case .strong: 30; case .normal: 20; case .weak: 10 } }
        var snr: Int { switch self { case .strong: 12; case .normal: 8; case .weak: 3 } }
    }

    var seekSensitivity: SeekSensitivity = .normal
    private(set) var isSeeking = false
    private(set) var isScanning = false

    /// 다음(또는 이전) 방송국까지 한 스텝씩 옮기며 찾고, 찾으면 멈춥니다.
    func seek(forward: Bool) { startSeek(direction: forward ? 1 : -1, scanning: false) }

    /// 방송국을 찾으면 약 4초 머문 뒤 계속 찾습니다. 멈출 때까지 반복합니다.
    func startScan() { startSeek(direction: 1, scanning: true) }

    func stopSeek() {
        seekTask?.cancel()
        seekTask = nil
        isSeeking = false
        isScanning = false
    }

    private func startSeek(direction: Int, scanning: Bool) {
        guard isConnected, deviceFrequencyKHz > 0 else { return }
        stopSeek()
        isSeeking = true
        isScanning = scanning
        seekTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await runSeek(direction: direction, scanning: scanning)
            if !Task.isCancelled { isSeeking = false; isScanning = false; seekTask = nil }
        }
    }

    /// Seek 범위(kHz). FM(VHF)은 방송 대역 87.5–108 MHz만, 그 외에는 수신기 밴드 범위를 씁니다.
    private func seekRange() -> ClosedRange<Int> {
        if deviceBandName == "VHF" { return 87_500...108_000 }
        if let i = currentDeviceBandIndex { return DeviceBand.all[i].minKHz...DeviceBand.all[i].maxKHz }
        return band.range
    }

    private func runSeek(direction: Int, scanning: Bool) async {
        let step = max(self.step, 1)
        let range = seekRange()
        let total = max(1, (range.upperBound - range.lowerBound) / step + 1)
        var f = deviceFrequencyKHz
        var visited = 0
        var foundInPass = false
        while !Task.isCancelled, isConnected {
            f += direction * step
            if f > range.upperBound { f = range.lowerBound } else if f < range.lowerBound { f = range.upperBound }
            let sentAt = Date()
            applyFrequency(f)
            // 새 주파수에서 측정한 상태 줄(전송 후 0.35초 이상 지난 것)을 기다립니다.
            await waitUntil(timeout: 3.0) { self.isClose(self.deviceFrequencyKHz, f) && self.lastStatusAt > sentAt.addingTimeInterval(0.35) }
            guard !Task.isCancelled else { return }
            guard isClose(deviceFrequencyKHz, f) else {
                showMessage(String(localized: "Seek stopped. The receiver did not follow the tuning."))
                return
            }
            visited += 1
            if rssi >= seekSensitivity.rssi, snr >= seekSensitivity.snr {
                foundInPass = true
                if !scanning {
                    showMessage(String(localized: "Station found: \(Self.frequencyLabel(kHz: f, fm: deviceMode == "FM"))"))
                    return
                }
                try? await Task.sleep(for: .seconds(4))
            }
            if visited >= total {
                guard foundInPass else {
                    showMessage(String(localized: "No station found."))
                    return
                }
                visited = 0
                foundInPass = false
            }
        }
    }

    // MARK: 주파수 적용 확인

    private func isClose(_ a: Int, _ b: Int) -> Bool { abs(a - b) <= (deviceMode == "FM" ? 5 : 1) }

    /// 기본은 `F<Hz>`(절대 지정). 앞서 `F`가 먹지 않았다면 엔코더 회전(`R`/`r`)으로 같은 만큼 움직입니다.
    private func sendTune(_ target: Int) {
        let before = deviceFrequencyKHz
        if useEncoderTuning, let steps = encoderSteps(to: target) {
            link.send(steps)
        } else {
            link.send(RadioProtocol.setFrequency(kHz: target))
        }
        verifyTask?.cancel()
        verifyTask = Task { @MainActor [weak self] in await self?.verifyTune(target, before: before) }
    }

    /// 현재 수신기 주파수에서 목표까지 필요한 엔코더 회전 명령. 수신기가 알려 준 스텝을 기준으로 계산합니다.
    private func encoderSteps(to target: Int) -> String? {
        guard let step = RadioProtocol.stepKHz(from: stepText), step > 0 else { return nil }
        let n = Int((Double(target - deviceFrequencyKHz) / step).rounded())
        guard n != 0 else { return nil }
        return String(repeating: n > 0 ? RadioProtocol.encoderUp : RadioProtocol.encoderDown, count: min(abs(n), 300))
    }

    /// 보낸 주파수가 상태 줄에 나타나는지 확인합니다. 안 움직였으면 다른 방식으로 한 번 더 시도하고,
    /// 그래도 안 되면 표시를 수신기 값으로 되돌리며 이유를 알립니다.
    private func verifyTune(_ target: Int, before: Int) async {
        await waitUntil(timeout: 1.4) { self.isClose(self.deviceFrequencyKHz, target) }
        guard !Task.isCancelled else { return }
        if isClose(deviceFrequencyKHz, target) { tuneTarget = nil; return }

        if deviceFrequencyKHz != before {
            // 움직이는 중이면(명령이 밀려 있음) 조금 더 기다립니다.
            await waitUntil(timeout: 2.0) { self.isClose(self.deviceFrequencyKHz, target) }
            guard !Task.isCancelled else { return }
            if isClose(deviceFrequencyKHz, target) { tuneTarget = nil; return }
        } else {
            let alternative = useEncoderTuning ? RadioProtocol.setFrequency(kHz: target) : encoderSteps(to: target)
            if let alternative {
                link.send(alternative)
                await waitUntil(timeout: 1.8) { self.isClose(self.deviceFrequencyKHz, target) }
                guard !Task.isCancelled else { return }
                if isClose(deviceFrequencyKHz, target) {
                    useEncoderTuning.toggle()   // 이제부터는 먹히는 방식을 먼저 씁니다
                    tuneTarget = nil
                    return
                }
            }
        }
        tuneTarget = nil
        if deviceFrequencyKHz > 0 { frequencies[Band.detect(mode: deviceMode, kHz: deviceFrequencyKHz)] = deviceFrequencyKHz }
        showMessage(String(localized: "The receiver did not accept the new frequency. See Advanced → Communication log."))
    }

    private func waitUntil(timeout: Double, _ condition: () -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end, !Task.isCancelled, !condition() {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    // MARK: 메모리 슬롯

    /// 슬롯 목록을 요청합니다. `$` 응답에는 끝 표시가 없어서 1.2초 동안 받은 줄을 모아 한꺼번에 반영합니다.
    /// 읽는 동안에도 기존 목록을 비우지 않아서 화면이 깜빡이지 않습니다.
    /// (수신기는 `#`/`F` 입력을 그대로 되돌려 보내므로(에코), 읽는 시간 밖의 `#` 줄은 슬롯으로 보지 않습니다.)
    func refreshMemory() {
        guard isConnected else { return }
        beginMemoryRead()
        link.send(RadioProtocol.listMemory)
    }

    /// 슬롯 줄을 모으기 시작합니다 (`refreshMemory`가 호출하며, 테스트에서는 직접 호출).
    func beginMemoryRead(window: Double = 1.2) {
        readingMemory = true
        pendingSlots = []
        memoryLoaded = false
        memoryGeneration += 1
        let generation = memoryGeneration
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(window))
            guard let self, readingMemory, generation == memoryGeneration else { return }
            readingMemory = false
            memorySlots = pendingSlots.sorted { $0.slot < $1.slot }
            memoryLoaded = true
            if let expected = expectedSlot {
                expectedSlot = nil
                if !memorySlots.contains(where: { $0.slot == expected }) {
                    showMessage(String(localized: "The receiver did not store the memory slot. See Advanced → Communication log."))
                }
            }
        }
    }

    /// 비어 있는 첫 슬롯(1...99)에 현재 주파수를 저장합니다. 이름은 ASCII 9자까지입니다.
    func saveToMemory(name: String) {
        guard isConnected, !deviceBandName.isEmpty else { return }
        // 목록을 다 받기 전에 저장하면 기존 슬롯을 덮어쓸 수 있어서 먼저 읽습니다.
        guard memoryLoaded else {
            showMessage(String(localized: "Reading memory slots… try again in a moment."))
            if !readingMemory { refreshMemory() }
            return
        }
        let used = Set(memorySlots.map(\.slot))
        guard let slot = (1...99).first(where: { !used.contains($0) }) else {
            showMessage(String(localized: "All 99 memory slots are in use."))
            return
        }
        let n = RadioProtocol.sanitizedMemoryName(name)
        let m = deviceMode.isEmpty ? mode : deviceMode
        link.send(RadioProtocol.setMemorySlot(slot, band: deviceBandName, kHz: frequency, mode: m, name: n.isEmpty ? nil : n))
        // 바로 보여 주고(낙관적 반영), 잠시 뒤 수신기에서 다시 읽어 확인합니다.
        memorySlots.append(MemorySlot(slot: slot, band: deviceBandName, frequencyHz: frequency * 1000, mode: m, name: n))
        memorySlots.sort { $0.slot < $1.slot }
        expectedSlot = slot
        refreshMemoryAfterWrite()
    }

    func clearMemory(_ slot: MemorySlot) {
        link.send(RadioProtocol.clearMemorySlot(slot.slot, band: slot.band, mode: slot.mode))
        memorySlots.removeAll { $0.slot == slot.slot }
        refreshMemoryAfterWrite()
    }

    private func refreshMemoryAfterWrite() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            self?.refreshMemory()
        }
    }

    // MARK: 볼륨

    func setVolume(_ value: Int) {
        let v = min(max(value, 0), 63)
        volume = v
        isMuted = v == 0
        guard isConnected else { return }
        lastLocalVolume = Date()
        pendingVolume = v
        flushSoon()
    }

    func changeVolume(by delta: Int) { setVolume(volume + delta) }

    func toggleMute() {
        if isConnected {
            if volume > 0 { preMuteVolume = volume; setVolume(0) } else { setVolume(max(preMuteVolume, 1)) }
        } else {
            isMuted.toggle()
        }
    }

    /// 신호 세기 0...1 (이퀄라이저 연출용)
    var signalLevel: Double { min(1, Double(rssi) / 60) }

    // MARK: 송신 합치기 (드래그 중 명령이 쏟아지지 않도록 120ms마다 최신 값만 전송)

    private func flushSoon() {
        guard sendTask == nil else { return }
        sendTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let self else { return }
            sendTask = nil
            if let f = pendingFrequency {
                pendingFrequency = nil
                sendTune(f)
            }
            if let v = pendingVolume {
                pendingVolume = nil
                link.send(RadioProtocol.volumeCommand(delta: v - deviceVolume))
                deviceVolume = v
            }
        }
    }

    // MARK: 수신

    private func linkDidConnect() {
        statusSeen = false
        // 재연결 직후에는 상태 로그가 꺼져 있습니다. t는 토글이라 상태 줄이 안 올 때만 보냅니다.
        Task { @MainActor [weak self] in
            for delay in [0.6, 2.0] {
                try? await Task.sleep(for: .seconds(delay))
                guard let self, link.isConnected, !statusSeen else { return }
                link.send(RadioProtocol.toggleLog)
            }
        }
    }

    // MARK: 통신 로그 / 수신기 메시지

    func clearLog() { log.removeAll() }

    private func record(_ direction: LogEntry.Direction, _ text: String) {
        let shown = text.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "⏎")
        log.append(LogEntry(direction: direction, text: shown))
        if log.count > 300 { log.removeFirst(log.count - 300) }
    }

    private func clearMessage() {
        messageTask?.cancel()
        deviceMessage = nil
    }

    private func showMessage(_ text: String) {
        deviceMessage = text
        messageTask?.cancel()
        messageTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            self?.deviceMessage = nil
        }
    }

    func handle(line: String) {
        if let message = RadioProtocol.errorMessage(line) {
            record(.rx, line)
            showMessage(message)
            return
        }
        if RadioProtocol.looksLikeStatus(line) {
            // 상태 줄은 0.5초마다 오므로 로그에는 마지막 한 줄만 둡니다.
            let first = !statusSeen
            statusSeen = true
            lastStatusLine = line
            lastStatusAt = Date()
            statusCount += 1
            if let st = RadioProtocol.parseStatus(line) { apply(st) }
            if first { refreshMemory() }   // 연결 직후 한 번 수신기 슬롯을 읽어 스테이션 목록으로 씁니다
            return
        }
        record(.rx, line)
        if readingMemory, let slot = RadioProtocol.parseMemorySlot(line) {
            pendingSlots.removeAll { $0.slot == slot.slot }
            pendingSlots.append(slot)
        }
    }

    private func apply(_ st: RadioStatus) {
        let kHz = st.frequencyKHz
        let newBand = Band.detect(mode: st.mode, kHz: kHz)
        band = newBand
        deviceFrequencyKHz = kHz
        if let target = tuneTarget {
            if isClose(kHz, target) {
                tuneTarget = nil
                frequencies[newBand] = kHz
            } else if Date() > tuneDeadline.addingTimeInterval(8) {
                tuneTarget = nil          // 확인 작업이 끝나지 않았을 때를 위한 안전장치
            }
            // 그 외에는 아직 이전 값을 보내는 중이므로 표시를 덮어쓰지 않습니다.
        } else {
            frequencies[newBand] = kHz
        }
        if let i = newBand.modes.firstIndex(of: st.mode) { modeIndex[newBand] = i }
        deviceBandName = st.bandName
        deviceMode = st.mode
        deviceVolume = st.volume
        if Date().timeIntervalSince(lastLocalVolume) > 0.8 {
            volume = st.volume
            isMuted = st.volume == 0
        }
        rssi = st.rssi
        snr = st.snr
        voltage = st.voltage
        bandwidthText = st.bandwidthText
        stepText = st.stepText
        agcIndex = st.agcIndex
    }
}
