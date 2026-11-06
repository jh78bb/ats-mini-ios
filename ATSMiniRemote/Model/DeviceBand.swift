import Foundation

/// ATS Mini 펌웨어(v2.45)의 `bands[]` 표. 수신기에는 밴드 목록을 알려 주는 명령이 없어서 소스의 표를 그대로 옮겼습니다.
/// 순서가 곧 `B`(다음 밴드)가 넘어가는 순서입니다. 다른 펌웨어/포크는 표가 다를 수 있습니다.
struct DeviceBand: Identifiable, Equatable {
    let index: Int
    let name: String
    let minKHz: Int
    let maxKHz: Int
    let mode: String          // 밴드를 처음 열 때의 기본 모드
    let summary: String       // 밴드 설명(영문). 번역은 Localizable.xcstrings의 같은 문장을 키로 씁니다.
    var id: Int { index }

    /// 예: `64–108 MHz`, `150–1800 kHz`
    var rangeLabel: String {
        func mhz(_ k: Int) -> String { k % 1000 == 0 ? "\(k / 1000)" : String(format: "%g", Double(k) / 1000) }
        if maxKHz < 3000 { return "\(minKHz)–\(maxKHz) kHz" }
        if minKHz < 1000 { return "\(minKHz) kHz–\(mhz(maxKHz)) MHz" }   // ALL: 150 kHz–30 MHz
        return "\(mhz(minKHz))–\(mhz(maxKHz)) MHz"
    }

    static let all: [DeviceBand] = [
        ("VHF", 64000, 108000, "FM", "FM broadcast band. Music and talk radio, usually 87.5–108 MHz."),
        ("ALL", 150, 30000, "AM", "Everything from long wave to shortwave (150 kHz–30 MHz) in one band. Tune anywhere with the dial."),
        ("11M", 25600, 26100, "AM", "Shortwave broadcast, 11 m. Usually quiet; opens only when solar activity is high."),
        ("13M", 21500, 21900, "AM", "Shortwave broadcast, 13 m. Daytime long-distance international stations."),
        ("15M", 18900, 19100, "AM", "Shortwave broadcast, 15 m. Daytime long-distance international stations."),
        ("16M", 17400, 18100, "AM", "Shortwave broadcast, 16 m. Daytime international broadcasts."),
        ("19M", 15100, 15900, "AM", "Shortwave broadcast, 19 m. A popular daytime and evening international band."),
        ("22M", 13500, 13900, "AM", "Shortwave broadcast, 22 m. Daytime international broadcasts."),
        ("25M", 11000, 13000, "AM", "Shortwave broadcast, 25 m. Good from late morning into the evening."),
        ("31M", 9000, 11000, "AM", "Shortwave broadcast, 31 m. One of the busiest bands, usable day and night."),
        ("41M", 7000, 9000, "AM", "Shortwave broadcast, 41 m. Best in the evening and at night."),
        ("49M", 5000, 7000, "AM", "Shortwave broadcast, 49 m. Popular for night-time regional and international stations."),
        ("60M", 4000, 5100, "AM", "Shortwave broadcast, 60 m (tropical band). Night-time, often regional stations."),
        ("75M", 3500, 4000, "AM", "Shortwave broadcast, 75 m. Night-time stations; shares space with amateur radio."),
        ("90M", 3000, 3500, "AM", "Shortwave broadcast, 90 m (tropical band). Night-time regional stations."),
        ("MW3", 1700, 3500, "AM", "A wide slice above medium wave: amateur 160 m, marine and other utility stations (AM)."),
        ("MW2", 495, 1701, "AM", "Medium wave (AM) broadcast band, 495–1701 kHz. Local and regional AM radio, best at night."),
        ("MW1", 150, 1800, "AM", "Wide medium-wave range including the long-wave edge (150–1800 kHz). AM radio and beacons."),
        ("160M", 1800, 2000, "LSB", "Amateur radio 160 m. Voice and data in lower sideband (LSB), best at night."),
        ("80M", 3500, 4000, "LSB", "Amateur radio 80 m. Voice in lower sideband (LSB), evening and night nets."),
        ("40M", 7000, 7300, "LSB", "Amateur radio 40 m. Voice in lower sideband (LSB), active day and night."),
        ("30M", 10000, 10200, "LSB", "Amateur radio 30 m. Mostly Morse code and digital modes, lower sideband (LSB)."),
        ("20M", 14000, 14400, "USB", "Amateur radio 20 m. The classic long-distance (DX) band in upper sideband (USB), mostly daytime."),
        ("17M", 18000, 18200, "USB", "Amateur radio 17 m. Quieter long-distance (DX) band in upper sideband (USB)."),
        ("15M", 21000, 21500, "USB", "Amateur radio 15 m. Daytime long-distance (DX) in upper sideband (USB)."),
        ("12M", 24800, 25000, "USB", "Amateur radio 12 m. Daytime long-distance (DX) when solar activity is good, upper sideband (USB)."),
        ("10M", 28000, 29700, "USB", "Amateur radio 10 m. Opens in high solar activity; voice in upper sideband (USB)."),
        ("CB", 25000, 28000, "AM", "Citizens’ band around 27 MHz (25–28 MHz range). Short-range hobby and trade voice in AM."),
    ].enumerated().map {
        DeviceBand(index: $0.offset, name: $0.element.0, minKHz: $0.element.1, maxKHz: $0.element.2, mode: $0.element.3, summary: $0.element.4)
    }

    /// 수신기가 알려 준 밴드 이름으로 표의 항목을 찾습니다. `15M`처럼 이름이 겹치면 현재 주파수와 모드로 구분합니다.
    static func index(name: String, kHz: Int, mode: String) -> Int? {
        let same = all.filter { $0.name == name }
        if same.count <= 1 { return same.first?.index }
        return (same.first { ($0.minKHz...$0.maxKHz).contains(kHz) && $0.mode == mode }
                ?? same.first { ($0.minKHz...$0.maxKHz).contains(kHz) }
                ?? same.first)?.index
    }
}
