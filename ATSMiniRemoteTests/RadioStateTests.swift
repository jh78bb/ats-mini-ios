import XCTest
@testable import ATSMiniRemote

/// 수신기가 보낸 줄을 RadioState가 화면 상태로 반영하는지 확인합니다 (실기기 없이).
final class RadioStateTests: XCTestCase {
    // 펌웨어 v2.45 형식: 버전,주파수,BFO,보정,밴드,모드,스텝,대역폭,AGC,볼륨,RSSI,SNR,커패시터,전압,시퀀스
    private let fm = "245,10170,0,0,VHF,FM,100k,110k,2,24,42,18,100,4.05,7"
    private let am = "245,9620,0,0,31M,AM,5k,3k,0,30,20,9,10,3.91,8"

    func testStatusLineUpdatesBandModeAndFrequency() {
        let radio = RadioState()
        radio.handle(line: fm)
        XCTAssertEqual(radio.deviceBandName, "VHF")
        XCTAssertEqual(radio.deviceMode, "FM")
        XCTAssertEqual(radio.band, .fm)
        XCTAssertEqual(radio.frequency, 101_700)
        XCTAssertEqual(radio.bandwidthText, "110k")
        XCTAssertEqual(radio.statusCount, 1)

        radio.handle(line: am)      // 장치에서 밴드/모드를 바꾸면 앱 표시도 따라가야 합니다
        XCTAssertEqual(radio.deviceBandName, "31M")
        XCTAssertEqual(radio.deviceMode, "AM")
        XCTAssertEqual(radio.band, .sw)
        XCTAssertEqual(radio.frequency, 9_620)
        XCTAssertEqual(radio.volume, 30)
        XCTAssertEqual(radio.rssi, 20)
        XCTAssertEqual(radio.statusCount, 2)
    }

    func testErrorLineShowsMessage() {
        let radio = RadioState()
        radio.handle(line: "Error: Frequency is out of range for the current band")
        XCTAssertEqual(radio.deviceMessage, "Frequency is out of range for the current band")
    }

    func testMemorySlotLinesAreOnlyReadWhileReading() async throws {
        let radio = RadioState()
        // 수신기는 `#...` 입력을 그대로 되돌려 보냅니다(에코). 읽는 중이 아니면 슬롯으로 보지 않습니다.
        radio.handle(line: "#03,VHF,101700000,FM")
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(radio.memorySlots.isEmpty)

        radio.beginMemoryRead(window: 0.2)
        radio.handle(line: "#02,MW,1134000,AM,KBS 1")
        radio.handle(line: "#01,VHF,107900000,FM")
        XCTAssertTrue(radio.memorySlots.isEmpty, "다 받기 전에는 기존 목록을 건드리지 않습니다")
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(radio.memorySlots.map(\.slot), [1, 2])
        XCTAssertEqual(radio.memorySlots[1].name, "KBS 1")
        XCTAssertTrue(radio.memoryLoaded)
    }

    func testNoDemoPresetsByDefault() {
        XCTAssertTrue(RadioState().presets.isEmpty)
    }

    func testDeviceBandTableMatchesFirmware() {
        XCTAssertEqual(DeviceBand.all.count, 28)
        XCTAssertEqual(DeviceBand.all.first?.name, "VHF")
        XCTAssertEqual(DeviceBand.all.last?.name, "CB")
        XCTAssertEqual(DeviceBand.all[0].rangeLabel, "64–108 MHz")
        XCTAssertEqual(DeviceBand.all[17].rangeLabel, "150–1800 kHz")   // MW1
        XCTAssertEqual(DeviceBand.all[1].rangeLabel, "150 kHz–30 MHz")  // ALL
    }

    func testBandIndexDisambiguatesDuplicateNames() {
        XCTAssertEqual(DeviceBand.index(name: "VHF", kHz: 101_700, mode: "FM"), 0)
        XCTAssertEqual(DeviceBand.index(name: "15M", kHz: 18_950, mode: "AM"), 4)    // 방송 15M
        XCTAssertEqual(DeviceBand.index(name: "15M", kHz: 21_225, mode: "USB"), 24)  // 아마추어 15M
        XCTAssertNil(DeviceBand.index(name: "XYZ", kHz: 1, mode: "AM"))
    }

    func testCurrentBandIndexFollowsStatusLine() {
        let radio = RadioState()
        radio.handle(line: fm)
        // 연결되지 않은 상태에서는 목록 선택을 쓰지 않으므로 nil
        XCTAssertNil(radio.currentDeviceBandIndex)
        XCTAssertEqual(radio.modeChoices, ["FM"])
        radio.handle(line: am)
        XCTAssertEqual(radio.modeChoices, ["AM", "LSB", "USB"])
    }
}
