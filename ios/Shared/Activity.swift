import ActivityKit

enum Mood: String, Codable, Hashable {
    case idle, thinking, needs, done
}

struct IslandAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var mood: Mood
        var project: String
        var status: String
        var working: Int
    }
}
