import SwiftUI

extension Animation {
    static let morph = Animation.spring(response: 0.45, dampingFraction: 0.68)
    static let pop = Animation.spring(response: 0.32, dampingFraction: 0.6)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xff) / 255, green: Double(hex >> 8 & 0xff) / 255, blue: Double(hex & 0xff) / 255, opacity: opacity)
    }

    static let qOrange = Color(hex: 0xff9f0a)
    static let qGreen = Color(hex: 0x30d158)
    static let qBlue = Color(hex: 0x0a84ff)
    static let qRed = Color(hex: 0xff453a)
    static let field = Color(hex: 0x1c1c1e)
    static let fieldHover = Color(hex: 0x2c2c2e)
}

func hsl(_ hue: Double, _ saturation: Double, _ lightness: Double) -> Color {
    let value = lightness + saturation * min(lightness, 1 - lightness)
    return Color(hue: hue.truncatingRemainder(dividingBy: 360) / 360, saturation: value == 0 ? 0 : 2 * (1 - lightness / value), brightness: value)
}

let mono = Font.system(size: 11, design: .monospaced)

struct Rise: ViewModifier {
    var on: Bool

    func body(content: Content) -> some View {
        content
            .opacity(on ? 0 : 1)
            .scaleEffect(on ? 0.92 : 1, anchor: .top)
            .offset(y: on ? -6 : 0)
            .blur(radius: on ? 10 : 0)
    }
}

struct Leave: ViewModifier {
    var on: Bool

    func body(content: Content) -> some View {
        content
            .opacity(on ? 0 : 1)
            .scaleEffect(on ? 0.96 : 1, anchor: .top)
            .blur(radius: on ? 6 : 0)
    }
}

extension AnyTransition {
    static let rise = AnyTransition.asymmetric(
        insertion: .modifier(active: Rise(on: true), identity: Rise(on: false)).animation(.morph.delay(0.06)),
        removal: .opacity.animation(.linear(duration: 0.05))
    )
    static let leave = AnyTransition.asymmetric(
        insertion: .modifier(active: Rise(on: true), identity: Rise(on: false)).animation(.morph.delay(0.06)),
        removal: .modifier(active: Leave(on: true), identity: Leave(on: false)).animation(.easeIn(duration: 0.14))
    )
}

struct Press: ButtonStyle {
    var scale: CGFloat = 0.92

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.pop, value: configuration.isPressed)
    }
}

struct Source: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SourceLabel(label: configuration.label, pressed: configuration.isPressed)
    }

    struct SourceLabel<Label: View>: View {
        var label: Label
        var pressed: Bool
        @State private var hovering = false

        var body: some View {
            label
                .contentShape(Rectangle())
                .opacity(hovering ? 0.8 : 1)
                .scaleEffect(pressed ? 0.96 : 1)
                .animation(.pop, value: pressed)
                .onHover { hovering = $0 }
        }
    }
}

struct HoverFill<S: Shape>: ViewModifier {
    var normal: Color
    var hover: Color
    var shape: S
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(hovering ? hover : normal, in: shape)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverFill<S: Shape>(_ normal: Color, _ hover: Color, in shape: S) -> some View {
        modifier(HoverFill(normal: normal, hover: hover, shape: shape))
    }
}

struct Capped: ViewModifier {
    var height: CGFloat
    var fade = false
    @State private var natural: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { natural = $0 }
            .frame(maxHeight: height, alignment: .top)
            .fixedSize(horizontal: false, vertical: true)
            .clipped()
            .mask {
                LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: fade && natural > height ? 1 - 14 / height : 1), .init(color: fade && natural > height ? .clear : .black, location: 1)], startPoint: .top, endPoint: .bottom)
            }
    }
}
