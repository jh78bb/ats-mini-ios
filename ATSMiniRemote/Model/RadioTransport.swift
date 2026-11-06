import Foundation

/// 수신기와의 연결 상태 (BLE, TCP 공통).
enum LinkState: Equatable {
    case disconnected
    case connecting(String)
    case connected(String)
}

/// BLE와 Wi-Fi TCP가 같은 방식으로 명령을 보내고 줄 단위로 받도록 맞춘 전송 계층.
protocol RadioTransport: AnyObject {
    var linkState: LinkState { get }
    var onLine: ((String) -> Void)? { get set }
    var onConnected: (() -> Void)? { get set }
    var onDisconnected: (() -> Void)? { get set }
    var onSend: ((String) -> Void)? { get set }
    func send(_ text: String)
    func disconnect()
}

extension RadioTransport {
    var isConnected: Bool { if case .connected = linkState { return true } else { return false } }
}

/// 조각으로 도착하는 바이트를 줄(CR 또는 LF 기준)로 나눕니다.
struct LineBuffer {
    private var data = Data()

    mutating func append(_ chunk: Data) -> [String] {
        data.append(chunk)
        var lines: [String] = []
        while let i = data.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            let lineData = data.prefix(upTo: i)
            data.removeSubrange(data.startIndex...i)
            if let line = String(data: lineData, encoding: .utf8), !line.isEmpty { lines.append(line) }
        }
        if data.count > 8192 { data.removeAll() }   // 줄바꿈 없는 대용량(스크린샷 등) 보호
        return lines
    }

    mutating func reset() { data.removeAll() }
}
