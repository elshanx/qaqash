import SwiftUI

struct Eyes: View {
    var mood: Mood
    var size: CGFloat = 8

    var color: Color {
        switch mood {
        case .needs: .orange
        case .done: .green
        default: .white
        }
    }

    var body: some View {
        HStack(spacing: size * 0.6) {
            eye
            eye
        }
    }

    @ViewBuilder var eye: some View {
        if mood == .done {
            Circle()
                .trim(from: 0.5, to: 1)
                .stroke(color, style: StrokeStyle(lineWidth: size * 0.3, lineCap: .round))
                .frame(width: size, height: size)
                .offset(y: size * 0.25)
        } else {
            Capsule()
                .fill(color)
                .frame(width: size * 0.75, height: mood == .thinking ? size * 0.6 : size * 1.2)
        }
    }
}
