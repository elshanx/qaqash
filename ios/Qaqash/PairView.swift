import SwiftUI
import VisionKit

struct PairView: View {
    @EnvironmentObject private var island: Island
    @StateObject private var discovery = Discovery()
    @State private var waitingFor: FoundMac?
    @State private var code: String?
    @State private var problem: String?
    @State private var otherWays = false
    @State private var scanning = false
    @State private var pasted = ""

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Eyes(mood: waitingFor == nil ? .idle : .needs, size: 28)
            if let waitingFor {
                Text("Check your Mac").font(.title2.bold())
                Text("Click ✓ on the island at the top of \(waitingFor.name)'s screen if it shows this code:")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Text(code ?? "····").font(.system(size: 44, weight: .semibold, design: .monospaced))
                Button("Cancel") { self.waitingFor = nil }
            } else {
                Text("Pair with your Mac").font(.title2.bold())
                Text("Make sure Qaqash is running on your Mac and both are on the same Wi-Fi.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                if discovery.macs.isEmpty {
                    ProgressView("Looking for Macs…")
                }
                ForEach(discovery.macs) { mac in
                    Button { pair(with: mac) } label: {
                        Label(mac.name, systemImage: "laptopcomputer").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                if let problem {
                    Text(problem).foregroundStyle(.orange).font(.footnote)
                }
            }
            Spacer()
            if waitingFor == nil {
                Button("Other ways to pair") { otherWays.toggle() }.font(.footnote)
                if otherWays { manual }
            }
        }
        .padding(24)
        .onAppear { discovery.start() }
        .onDisappear { discovery.stop() }
        .sheet(isPresented: $scanning) {
            Scanner { code in
                scanning = false
                use(code)
            }
            .ignoresSafeArea()
        }
    }

    @ViewBuilder private var manual: some View {
        if DataScannerViewController.isSupported {
            Button("Scan the code from Pair iPhone…") { scanning = true }
        }
        TextField("Or paste the pairing code", text: $pasted, axis: .vertical)
            .lineLimit(3)
            .textFieldStyle(.roundedBorder)
            .font(.caption.monospaced())
        Button("Pair") { use(pasted) }.disabled(pasted.isEmpty)
    }

    private func pair(with mac: FoundMac) {
        problem = nil
        code = nil
        waitingFor = mac
        Task {
            do {
                let pairing = try await requestPairing(with: mac, device: UIDevice.current.name) { pin in
                    Task { @MainActor in code = pairCode(pin) }
                }
                if waitingFor == mac { island.pair(pairing) }
            } catch {
                if waitingFor == mac { problem = "\(mac.name) didn't allow it. Try again." }
            }
            if waitingFor == mac { waitingFor = nil }
        }
    }

    private func use(_ text: String) {
        guard let pairing = Pairing.parse(text) else { return problem = "That isn't a Qaqash pairing code." }
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
