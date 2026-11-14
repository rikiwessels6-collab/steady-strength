import ActivityKit
import SwiftUI
import WidgetKit

@main
struct RestTimerBundle: WidgetBundle {
    var body: some Widget {
        RestTimerLiveActivity()
    }
}

/// Tide, matching the app: deep ocean, coral highlights, aqua progress.
private enum Palette {
    static let night = Color(red: 0x0B / 255, green: 0x22 / 255, blue: 0x30 / 255)
    static let gold = Color(red: 0xFF / 255, green: 0x7A / 255, blue: 0x59 / 255)
    static let emerald = Color(red: 0x2E / 255, green: 0xC4 / 255, blue: 0xB6 / 255)
}

/// The lock screen layout, with a smaller one for the Apple Watch Smart Stack.
private struct RestLockScreen: View {
    let context: ActivityViewContext<RestActivityAttributes>
    @Environment(\.activityFamily) private var family

    var body: some View {
        let range = context.state.start...max(context.state.end, context.state.start)
        if family == .small {
            // Apple Watch: the countdown, big and alone, with what's next underneath.
            VStack(alignment: .leading, spacing: 2) {
                Label("REST", systemImage: "timer").font(.caption2.weight(.bold)).foregroundStyle(Palette.gold)
                Text(timerInterval: range, countsDown: true)
                    .font(.system(size: 30, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                if let next = context.state.next {
                    Text(next).font(.caption2).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
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
        }
    }
}

struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            RestLockScreen(context: context)
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
        // Also shown in the Apple Watch Smart Stack, using the small layout above.
        .supplementalActivityFamilies([.small, .medium])
    }
}
