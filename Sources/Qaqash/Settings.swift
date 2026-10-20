import SwiftUI

@Observable final class Settings {
    private static let store = UserDefaults.standard

    var sound: Bool { didSet { Self.store.set(sound, forKey: "sound") } }
    var quiet: Bool { didSet { Self.store.set(quiet, forKey: "quiet") } }
    var editPanel: Bool { didSet { Self.store.set(editPanel, forKey: "editPanel") } }
    var menuBarIcon: Bool {
        didSet {
            Self.store.set(menuBarIcon, forKey: "menuBarIcon")
            MainActor.assumeIsolated { Tray.shared.update() }
        }
    }

    init() {
        Self.store.register(defaults: ["sound": true, "quiet": true, "editPanel": true, "menuBarIcon": true])
        sound = Self.store.bool(forKey: "sound")
        quiet = Self.store.bool(forKey: "quiet")
        editPanel = Self.store.bool(forKey: "editPanel")
        menuBarIcon = Self.store.bool(forKey: "menuBarIcon")
    }
}

let settings = Settings()

struct SettingsPage: View {
    var body: some View {
        @Bindable var settings = settings
        VStack(spacing: 6) {
            row("Sounds", $settings.sound)
            row("Show edits while Claude works", $settings.editPanel)
            row("Stay quiet while the Claude app is in front", $settings.quiet)
            row("Show icon in the menu bar", $settings.menuBarIcon)
            HStack(spacing: 6) {
                action("Pair iPhone…") { PairWindow.open() }
                action("Quit Qaqash") { NSApp.terminate(nil) }
            }
        }
        .padding(.bottom, 2)
    }

    private func row(_ label: String, _ isOn: Binding<Bool>) -> some View {
        Button { withAnimation(.morph) { isOn.wrappedValue.toggle() } } label: {
            HStack(spacing: 12) {
                Text(label).font(.system(size: 13))
                Spacer(minLength: 0)
                Capsule().fill(isOn.wrappedValue ? Color.qGreen : Color(hex: 0x3a3a3c)).frame(width: 34, height: 20)
                    .overlay(alignment: isOn.wrappedValue ? .trailing : .leading) { Circle().fill(.white).padding(2) }
                    .animation(.pop, value: isOn.wrappedValue)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .hoverFill(.field, .fieldHover, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(Press(scale: 0.98))
    }

    private func action(_ title: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title).font(.system(size: 13)).frame(maxWidth: .infinity).padding(.vertical, 9).hoverFill(.field, .fieldHover, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(Press())
    }
}
