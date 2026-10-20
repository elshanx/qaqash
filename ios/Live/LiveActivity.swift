import ActivityKit
import SwiftUI
import WidgetKit

@main
struct LiveBundle: WidgetBundle {
    var body: some Widget { IslandLive() }
}

struct IslandLive: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: IslandAttributes.self) { context in
            HStack(spacing: 14) {
                Eyes(mood: context.state.mood, size: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.project).font(.headline)
                    Text(context.state.status).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .activityBackgroundTint(.black)
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Eyes(mood: context.state.mood, size: 14).padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.project).font(.headline)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.status).foregroundStyle(.secondary)
                }
            } compactLeading: {
                Eyes(mood: context.state.mood, size: 8)
            } compactTrailing: {
                Text(context.state.status).font(.caption2).lineLimit(1).frame(maxWidth: 64)
            } minimal: {
                Eyes(mood: context.state.mood, size: 6)
            }
        }
    }
}
