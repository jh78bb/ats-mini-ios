import SwiftUI

enum Theme {
    static let bg = Color(red: 0.045, green: 0.045, blue: 0.05)
    static let card = Color(red: 0.085, green: 0.085, blue: 0.095)
    static let chip = Color.white.opacity(0.09)
    static let pointer = Color(red: 0.94, green: 0.20, blue: 0.23)    // 다이얼 빨간 포인터
    static let mint = Color(red: 0.29, green: 0.87, blue: 0.50)       // 상태 포인트
    static let dotOff = Color.white.opacity(0.07)
    static let dim = Color.white.opacity(0.38)
    static let text = Color.white.opacity(0.92)
    static let stroke = Color.white.opacity(0.07)

    static var background: some View { bg.ignoresSafeArea() }
}

extension View {
    /// 어두운 둥근 카드 배경.
    func card(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
    }
}

/// 카드 상단의 작은 회색 라벨 (아이콘 + 텍스트).
struct CardLabel: View {
    let symbol: String
    let text: LocalizedStringKey
    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.dim)
            .labelStyle(.titleAndIcon)
    }
}

/// 작은 알약 칩.
struct Chip: View {
    let symbol: String?
    let text: String
    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)) }
            Text(text).font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(Theme.text.opacity(0.75))
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Theme.chip, in: Capsule())
    }
}
