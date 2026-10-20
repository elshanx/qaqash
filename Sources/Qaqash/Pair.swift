import CoreImage.CIFilterBuiltins
import SwiftUI

@MainActor enum PairWindow {
    private static var window: NSWindow?

    static func open() {
        let window = window ?? NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        if self.window == nil {
            window.title = "Pair iPhone"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: PairView())
            window.center()
            self.window = window
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

private func qrCode(_ text: String) -> NSImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(text.utf8)
    guard let output = filter.outputImage else { return nil }
    let representation = NSCIImageRep(ciImage: output)
    let image = NSImage(size: representation.size)
    image.addRepresentation(representation)
    return image
}

private struct PairView: View {
    @State private var copied = false

    var body: some View {
        let text = phone.pairingText()
        VStack(spacing: 12) {
            Text("Pair your iPhone").font(.system(size: 17, weight: .semibold))
            Text("Open Qaqash on your iPhone and scan this code. Both need to be on the same Wi-Fi.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let text, let image = qrCode(text) {
                Image(nsImage: image).interpolation(.none).resizable().frame(width: 220, height: 220)
                    .padding(14).background(.white, in: RoundedRectangle(cornerRadius: 18))
            } else {
                Text("The phone link is not ready yet.").foregroundStyle(.secondary).frame(height: 248)
            }
            Button(copied ? "Copied" : "Copy pairing code") {
                guard let text else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            }
            .disabled(text == nil)
        }
        .padding(28)
        .frame(width: 360)
    }
}
