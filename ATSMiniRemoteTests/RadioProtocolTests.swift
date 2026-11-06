import XCTest
@testable import ATSMiniRemote

final class RadioProtocolTests: XCTestCase {
    // 필드: 버전, 주파수, BFO, 보정, 밴드, 모드, 스텝, 대역폭, AGC, 볼륨, RSSI, SNR, 커패시터, ADC, 시퀀스
    func testParsesFMStatusLine() throws {
        let st = try XCTUnwrap(RadioProtocol.parseStatus("245,10170,0,0,VHF,FM,100k,110k,2,24,42,18,100,4.05,7"))
        XCTAssertEqual(st.version, 245)
        XCTAssertEqual(st.bandName, "VHF")
        XCTAssertEqual(st.stepText, "100k")
        XCTAssertEqual(st.bandwidthText, "110k")
        XCTAssertEqual(st.frequencyKHz, 101_700)   // FM은 10 kHz 단위
        XCTAssertEqual(st.mode, "FM")
        XCTAssertEqual(st.volume, 24)
        XCTAssertEqual(st.rssi, 42)
        XCTAssertEqual(st.snr, 18)
        XCTAssertEqual(st.voltage, 4.05, accuracy: 0.0001)   // 펌웨어는 전압을 %.2f 소수로 보냅니다
    }

    func testParsesAMStatusLineInKHz() throws {
        let st = try XCTUnwrap(RadioProtocol.parseStatus("245,9620,0,0,31M,AM,1k,3k,0,30,20,9,10,3.91,255\r"))
        XCTAssertEqual(st.frequencyKHz, 9_620)
        XCTAssertEqual(Band.detect(mode: st.mode, kHz: st.frequencyKHz), .sw)
    }

    func testRejectsNonStatusLines() {
        XCTAssertNil(RadioProtocol.parseStatus(""))
        XCTAssertNil(RadioProtocol.parseStatus("#01,VHF,107900000,FM,Radio One"))
        XCTAssertNil(RadioProtocol.parseStatus("245,10170,0,0,VHF,XX,100k,110k,2,24,42,18,100,4.05,7"))
    }

    func testCommands() {
        XCTAssertEqual(RadioProtocol.setFrequency(kHz: 107_900), "F107900000\n")
        XCTAssertEqual(RadioProtocol.volumeCommand(delta: 3), "VVV")
        XCTAssertEqual(RadioProtocol.volumeCommand(delta: -2), "vv")
        XCTAssertEqual(RadioProtocol.volumeCommand(delta: 0), "")
    }

    func testBandDetection() {
        XCTAssertEqual(Band.detect(mode: "FM", kHz: 101_700), .fm)
        XCTAssertEqual(Band.detect(mode: "AM", kHz: 198), .lw)
        XCTAssertEqual(Band.detect(mode: "AM", kHz: 1_134), .mw)
        XCTAssertEqual(Band.detect(mode: "LSB", kHz: 7_100), .sw)
    }
}

final class RadioProtocolAdvancedTests: XCTestCase {
    func testStatusAGCAndLegacyADCVoltage() throws {
        let st = try XCTUnwrap(RadioProtocol.parseStatus("245,10170,0,0,VHF,FM,100k,Auto,5,24,42,18,100,2400,7"))
        XCTAssertEqual(st.agcIndex, 5)
        XCTAssertEqual(st.bandwidthText, "Auto")
        XCTAssertEqual(st.voltage, 2400 * 1.702 / 1000, accuracy: 0.0001)   // 문서가 설명한 ADC 값 형식도 허용
    }

    func testStatusLineAndErrorDetection() {
        XCTAssertTrue(RadioProtocol.looksLikeStatus("245,10170,0,0,VHF,FM,100k,110k,2,24,42,18,100,4.05,7"))
        XCTAssertFalse(RadioProtocol.looksLikeStatus("#01,VHF,107900000,FM,Radio One"))
        XCTAssertFalse(RadioProtocol.looksLikeStatus("Error: Invalid memory slot number"))
        XCTAssertEqual(RadioProtocol.errorMessage("Error: Frequency is out of range for the current band"),
                       "Frequency is out of range for the current band")
        XCTAssertNil(RadioProtocol.errorMessage("245,10170"))
    }

    func testParsesMemorySlot() throws {
        let m = try XCTUnwrap(RadioProtocol.parseMemorySlot("#01,VHF,107900000,FM,Radio One"))
        XCTAssertEqual(m, MemorySlot(slot: 1, band: "VHF", frequencyHz: 107_900_000, mode: "FM", name: "Radio One"))
        XCTAssertEqual(m.frequencyKHz, 107_900)
        XCTAssertEqual(RadioProtocol.parseMemorySlot("#02,MW,1134000,AM")?.name, "")
        XCTAssertNil(RadioProtocol.parseMemorySlot("#03,VHF,0,FM,Empty"))      // 빈 슬롯
        XCTAssertNil(RadioProtocol.parseMemorySlot("245,10170,0,0,VHF,FM,100k,110k,2,24,42,18,100,4.05,7"))
    }

    func testMemoryCommands() {
        XCTAssertEqual(RadioProtocol.setMemorySlot(1, band: "VHF", kHz: 107_900, mode: "FM", name: "Radio One"),
                       "#01,VHF,107900000,FM,Radio One\n")
        XCTAssertEqual(RadioProtocol.setMemorySlot(12, band: "MW", kHz: 1_134, mode: "AM", name: nil),
                       "#12,MW,1134000,AM\n")
        XCTAssertEqual(RadioProtocol.clearMemorySlot(5, band: "VHF", mode: "FM"), "#05,VHF,0,FM\n")
    }

    func testMemoryNameSanitizing() {
        XCTAssertEqual(RadioProtocol.sanitizedMemoryName("KBS, Classic FM 한글"), "KBS Class")
        XCTAssertEqual(RadioProtocol.sanitizedMemoryName("a,b"), "ab")
    }

    func testSSBFrequencyIncludesBFO() throws {
        // 문서: SSB 표시 주파수(Hz) = 주파수(kHz)×1000 + BFO(Hz)
        let lsb = try XCTUnwrap(RadioProtocol.parseStatus("245,7096,4200,0,40M,LSB,1k,2.2k,0,20,30,10,50,3.95,1"))
        XCTAssertEqual(lsb.frequencyKHz, 7_100)
        let usb = try XCTUnwrap(RadioProtocol.parseStatus("245,14090,-1300,0,20M,USB,1k,2.2k,0,20,30,10,50,3.95,2"))
        XCTAssertEqual(usb.frequencyKHz, 14_089)
    }

    func testStepTextToKHz() {
        XCTAssertEqual(RadioProtocol.stepKHz(from: "100k"), 100)
        XCTAssertEqual(RadioProtocol.stepKHz(from: "9k"), 9)
        XCTAssertEqual(RadioProtocol.stepKHz(from: "25"), 0.025)    // 단위가 없으면 Hz
        XCTAssertNil(RadioProtocol.stepKHz(from: "Auto"))
    }
}
