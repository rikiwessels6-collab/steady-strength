import ActivityKit
import SwiftUI
import WidgetKit

@main
struct RestTimerBundle: WidgetBundle {
    var body: some Widget {
        RestTimerLiveActivity()
    }
}

/// Night, emerald and gold, matching the app.
private enum Palette {
    static let night = Color(red: 0.04, green: 0.08, blue: 0.07)
    static let gold = Color(red: 0.85, green: 0.70, blue: 0.35)
    static let emerald = Color(red: 0.18, green: 0.75, blue: 0.56)
}

struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            let range = context.state.start...max(context.state.end, context.state.start)
            HStack(alignment: .center, spacing: 16) {
                ProgressView(timerInterval: range, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                    .progressViewStyle(.circular)
                    .tint(Palette.emerald)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("REST · \(context.attributes.workoutName.uppercased())")
                        .font(.caption2.weight(.semibold)).foregroundStyle(Palette.gold).lineLimit(1)
                    Text(timerInterval: range, countsDown: true)
                        .font(.system(size: 34, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                    if let next = context.state.next {
                        Text(next).font(.footnote).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .activityBackgroundTint(Palette.night)
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let range = context.state.start...max(context.state.end, context.state.start)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Rest", systemImage: "timer").font(.headline).foregroundStyle(Palette.gold)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: range, countsDown: true)
                        .font(.title2.weight(.bold).monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 90)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.next ?? context.attributes.workoutName)
                        .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(Palette.gold)
            } compactTrailing: {
                Text(timerInterval: range, countsDown: true)
                    .monospacedDigit()
                    .frame(maxWidth: 48)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(Palette.gold)
            }
        }
    }
}
