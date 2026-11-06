import CoreBluetooth
import Observation

struct DiscoveredDevice: Identifiable, Equatable {
    let id: UUID
    var name: String
    var rssi: Int
}

/// ATS Mini와의 BLE 연결. Nordic UART Service(`6E400001-…`)로 한 글자 명령을 쓰고 상태 줄을 받습니다.
/// 특성(characteristic) UUID는 문서에 없어서 속성(notify / write)으로 찾습니다.
@Observable
final class BLERadioLink: NSObject, RadioTransport {
    enum BluetoothState { case unknown, unsupported, unauthorized, poweredOff, ready }

    static let serviceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    private static let lastIDKey = "lastPeripheralID"

    private(set) var bluetooth: BluetoothState = .unknown
    private(set) var linkState: LinkState = .disconnected
    private(set) var devices: [DiscoveredDevice] = []
    private(set) var isScanning = false
    /// 서비스 UUID 필터 없이 이름 있는 모든 BLE 기기를 보여줍니다 (광고에 서비스가 없는 경우 대비).
    var scanAll = false { didSet { if isScanning { restartScan() } } }

    @ObservationIgnored var onLine: ((String) -> Void)?
    @ObservationIgnored var onConnected: (() -> Void)?
    @ObservationIgnored var onDisconnected: (() -> Void)?
    @ObservationIgnored var onSend: ((String) -> Void)?

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var found: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var active: CBPeripheral?
    @ObservationIgnored private var writeChar: CBCharacteristic?
    @ObservationIgnored private var lines = LineBuffer()
    @ObservationIgnored private var wantConnected = false
    @ObservationIgnored private var wantScan = false

    private func prepare() {
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) }
    }

    /// 앱 시작 시: 이전에 연결한 기기가 있으면 자동으로 다시 연결을 시도합니다.
    func resumeIfPossible() {
        guard UserDefaults.standard.string(forKey: Self.lastIDKey) != nil else { return }
        wantConnected = true
        prepare()
    }

    // MARK: 검색 / 연결

    func startScan() {
        wantScan = true
        prepare()
        beginScanIfReady()
    }

    func stopScan() {
        wantScan = false
        central?.stopScan()
        isScanning = false
    }

    private func restartScan() {
        central?.stopScan()
        devices.removeAll()
        beginScanIfReady()
    }

    private func beginScanIfReady() {
        guard wantScan, let central, central.state == .poweredOn else { return }
        central.scanForPeripherals(withServices: scanAll ? nil : [Self.serviceUUID],
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        isScanning = true
    }

    func connect(_ device: DiscoveredDevice) {
        guard let p = found[device.id], let central else { return }
        stopScan()
        wantConnected = true
        UserDefaults.standard.set(device.id.uuidString, forKey: Self.lastIDKey)
        open(p, central: central)
    }

    private func open(_ p: CBPeripheral, central: CBCentralManager) {
        active = p
        p.delegate = self
        linkState = .connecting(p.name ?? "ATS-Mini")
        central.connect(p)
    }

    func disconnect() {
        wantConnected = false
        UserDefaults.standard.removeObject(forKey: Self.lastIDKey)
        if let p = active { central?.cancelPeripheralConnection(p) }
        reset()
    }

    private func reset() {
        let was = isConnected
        active = nil
        writeChar = nil
        lines.reset()
        linkState = .disconnected
        if was { onDisconnected?() }
    }

    private func reconnectLast() {
        guard wantConnected, active == nil, let central,
              let s = UserDefaults.standard.string(forKey: Self.lastIDKey), let id = UUID(uuidString: s),
              let p = central.retrievePeripherals(withIdentifiers: [id]).first else { return }
        found[id] = p
        open(p, central: central)
    }

    // MARK: 송신

    func send(_ text: String) {
        guard let p = active, let c = writeChar, let data = text.data(using: .utf8) else { return }
        onSend?(text)
        let type: CBCharacteristicWriteType = c.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        let size = max(20, p.maximumWriteValueLength(for: type))
        var offset = 0
        while offset < data.count {
            p.writeValue(data.subdata(in: offset..<min(offset + size, data.count)), for: c, type: type)
            offset += size
        }
    }

    // MARK: 수신 (줄 단위)

    private func receive(_ data: Data) {
        for line in lines.append(data) { onLine?(line) }
    }
}

extension BLERadioLink: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            bluetooth = .ready
            reconnectLast()
            beginScanIfReady()
        case .poweredOff: bluetooth = .poweredOff
        case .unauthorized: bluetooth = .unauthorized
        case .unsupported: bluetooth = .unsupported
        default: bluetooth = .unknown
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name
        if scanAll && name == nil { return }
        found[peripheral.identifier] = peripheral
        let d = DiscoveredDevice(id: peripheral.identifier, name: name ?? "ATS-Mini", rssi: RSSI.intValue)
        if let i = devices.firstIndex(where: { $0.id == d.id }) { devices[i] = d } else { devices.append(d) }
        devices.sort { $0.rssi > $1.rssi }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        retryIfWanted(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral === active else { return }
        let was = isConnected
        writeChar = nil
        lines.reset()
        if was { onDisconnected?() }
        retryIfWanted(peripheral)
    }

    /// 사용자가 끊지 않았다면 자동으로 재연결을 계속 시도합니다 (CoreBluetooth의 connect는 기기가 나타날 때까지 대기).
    private func retryIfWanted(_ p: CBPeripheral) {
        if wantConnected, let central {
            open(p, central: central)
        } else {
            reset()
        }
    }
}

extension BLERadioLink: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        peripheral.services?.filter { $0.uuid == Self.serviceUUID }
            .forEach { peripheral.discoverCharacteristics(nil, for: $0) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] {
            if c.properties.contains(.notify) || c.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: c)
            }
            // 알림 전용 특성이 아닌 쓰기 가능 특성을 송신용으로 사용
            if c.properties.contains(.write) || c.properties.contains(.writeWithoutResponse) {
                writeChar = c
            }
        }
        if writeChar != nil {
            linkState = .connected(peripheral.name ?? "ATS-Mini")
            onConnected?()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let data = characteristic.value { receive(data) }
    }
}
