import SwiftUI

struct Tabs: View {
    var body: some View {
        HStack(spacing: 4) {
            tab(.home, "house")
            tab(.sessions, "list.bullet")
            Spacer()
            tab(.settings, "gearshape")
            button(settings.sound ? "speaker.wave.2" : "speaker.slash", active: false) { settings.sound.toggle() }
        }
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    private func tab(_ tab: Tab, _ symbol: String) -> some View {
        button(symbol, active: state.tab == tab) { withAnimation(.morph) { state.tab = tab } }
    }

    private func button(_ symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(active ? 1 : 0.55))
                .frame(width: 38, height: 30)
                .hoverFill(active ? .fieldHover : .clear, active ? .fieldHover : .white.opacity(0.08), in: Capsule())
        }
        .buttonStyle(Press())
    }
}
