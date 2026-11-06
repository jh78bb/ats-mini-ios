import SwiftUI

/// 런치 스크린(같은 배경색 + 로고) 바로 뒤에 이어지는 짧은 스플래시.
/// 로고는 런치 이미지와 같은 위치·크기라서 전환할 때 튀지 않고, 앱 이름만 부드럽게 나타납니다.
struct SplashView: View {
    @State private var showTitle = false

    var body: some View {
        ZStack {
            Theme.background
            Image("LaunchLogo")
                .resizable()
                .frame(width: 120, height: 120)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text("ATS Mini Remote")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                Text("Radio remote control")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.dim)
            }
            .offset(y: 110)
            .opacity(showTitle ? 1 : 0)
        }
        .onAppear { withAnimation(.easeOut(duration: 0.5).delay(0.1)) { showTitle = true } }
    }
}
