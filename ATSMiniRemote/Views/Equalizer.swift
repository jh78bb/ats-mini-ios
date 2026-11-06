import SwiftUI

/// 점 매트릭스 이퀄라이저 (연출용). 신호 세기와 볼륨에 따라 높이가 달라지고, 음소거면 바닥만 남습니다.
struct Equalizer: View {
    @Environment(RadioState.self) private var radio
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = 27
    private let rows = 9

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: reduceMotion)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                let level = radio.isMuted || !radio.isConnected ? 0.0 : 0.3 + 0.7 * radio.signalLevel * (0.4 + 0.6 * Double(radio.volume) / 63)
                let dx = size.width / CGFloat(columns)
                let dy = size.height / CGFloat(rows)
                let r = min(dx, dy) * 0.28

                for c in 0..<columns {
                    let phase = Double(c) * 1.7
                    let wave = (sin(t * 3.1 + phase) + sin(t * 5.3 + phase * 0.6) + 2) / 4   // 0...1
                    let lit = 2 + Int((wave * level * Double(rows - 2)).rounded())
                    for row in 0..<rows {
                        let y = size.height - dy * (CGFloat(row) + 0.5)
                        let x = dx * (CGFloat(c) + 0.5)
                        let on = row < lit
                        let mix = Double(row) / Double(rows - 1)
                        let color: Color = on
                            ? Color(white: 0.92 - 0.42 * mix)
                            : Theme.dotOff
                        ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(color))
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
