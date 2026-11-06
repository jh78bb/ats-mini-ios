import Foundation
import Network
import Observation

/// Wi-Fi TCP 연결. 수신기의 `Settings → TCP Port → Ad hoc`을 켜면 포트 60000에서 BLE와 같은 프로토콜을 씁니다.
/// 시뮬레이터에는 블루투스가 없으므로 `tools/mock_ats_mini.py`(모의 수신기)와 `127.0.0.1`로도 연결해 볼 수 있습니다.
/// 인증과 암호화가 없으니 믿을 수 있는 네트워크에서만 쓰세요.
@Observable
final class TCPRadioLink: RadioTransport {
    static let defaultPort = 60000
    private static let hostKey = "tcpHost", portKey = "tcpPort"

    private(set) var linkState: LinkState = .disconnected
    var host: String = UserDefaults.standard.string(forKey: TCPRadioLink.hostKey) ?? "atsmini.local"
    var port: String = UserDefaults.standard.string(forKey: TCPRadioLink.portKey) ?? String(TCPRadioLink.defaultPort)

    @ObservationIgnored var onLine: ((String) -> Void)?
    @ObservationIgnored var onConnected: (() -> Void)?
    @ObservationIgnored var onDisconnected: (() -> Void)?
    @ObservationIgnored var onSend: ((String) -> Void)?

    @ObservationIgnored private var connection: NWConnection?
    @ObservationIgnored private var lines = LineBuffer()

    /// 입력한 호스트와 포트로 연결합니다. 포트가 잘못되면 기본 포트를 씁니다.
    func connect() {
        disconnect()
        let h = host.trimmingCharacters(in: .whitespaces)
        guard !h.isEmpty else { return }
        UserDefaults.standard.set(h, forKey: Self.hostKey)
        UserDefaults.standard.set(port, forKey: Self.portKey)
        let p = NWEndpoint.Port(rawValue: UInt16(port) ?? UInt16(Self.defaultPort)) ?? .init(integerLiteral: UInt16(Self.defaultPort))
        let conn = NWConnection(host: NWEndpoint.Host(h), port: p, using: .tcp)
        connection = conn
        lines.reset()
        linkState = .connecting(h)
        conn.stateUpdateHandler = { [weak self, weak conn] state in
            guard let self, let conn, conn === self.connection else { return }
            switch state {
            case .ready:
                self.linkState = .connected(h)
                self.onConnected?()
                self.receiveLoop(conn)
            case .failed, .cancelled:
                self.finish(conn)
            default:
                break   // .waiting 등: 네트워크가 준비될 때까지 연결 중으로 둡니다
            }
        }
        conn.start(queue: .main)
    }

    func disconnect() {
        guard let conn = connection else { return }
        connection = nil
        conn.cancel()
        let was = isConnected
        linkState = .disconnected
        if was { onDisconnected?() }
    }

    func send(_ text: String) {
        guard isConnected, let conn = connection, let data = text.data(using: .utf8) else { return }
        onSend?(text)
        conn.send(content: data, completion: .contentProcessed { _ in })
    }

    private func receiveLoop(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self, weak conn] data, _, isComplete, error in
            guard let self, let conn, conn === self.connection else { return }
            if let data, !data.isEmpty {
                for line in self.lines.append(data) { self.onLine?(line) }
            }
            if isComplete || error != nil { self.finish(conn); return }
            self.receiveLoop(conn)
        }
    }

    private func finish(_ conn: NWConnection) {
        guard conn === connection else { return }
        connection = nil
        conn.cancel()
        let was = isConnected
        linkState = .disconnected
        if was { onDisconnected?() }
    }
}
