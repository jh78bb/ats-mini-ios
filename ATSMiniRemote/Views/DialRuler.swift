import SwiftUI

/// 라디오 다이얼 눈금자. 가운데 빨간 포인터가 현재 주파수이고, 좌우로 드래그해 튜닝합니다.
/// `center`(눈금 단위)를 애니메이션해 눈금이 부드럽게 미끄러집니다.
struct DialRuler: View, Animatable {
    let band: Band
    var center: Double

    var animatableData: Double {
        get { center }
        set { center = newValue }
    }

    private let spacing: CGFloat = 14

    var body: some View {
        Canvas { ctx, size in
            let spec = band.dial
            let midX = size.width / 2
            let half = Int(midX / spacing) + 2
            let base = Int(center.rounded())
            let lo = Int((Double(band.range.lowerBound) / Double(spec.tick)).rounded(.up))
            let hi = Int((Double(band.range.upperBound) / Double(spec.tick)).rounded(.down))

            for i in (base - half)...(base + half) where i >= lo && i <= hi {
                let x = midX + (Double(i) - center) * spacing
                let dist = abs(x - midX) / midX
                let fade = max(0.0, 1 - dist * 0.9)
                let isMajor = i % spec.major == 0
                let h: CGFloat = isMajor ? 22 : 14
                var p = Path()
                p.move(to: CGPoint(x: x, y: size.height - 6))
                p.addLine(to: CGPoint(x: x, y: size.height - 6 - h))
                ctx.stroke(p, with: .color(.white.opacity((isMajor ? 0.55 : 0.28) * fade)), lineWidth: 1.5)

                if isMajor {
                    let value = Double(i * spec.tick) / spec.divisor
                    let text = String(format: "%.\(spec.decimals)f", value)
                    let near = abs(x - midX) < spacing * Double(spec.major) / 2
                    let label = Text(text)
                        .font(.system(size: near ? 20 : 17, weight: .medium))
                        .foregroundColor(.white.opacity(near ? 1 : 0.45 * fade))
                    ctx.draw(label, at: CGPoint(x: x, y: 18))
                }
            }
        }
        .overlay(alignment: .bottom) {
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 13))
                .foregroundStyle(Theme.pointer)
                .offset(y: -8)
        }
        .frame(height: 64)
        .accessibilityHidden(true)
    }
}
