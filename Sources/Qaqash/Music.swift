import SwiftUI

struct Track: Equatable {
    var app: String
    var playing: Bool
    var title: String
    var artist: String
    var album = ""
    var position: Double = 0
    var duration: Double = 0
    var artworkUrl: String?

    static let idle = Track(app: "Spotify", playing: false, title: "Spotify", artist: "Not playing")
}

private let spotifyNowPlaying = """
tell application "Spotify"
    if player state is stopped then return ""
    return (player state as text) & tab & (name of current track) & tab & (artist of current track) & tab & (album of current track) & tab & (player position as text) & tab & ((duration of current track) / 1000 as text) & tab & (artwork url of current track)
end tell
"""

private let musicNowPlaying = """
tell application "Music"
    if player state is stopped then return ""
    set state to player state as text
    try
        return state & tab & (name of current track) & tab & (artist of current track) & tab & (album of current track) & tab & (player position as text) & tab & (duration of current track as text)
    end try
    return state & tab & "Apple Music Radio" & tab & "Live" & tab & "Radio" & tab & "0" & tab & "0"
end tell
"""

private let musicArtwork = """
on run argv
    tell application "Music" to set artworkData to raw data of artwork 1 of current track
    set artworkFile to open for access (POSIX file (item 1 of argv)) with write permission
    set eof artworkFile to 0
    write artworkData to artworkFile
    close access artworkFile
end run
"""

enum Music {
    private static var timer: DispatchSourceTimer?

    static func start() {
        guard let spotify = NSAppleScript(source: spotifyNowPlaying), let music = NSAppleScript(source: musicNowPlaying) else { return }
        let timer = DispatchSource.makeTimerSource(queue: scripts)
        timer.schedule(deadline: .now(), repeating: 2)
        timer.setEventHandler {
            let track = nowPlaying(spotify, music)
            DispatchQueue.main.async { state.updateTrack(track) }
        }
        timer.resume()
        self.timer = timer
    }

    private static func query(_ app: String, _ bundleId: String, _ script: NSAppleScript) -> Track? {
        guard appIsRunning(bundleId), let line = script.text() else { return nil }
        let fields = line.components(separatedBy: "\t")
        guard fields.count >= 6 else { return nil }
        let seconds = { (text: String) in Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        return Track(app: app, playing: fields[0] == "playing", title: fields[1], artist: fields[2], album: fields[3],
                     position: seconds(fields[4]), duration: seconds(fields[5]), artworkUrl: fields.count > 6 ? fields[6] : nil)
    }

    private static func nowPlaying(_ spotify: NSAppleScript, _ music: NSAppleScript) -> Track? {
        let playing = query("Spotify", "com.spotify.client", spotify)
        if playing?.playing == true { return playing }
        return query("Music", "com.apple.Music", music) ?? playing
    }

    static func control(_ app: String, _ action: String) {
        let bundleId = app == "Music" ? "com.apple.Music" : "com.spotify.client"
        let launches = action == "toggle" || action == "open"
        let commands = switch (action, app) {
        case ("toggle", _): "playpause"
        case ("next", _): "next track"
        case ("previous", _): "previous track"
        case ("open", "Music"): "try\nreveal current track\nend try\nactivate"
        default: "activate"
        }
        scripts.async {
            guard launches || appIsRunning(bundleId) else { return }
            _ = runScript("tell application \"\(app == "Music" ? "Music" : "Spotify")\"\n\(commands)\nend tell")
        }
    }

    static func artwork() -> NSImage? {
        guard appIsRunning("com.apple.Music") else { return nil }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("qaqash-artwork")
        guard run("/usr/bin/osascript", ["-e", musicArtwork, file.path]) != nil else { return nil }
        return NSImage(contentsOf: file)
    }
}

private func hueOf(_ text: String) -> Double {
    Double(text.utf16.reduce(7) { ($0 * 31 + Int($1)) % 360 })
}

private func spotifyCover(_ text: String?) -> URL? {
    guard let text, let url = URL(string: text), url.scheme == "https", url.host == "i.scdn.co" else { return nil }
    return url
}

private func vivid(_ red: Double, _ green: Double, _ blue: Double) -> Color {
    let (r, g, b) = (red / 255, green / 255, blue / 255)
    let high = max(r, g, b)
    let low = min(r, g, b)
    let delta = high - low
    let hue = delta == 0 ? 0 : high == r ? 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6) : high == g ? 60 * ((b - r) / delta + 2) : 60 * ((r - g) / delta + 4)
    let lightness = (high + low) / 2
    let saturation = delta == 0 ? 0 : delta / (1 - abs(2 * lightness - 1))
    return hsl((hue + 360).truncatingRemainder(dividingBy: 360), saturation < 0.12 ? 0 : max(0.55, saturation), min(0.72, max(0.58, lightness)))
}

private func tintOf(_ image: NSImage) -> Color? {
    let size = 12
    var pixels = [UInt8](repeating: 0, count: size * size * 4)
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let context = CGContext(data: &pixels, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))
    var (red, green, blue, total) = (0.0, 0.0, 0.0, 0.0)
    for index in stride(from: 0, to: pixels.count, by: 4) {
        let (r, g, b) = (Double(pixels[index]), Double(pixels[index + 1]), Double(pixels[index + 2]))
        let high = max(r, g, b)
        let weight = (high - min(r, g, b)) * high / 255 + 1
        red += r * weight
        green += g * weight
        blue += b * weight
        total += weight
    }
    return vivid(red / total, green / total, blue / total)
}

