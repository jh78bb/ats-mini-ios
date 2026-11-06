import Foundation

/// ATS Mini "Ad hoc" 원격 제어 프로토콜. USB 시리얼, BLE, TCP가 같은 프로토콜을 씁니다.
/// 참고: https://esp32-si4732.github.io/ats-mini/remote.html
struct RadioStatus: Equatable {
    var version: Int          // 201 = v2.01
    var frequency: Int        // FM = 10 kHz 단위, AM/SSB = 1 kHz 단위
    var bfo: Int              // SSB, Hz
    var bandName: String
    var mode: String          // FM / LSB / USB / AM
    var volume: Int           // 0...63 (0 = 음소거)
    var rssi: Int             // 0...127 dBµV
    var snr: Int              // 0...127 dB
    var stepText: String      // 수신기가 알려 주는 스텝 표기 (예: 100k)
    var bandwidthText: String // 수신기가 알려 주는 대역폭 표기 (예: 2.5k)
    var agcIndex: Int         // 수신기의 AGC/감쇠기 인덱스
    var voltage: Double       // 배터리 전압(V)

    /// 항상 kHz 정수로 환산한 주파수. SSB는 문서대로 `주파수(kHz)×1000 + BFO(Hz)`를 반영합니다.
    var frequencyKHz: Int {
        switch mode {
        case "FM": return frequency * 10
        case "LSB", "USB": return Int((Double(frequency) + Double(bfo) / 1000).rounded())
        default: return frequency
        }
    }
}

/// 수신기의 메모리 슬롯 하나.
struct MemorySlot: Identifiable, Equatable {
    var slot: Int
    var band: String          // 수신기의 밴드 이름 (예: VHF)
    var frequencyHz: Int
    var mode: String
    var name: String
    var id: Int { slot }
    var frequencyKHz: Int { frequencyHz / 1000 }
}

enum RadioProtocol {
    /// 모니터(로그) 한 줄을 파싱합니다. 쉼표로 구분된 15개 필드이며, 형식이 다르면 nil입니다.
    /// 0 버전, 1 주파수, 2 BFO, 3 BFO 보정, 4 밴드 이름, 5 모드, 6 스텝 표기, 7 대역폭 표기, 8 AGC 인덱스,
    /// 9 볼륨, 10 RSSI, 11 SNR, 12 안테나 커패시터, 13 전압(소수, `%.2f`), 14 시퀀스 번호
    /// 펌웨어 v2.45 소스 기준입니다. 문서는 13번을 ADC 값이라고 적지만 실제로는 전압을 소수로 보냅니다.
    /// (20보다 크면 ADC 값으로 보고 `× 1.702 / 1000`으로 환산합니다.)
    static func parseStatus(_ line: String) -> RadioStatus? {
        let f = line.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard f.count >= 15,
              let version = Int(f[0]), let freq = Int(f[1]), let bfo = Int(f[2]),
              let agc = Int(f[8]), let volume = Int(f[9]), let rssi = Int(f[10]), let snr = Int(f[11]),
              let rawVoltage = Double(f[13]) else { return nil }
        let mode = f[5].uppercased()
        guard ["FM", "AM", "LSB", "USB"].contains(mode) else { return nil }
        return RadioStatus(version: version, frequency: freq, bfo: bfo, bandName: f[4], mode: mode,
                           volume: volume, rssi: rssi, snr: snr,
                           stepText: f[6], bandwidthText: f[7], agcIndex: agc,
                           voltage: rawVoltage > 20 ? rawVoltage * 1.702 / 1000 : rawVoltage)
    }

    /// 상태 줄처럼 보이는지(쉼표 14개 이상) 판단합니다. 파싱에 실패해도 로그가 켜져 있다는 증거로 씁니다.
    static func looksLikeStatus(_ line: String) -> Bool {
        !line.hasPrefix("#") && line.reduce(0) { $1 == "," ? $0 + 1 : $0 } >= 14
    }

    /// 수신기가 돌려주는 오류 줄(`Error: Frequency is out of range for the current band`)의 메시지.
    static func errorMessage(_ line: String) -> String? {
        guard line.hasPrefix("Error:") else { return nil }
        return line.dropFirst("Error:".count).trimmingCharacters(in: .whitespaces)
    }

    /// `F<Hz>` 주파수 직접 지정. CR/LF로 끝나야 합니다. 현재 밴드 범위 안이어야 합니다.
    static func setFrequency(kHz: Int) -> String { "F\(kHz * 1000)\n" }

    /// 볼륨 변화량만큼 `V`(올림) 또는 `v`(내림)를 반복합니다.
    static func volumeCommand(delta: Int) -> String {
        String(repeating: delta >= 0 ? "V" : "v", count: min(abs(delta), 63))
    }

    // 고급 제어 (대문자 = 올림/다음, 소문자 = 내림/이전)
    static let bandwidthNext = "W", bandwidthPrevious = "w"
    static let agcUp = "A", agcDown = "a"
    static let calibrationUp = "I", calibrationDown = "i"
    static let sleepOn = "O", sleepOff = "o"
    static let encoderUp = "R", encoderDown = "r"
    static let encoderClick = "e", encoderShortPress = "E"

    /// 메모리 슬롯 저장. 이름은 인쇄 가능한 ASCII 9자까지이고 쉼표는 쓸 수 없습니다.
    /// 예: `#01,VHF,107900000,FM,Radio One`. 주파수를 0으로 보내면 슬롯이 지워집니다.
    static func setMemorySlot(_ slot: Int, band: String, kHz: Int, mode: String, name: String?) -> String {
        var cmd = String(format: "#%02d,%@,%d,%@", slot, band, kHz * 1000, mode)
        if let name { cmd += "," + sanitizedMemoryName(name) }
        return cmd + "\n"
    }

    static func clearMemorySlot(_ slot: Int, band: String, mode: String) -> String {
        String(format: "#%02d,%@,0,%@\n", slot, band, mode)
    }

    static func sanitizedMemoryName(_ name: String) -> String {
        String(name.unicodeScalars
            .filter { $0.isASCII && $0.value >= 0x20 && $0.value < 0x7F && $0 != "," }
            .prefix(9).map(Character.init))
    }

    /// `$` 명령 응답 한 줄(`#01,VHF,107900000,FM,Radio One`)을 파싱합니다.
    static func parseMemorySlot(_ line: String) -> MemorySlot? {
        guard line.hasPrefix("#") else { return nil }
        let f = line.dropFirst().split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard f.count >= 4, let slot = Int(f[0]), let hz = Int(f[2]), hz > 0 else { return nil }
        return MemorySlot(slot: slot, band: f[1], frequencyHz: hz, mode: f[3].uppercased(),
                          name: f.dropFirst(4).joined(separator: ","))
    }

    /// 수신기가 알려 준 스텝 표기(`100k`, `9k`, `25` 등)를 kHz로 바꿉니다. 단위가 없으면 Hz로 봅니다.
    static func stepKHz(from text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        if t.hasSuffix("k") { return Double(t.dropLast()) }
        if let hz = Double(t) { return hz / 1000 }
        return nil
    }

    static let toggleLog = "t"
    static let nextBand = "B", previousBand = "b"
    static let nextMode = "M", previousMode = "m"
    static let listMemory = "$"
}

extension Band {
    /// 장치가 알려 준 모드와 주파수(kHz)로 앱의 밴드를 추정합니다.
    static func detect(mode: String, kHz: Int) -> Band {
        if mode == "FM" { return .fm }
        if kHz < 520 { return .lw }
        if kHz < 1_800 { return .mw }
        return .sw
    }
}
