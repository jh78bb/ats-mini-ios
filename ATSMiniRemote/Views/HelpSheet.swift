import SwiftUI

/// 각 설정 항목 제목 오른쪽의 `?` 버튼이 여는 설명 창의 주제.
enum HelpTopic: String, Identifiable {
    case band, mode, seek, step, volume, reception, sleep, encoder, memory, log
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .band: "About bands"
        case .mode: "About modes"
        case .seek: "About seek and scan"
        case .step: "About tuning step"
        case .volume: "About volume"
        case .reception: "About reception settings"
        case .sleep: "About sleep"
        case .encoder: "About the receiver encoder"
        case .memory: "About memory slots"
        case .log: "About the communication log"
        }
    }
}

/// 섹션 제목 + 오른쪽 `?` 버튼.
struct HelpHeader: View {
    let title: LocalizedStringKey
    let topic: HelpTopic

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            HelpButton(topic: topic)
        }
        .textCase(nil)
    }
}

struct HelpButton: View {
    let topic: HelpTopic
    @State private var show = false

    var body: some View {
        Button { show = true } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 18))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Help")
        .sheet(isPresented: $show) { HelpSheet(topic: topic) }
    }
}

struct HelpSheet: View {
    let topic: HelpTopic
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List { content }
                .navigationTitle(topic.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var content: some View {
        switch topic {
        case .band: bandContent
        case .mode: modeContent
        case .seek:
            paragraph("Seek steps through the band one tuning step at a time and stops at the next station that is strong enough. Scan keeps doing that, pausing about 4 seconds on each station, until you stop it. The app reads the receiver’s signal strength (RSSI) and quality (SNR) at every step, which takes about a second, so a larger tuning step finds stations faster. FM covers 87.5–108 MHz.")
            entries([
                ("Strong", "Only stops at strong stations. Fewer false stops, but weak stations are skipped."),
                ("Normal", "A good balance for most places."),
                ("Weak", "Also stops at faint stations and sometimes at noise."),
            ])
        case .step:
            paragraph("How far the dial and the ‹ › buttons move per step. This is the app’s own tuning step and is separate from the receiver’s step setting. Small steps tune finely; large steps move faster.")
        case .volume:
            paragraph("Output level of the receiver’s speaker and headphones, from 0 to 63. 0 is mute. You can also tap the volume tile on the main screen.")
        case .reception:
            paragraph("Fine controls for how the receiver picks up a signal. Use − and + to step each one; the receiver keeps the actual value.")
            entries([
                ("Bandwidth", "How wide a slice of spectrum the receiver listens to. Narrow rejects neighbouring stations but sounds duller; wide sounds fuller but lets interference in."),
                ("AGC / Attenuator", "Automatic gain control keeps the volume steady as signals fade. The attenuator weakens very strong signals to avoid distortion."),
                ("Calibration", "Fine-tunes the frequency in single-sideband modes (LSB/USB) so voices sound natural instead of too high or too low."),
            ])
        case .sleep:
            paragraph("Sleep puts the receiver to sleep to save battery (the screen turns off; in some sleep modes the radio stops too). Wake up turns it back on.")
        case .encoder:
            paragraph("Remote control for the receiver’s rotary knob, so you can use its on-screen menus from the app.")
            entries([
                ("Rotate left / right", "Tunes the frequency or moves through the menu on the receiver’s screen."),
                ("Click", "Selects the highlighted menu item, like pressing the knob."),
                ("Short press", "Holding the knob for about half a second; some menu items use it."),
            ])
        case .memory:
            paragraph("The receiver stores up to 99 stations (band, frequency, mode and an optional name). While connected, these slots are the stations in the bottom bar and the heart button saves to them. Tap a slot to tune to it. Saving uses the first empty slot; clearing really empties the slot on the receiver.")
        case .log:
            paragraph("A technical view for troubleshooting: the commands the app sent (→) and the lines the receiver sent back (←). Copy it when you report a problem.")
        }
    }

    private func paragraph(_ key: LocalizedStringKey) -> some View {
        Section { Text(key) }
    }

    private func entries(_ items: [(String, String)]) -> some View {
        Section {
            ForEach(items, id: \.0) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey(item.0)).font(.headline)
                    Text(LocalizedStringKey(item.1)).font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: 밴드 · 모드

    @ViewBuilder
    private var bandContent: some View {
        paragraph("A band is a slice of the radio spectrum. The dial only moves inside the selected band, so pick the band first, then tune. Pick one from the list and the app steps the receiver there for you. A quiet band is not broken; it just has nothing on the air right now.")
        Section("Bands on this receiver") {
            ForEach(DeviceBand.all) { b in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(verbatim: b.name).font(.headline)
                        Text(verbatim: b.rangeLabel).foregroundStyle(.secondary)
                        Spacer()
                        Text(verbatim: b.mode).font(.caption.weight(.semibold))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Theme.chip, in: Capsule())
                    }
                    Text(LocalizedStringKey(b.summary)).font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private var modeContent: some View {
        paragraph("The mode is how the receiver decodes the signal. Use the one that matches the band: FM on the FM band, AM on broadcast bands, LSB or USB for amateur radio voice. The wrong mode sounds distorted or silent.")
        entries([
            ("FM", "Wideband FM, used by VHF broadcast stations. Clear music."),
            ("AM", "Amplitude modulation, used by long-, medium- and shortwave broadcasts."),
            ("LSB", "Lower sideband, a voice mode used by amateur radio below about 10 MHz. It needs fine tuning, otherwise voices sound like a duck."),
            ("USB", "Upper sideband, the voice mode used above about 10 MHz and by many utility stations. It also needs fine tuning."),
        ])
    }
}