extension AppState {
    func updateTrack(_ next: Track?) {
        let albumChanged = track.map { "\($0.app):\($0.album)" } != next.map { "\($0.app):\($0.album)" }
        withAnimation(.morph) {
            track = next
            trackSyncedAt = Date()
        }
        if albumChanged { loadArtwork() }
    }

    private func loadArtwork() {
        let current = track
        artwork = nil
        tint = nil
        let show = { (image: NSImage?) in
            guard let image, self.track?.album == current?.album else { return }
            self.artwork = image
            withAnimation(.easeOut(duration: 0.9)) { self.tint = tintOf(image) }
        }
        if current?.app == "Music" {
            scripts.async {
                let image = Music.artwork()
                DispatchQueue.main.async { show(image) }
            }
        } else if let url = spotifyCover(current?.artworkUrl) {
            Task {
                let data = try? await URLSession.shared.data(from: url).0
                show(data.flatMap(NSImage.init(data:)))
            }
        }
    }

    var accent: Color { tint ?? hsl(hueOf(track?.album ?? ""), 0.75, 0.65) }

    var position: Double {
        guard let track else { return 0 }
        let played = track.playing ? Date().timeIntervalSince(trackSyncedAt) : 0
        return min(track.position + played, track.duration)
    }

    func control(_ action: String) {
        Music.control(track?.app ?? Track.idle.app, action)
        guard var track, action == "toggle" else { return }
        track.position = position
        track.playing.toggle()
        withAnimation(.morph) {
            self.track = track
            trackSyncedAt = Date()
        }
    }
}

struct ArtView: View {
    var size: CGFloat
    var radius: CGFloat

    var body: some View {
        let hue = hueOf(state.track?.album ?? "")
        ZStack {
            if let artwork = state.artwork {
                Image(nsImage: artwork).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [hsl(hue, 0.7, 0.58), hsl(hue + 50, 0.7, 0.32)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}

struct Equalizer: View {
    var height: CGFloat
    var playing: Bool

    var body: some View {
        HStack(spacing: 2) {
            ForEach([0.9, 0.7, 1.1, 0.8], id: \.self) { duration in
                Bar(height: height, duration: duration, playing: playing)
            }
        }
        .frame(height: height)
        .opacity(playing ? 1 : 0.4)
    }

    private struct Bar: View {
        var height: CGFloat
        var duration: Double
        var playing: Bool

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 2).fill(state.accent).frame(width: 3, height: height)
            if playing {
                shape.phaseAnimator([0.25, 1]) { $0.scaleEffect(y: $1) } animation: { _ in .easeInOut(duration: duration) }
            } else {
                shape.scaleEffect(y: 0.6)
            }
        }
    }
}

private struct PlayIcon: View {
    var playing: Bool
    var size: CGFloat

    var body: some View {
        Image(systemName: playing ? "pause.fill" : "play.fill").font(.system(size: size))
    }
}

struct PlayerView: View {
    var body: some View {
        let track = state.track ?? .idle
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Button { state.control("open") } label: {
                    HStack(spacing: 14) {
                        ArtView(size: 56, radius: 14).shadow(color: .black.opacity(0.4), radius: 8, y: 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title).font(.system(size: 15, weight: .semibold))
                            Text(track.artist).font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
                        }
                        .lineLimit(1)
                    }
                }
                .buttonStyle(Source())
                Spacer(minLength: 0)
                if state.track != nil { Equalizer(height: 18, playing: track.playing) }
            }
            if track.duration > 0 {
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    let position = state.position
                    HStack(spacing: 10) {
                        Text(clock(position))
                        Capsule().fill(.white.opacity(0.18)).frame(height: 5)
                            .overlay(alignment: .leading) {
                                GeometryReader { geometry in
                                    Capsule().fill(.white.opacity(0.85)).frame(width: geometry.size.width * position / track.duration)
                                        .animation(.linear(duration: 0.5), value: position)
                                }
                            }
                        Text("-" + clock(track.duration - position))
                    }
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
                }
            }
            HStack(spacing: 28) {
                control("previous") { Image(systemName: "backward.fill").font(.system(size: 22)) }
                control("toggle") { PlayIcon(playing: track.playing, size: 28) }
                control("next") { Image(systemName: "forward.fill").font(.system(size: 22)) }
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private func control(_ action: String, @ViewBuilder _ icon: () -> some View) -> some View {
        Button { state.control(action) } label: {
            icon().frame(width: 40, height: 40).hoverFill(.clear, .white.opacity(0.1), in: Circle())
        }
        .buttonStyle(Press())
    }

    private func clock(_ seconds: Double) -> String {
        let whole = max(0, Int(seconds))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}

struct MiniPlayer: View {
    var body: some View {
        let track = state.track ?? .idle
        HStack(spacing: 10) {
            Button { state.control("open") } label: {
                HStack(spacing: 10) {
                    ArtView(size: 26, radius: 6)
                    Text([track.title, track.artist].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 13)).lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(Source())
            Button { state.control("toggle") } label: {
                PlayIcon(playing: track.playing, size: 14).frame(width: 30, height: 30).hoverFill(.clear, .white.opacity(0.1), in: Circle())
            }
            .buttonStyle(Press())
        }
        .padding(.top, 12)
    }
}
