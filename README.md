# ATS Mini Remote

iOS remote controller for ATS Mini radio receivers.

**ATS Mini Remote**는 iPhone에서 ATS Mini 라디오 수신기를 찾아 연결하고, 주파수와 볼륨을 조절하는 iOS 앱입니다. `ats-mini-ios`는 이 앱의 소스 저장소입니다.

**현재 상태** · 초기 기획 단계입니다. 아래 연결 흐름과 기능은 구현 계획입니다.

## 앱에서 블루투스로 연결하기

1. ATS Mini의 `Settings → Bluetooth`에서 `Ad hoc` 모드를 켭니다.
2. iPhone에서 앱을 열고 **기기 연결 → 블루투스**를 선택합니다. 처음 연결할 때는 iOS의 블루투스 접근을 허용합니다.
3. 앱에 표시되는 주변 수신기 목록에서 내 ATS Mini를 선택합니다.
4. 연결이 완료되면 제어 화면에서 주파수, 볼륨, 밴드와 수신 모드를 조절합니다.

앱에서 연결 상태를 확인하고, 연결이 끊기면 **다시 연결**을 눌러 재시도할 수 있도록 할 계획입니다.

## 연결 방식

| 방식 | 연결에 필요한 설정 | 개발 방향 |
| --- | --- | --- |
| 블루투스 LE (BLE) | 수신기의 `Bluetooth → Ad hoc` 설정과 iOS 블루투스 권한 | 기본 연결. 공유기나 IP 주소 입력 없이 앱에서 수신기를 찾아 연결합니다. |
| Wi-Fi TCP | 수신기의 Wi-Fi와 `TCP Port → Ad hoc` 설정, iOS 로컬 네트워크 권한 | 보조 연결. iPhone을 수신기와 같은 네트워크 또는 수신기의 Wi-Fi에 연결한 뒤 `atsmini.local`이나 수신기 IP의 `60000`번 포트로 접속합니다. |

수신기 가까이에서 바로 연결할 때는 BLE가 간편합니다. 집에서 수신기를 공유기에 연결해 두고 쓴다면 Wi-Fi도 편리합니다. ATS Mini 펌웨어 문서는 안정성을 위해 수신기의 Wi-Fi와 블루투스를 한 번에 하나씩 사용하도록 권장합니다. [ATS Mini 원격 제어 문서](https://esp32-si4732.github.io/ats-mini/remote.html) · [수신기 설정 안내](https://esp32-si4732.github.io/ats-mini/manual.html) · [iOS 로컬 네트워크 권한](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)

## 개발 계획

- [ ] Swift와 SwiftUI로 기기 연결 화면과 라디오 제어 화면을 구성합니다.
- [ ] Core Bluetooth로 BLE 검색, 기기 선택, 연결 및 재연결을 구현합니다.
- [ ] ATS Mini의 Ad hoc 프로토콜로 주파수, 볼륨, 밴드와 수신 모드를 제어하고 수신기 상태를 표시합니다.
- [ ] Wi-Fi TCP 연결을 추가하고 BLE와 같은 라디오 제어 명령을 사용합니다.

`Ad hoc` 원격 제어 모드를 제공하는 [ESP32-SI4732 ATS Mini 펌웨어](https://github.com/esp32-si4732/ats-mini)를 기준으로 개발합니다. 지원 펌웨어 버전과 기기 조합은 iPhone과 ATS Mini 실기기에서 확인할 예정입니다.

## 향후 확장

Android 앱과 공통 통신 프로토콜 라이브러리를 개발하게 되면 각각 `ats-mini-android`와 `ats-mini-protocol`로 분리할 수 있습니다.
