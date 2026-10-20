import SwiftUI

struct Eyes: View {
    var mood: Mood
    var width: CGFloat
    var height: CGFloat
    var gap: CGFloat

    var body: some View {
        moving(HStack(spacing: gap) { eye; eye })
            .animation(.pop, value: mood)
    }

    @ViewBuilder private var eye: some View {
        if mood == .done {
            Circle().trim(from: 0.5, to: 1)
                .stroke(Color.qGreen, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: width + 3, height: width + 3)
                .offset(y: 2)
        } else {
            let grown: CGFloat = mood == .needs ? 2 : 0
            RoundedRectangle(cornerRadius: (width + grown) / 2)
                .fill(mood == .needs ? Color.qOrange : .white)
                .frame(width: width + grown, height: height + grown)
        }
    }

    @ViewBuilder private func moving(_ eyes: some View) -> some View {
        switch mood {
        case .thinking:
            eyes.keyframeAnimator(initialValue: -2.0, repeating: true) { $0.offset(x: $1) } keyframes: { _ in
                CubicKeyframe(2, duration: 1.2)
                CubicKeyframe(-2, duration: 1.2)
            }
        case .needs:
            eyes.keyframeAnimator(initialValue: 1.0, repeating: true) { content, scale in
                content.scaleEffect(scale).shadow(color: .qOrange.opacity((scale - 1) / 0.15), radius: 4)
            } keyframes: { _ in
                CubicKeyframe(1.15, duration: 0.7)
                CubicKeyframe(1, duration: 0.7)
            }
        case .done:
            eyes.keyframeAnimator(initialValue: 0.0, repeating: false) { $0.offset(y: $1) } keyframes: { _ in
                SpringKeyframe(-3, duration: 0.2)
                SpringKeyframe(0, duration: 0.3)
            }
        case .idle:
            eyes.keyframeAnimator(initialValue: 1.0, repeating: true) { $0.scaleEffect(x: 1, y: $1) } keyframes: { _ in
                LinearKeyframe(1, duration: 3.76)
                LinearKeyframe(0.1, duration: 0.12)
                LinearKeyframe(1, duration: 0.12)
            }
        }
    }
}

struct Face: View {
    var body: some View {
        Eyes(mood: state.displayMood, width: 6, height: 9, gap: 5)
            .background { ContextRing(diameter: 24, line: 2) }
    }
}

struct Avatar: View {
    var body: some View {
        let thinking = state.displayMood == .thinking
        Eyes(mood: thinking ? .thinking : .idle, width: 12, height: 18, gap: 10)
            .background { ContextRing(diameter: 58, line: 3) }
            .overlay(alignment: .top) {
                if thinking {
                    Text("•••").font(.system(size: 8)).kerning(2)
                        .phaseAnimator([0.25, 0.8]) { $0.opacity($1) } animation: { _ in .easeInOut(duration: 0.7) }
                        .offset(y: 24)
                }
            }
            .frame(height: 50)
            .padding(.leading, 4)
    }
}
