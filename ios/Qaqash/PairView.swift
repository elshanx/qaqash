import SwiftUI
import VisionKit

struct PairView: View {
    @EnvironmentObject private var island: Island
    @State private var scanning = false
    @State private var pasted = ""
    @State private var failed = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Eyes(mood: .idle, size: 28)
            Text("Pair with your Mac").font(.title2.bold())
            Text("On your Mac, click the eyes in the menu bar, and choose Pair iPhone. Both need to be on the same Wi-Fi.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if DataScannerViewController.isSupported {
                Button("Scan the code") { scanning = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            Spacer()
            TextField("Or paste the pairing code", text: $pasted, axis: .vertical)
                .lineLimit(3)
                .textFieldStyle(.roundedBorder)
                .font(.caption.monospaced())
            Button("Pair") { use(pasted) }
                .disabled(pasted.isEmpty)
            if failed {
                Text("That isn't a Qaqash pairing code.").foregroundStyle(.orange).font(.footnote)
            }
        }
        .padding(24)
        .sheet(isPresented: $scanning) {
            Scanner { code in
                scanning = false
                use(code)
            }
            .ignoresSafeArea()
        }
    }

    private func use(_ text: String) {
        guard let pairing = Pairing.parse(text) else { return failed = true }
        island.pair(pairing)
    }
}

struct Scanner: UIViewControllerRepresentable {
    let found: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(found: found) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let found: (String) -> Void
        var done = false

        init(found: @escaping (String) -> Void) { self.found = found }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            for case .barcode(let code) in items {
                guard !done, let text = code.payloadStringValue, Pairing.parse(text) != nil else { continue }
                done = true
                found(text)
            }
        }
    }
}
