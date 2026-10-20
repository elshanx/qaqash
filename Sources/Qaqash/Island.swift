import SwiftUI

struct IslandView: View {
    @State private var squashes = 0
    @State private var squash = 0.0
    @State private var drips = 0
    @State private var last = CGSize.zero

    var body: some View {
        VStack(spacing: 0) {
            Bar()
            if state.open {
                Pages().transition(.leave)
            }
        }
        .frame(width: state.width, alignment: .top)
        .clipped()
        .background(alignment: .top) { liquid }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            state.hit = size
            wobble(size)
        }
        .frame(width: IslandWindow.canvas.width, height: IslandWindow.canvas.height, alignment: .top)
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
        .font(.system(size: 12))
    }

    private func wobble(_ size: CGSize) {
        let grew = size.height - last.height
        let moved = abs(grew) + abs(size.width - last.width)
        last = size
        guard moved >= 20 else { return }
        squash = grew >= 0 ? 0.035 : -0.03
        squashes += 1
        if grew < 0 { drips += 1 }
    }

    private var glow: Color {
        switch state.displayMood {
        case .needs: return Color.qOrange.opacity(0.42)
        case .done: return Color.qGreen.opacity(0.4)
        default: return state.page == .home && !state.working ? state.accent.opacity(0.45) : .clear
        }
    }

    private var liquid: some View {
        let radius: CGFloat = state.open ? 32 : 12
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius)
        return ZStack(alignment: .bottom) {
            UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24)
                .fill(.black)
                .frame(width: 48, height: 26)
                .keyframeAnimator(initialValue: CGSize(width: 1, height: 0), trigger: drips) { $0.scaleEffect(x: $1.width, y: 1, anchor: .top).offset(y: $1.height) } keyframes: { _ in
                    KeyframeTrack(\.height) {
                        CubicKeyframe(14, duration: 0.26)
                        CubicKeyframe(-2, duration: 0.26)
                        CubicKeyframe(0, duration: 0.23)
                    }
                    KeyframeTrack(\.width) {
                        CubicKeyframe(0.7, duration: 0.26)
                        CubicKeyframe(1.05, duration: 0.26)
                        CubicKeyframe(1, duration: 0.23)
                    }
                }
            shape.fill(.black)
                .overlay(alignment: .bottom) {
                    Ellipse().fill(glow).frame(height: 120).padding(.horizontal, state.width * 0.08).blur(radius: 36).offset(y: 70)
                        .opacity(state.open ? 1 : 0)
                        .animation(.easeOut(duration: state.open ? 0.9 : 0.12), value: state.open)
                        .animation(.easeOut(duration: 0.9), value: glow)
                }
                .clipShape(shape)
                .overlay { shape.stroke(LinearGradient(colors: [.clear, .white.opacity(state.open ? 0.1 : 0)], startPoint: .center, endPoint: .bottom), lineWidth: 1) }
                .shadow(color: .black.opacity(state.open ? 0.45 : 0), radius: 14, y: 12)
                .keyframeAnimator(initialValue: CGSize(width: 1, height: 1), trigger: squashes) { $0.scaleEffect(x: $1.width, y: $1.height, anchor: .top) } keyframes: { _ in
                    KeyframeTrack(\.width) {
                        CubicKeyframe(1 - squash, duration: 0.195)
                        CubicKeyframe(1 + squash * 0.5, duration: 0.195)
                        CubicKeyframe(1, duration: 0.26)
                    }
                    KeyframeTrack(\.height) {
                        CubicKeyframe(1 + squash, duration: 0.195)
                        CubicKeyframe(1 - squash * 0.4, duration: 0.195)
                        CubicKeyframe(1, duration: 0.26)
                    }
                }
        }
        .overlay(alignment: .topLeading) { Ear().offset(x: -12) }
        .overlay(alignment: .topTrailing) { Ear().scaleEffect(x: -1).offset(x: 12) }
    }
}

private struct Ear: View {
    var body: some View {
        Path { path in
            path.addRect(CGRect(x: 0, y: 0, width: 12, height: 12))
            path.addEllipse(in: CGRect(x: -12, y: 0, width: 24, height: 24))
        }
        .fill(.black, style: FillStyle(eoFill: true))
        .frame(width: 12, height: 12)
        .clipped()
    }
}

private struct Bar: View {
    var body: some View {
        let music = state.musicMode && !state.open
        ZStack(alignment: .leading) {
            Face()
                .offset(x: music ? 48 : 22)
                .keyframeAnimator(initialValue: 0.0, repeating: true) { $0.offset(y: music ? $1 : 0) } keyframes: { _ in
                    CubicKeyframe(-2, duration: 0.15)
                    CubicKeyframe(0.5, duration: 0.15)
                    CubicKeyframe(0, duration: 0.2)
                }
            ArtView(size: 20, radius: 5).offset(x: 18).opacity(music ? 1 : 0).scaleEffect(music ? 1 : 0.6)
            ZStack(alignment: .leading) {
                Text(state.statusText)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .id(state.statusText)
                    .transition(.asymmetric(insertion: .modifier(active: StatusIn(on: true), identity: StatusIn(on: false)).animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.28)), removal: .opacity.animation(.linear(duration: 0.05))))
            }
            .padding(.leading, state.width / 2 + 87)
            .padding(.trailing, 16)
            .opacity(state.open || music ? 0 : 0.8)
            Equalizer(height: 14, playing: true)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 22)
                .opacity(music ? 1 : 0)
                .scaleEffect(music ? 1 : 0.6, anchor: .trailing)
        }
        .animation(.pop, value: music)
        .frame(width: state.width, height: state.barHeight, alignment: .leading)
        .onChange(of: state.statusText) { state.bump() }
    }
}

private struct StatusIn: ViewModifier {
    var on: Bool

    func body(content: Content) -> some View {
        content.opacity(on ? 0 : 1).offset(y: on ? 4 : 0).blur(radius: on ? 3 : 0)
    }
}

private struct Pages: View {
    var body: some View {
        VStack(spacing: 0) {
            if state.showTabs { Tabs().transition(.rise) }
            switch state.page {
            case .settings:
                SettingsPage().transition(.rise)
            case .home:
                if state.showActivity, let activity = state.activity {
                    ActivityView(activity: activity).transition(.rise)
                    MiniPlayer()
                    MiniVSCode()
                } else {
                    PlayerView().transition(.rise)
                    VSCodeCard()
                }
            case .sessions:
                SessionList().transition(.rise)
            case .prompt:
                if let first = state.queue.first { PromptView(ask: first).transition(.rise) }
            case nil:
                EmptyView()
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
        .frame(width: state.contentWidth)
    }
}
