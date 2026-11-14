import SwiftUI
import SwiftData
import SteadyCore

/// Shown when a workout is finished: time, sets, volume and any new personal bests.
struct WorkoutRecapView: View {
    let log: WorkoutLog
    let onDone: () -> Void
    @Environment(ContentStore.self) private var store
    @Query private var logs: [WorkoutLog]

    private var minutes: Int {
        max(1, Int(((log.finishedAt ?? .now).timeIntervalSince(log.startedAt) / 60).rounded()))
    }
    private var volume: Double { log.sets.reduce(0) { $0 + $1.weight * Double($1.reps) } }

    /// Exercises where today beat every earlier session for top weight or estimated 1RM.
    private var records: [String] {
        let library = store.content?.library ?? [:]
        let earlier = logs.filter { $0 !== log && $0.startedAt < log.startedAt }.flatMap(\.sets)
        var names: [String] = []
        for id in Set(log.sets.map(\.exerciseId)) {
            let before = earlier.filter { $0.exerciseId == id }.map { StatSet(date: $0.completedAt, weight: $0.weight, reps: $0.reps) }
            let during = log.sets.filter { $0.exerciseId == id }.map { StatSet(date: $0.completedAt, weight: $0.weight, reps: $0.reps) }
            if ExerciseStats.isRecord(before: before, during: during), let name = library[id]?.name { names.append(name) }
        }
        return names.sorted()
    }

    var body: some View {
        let best = records
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(LinearGradient.brand)
                    .padding(.top, 40)
                    .accessibilityHidden(true)
                VStack(spacing: 6) {
                    Text("WORKOUT COMPLETE").font(.caption.weight(.semibold)).tracking(1.6).foregroundStyle(Color.gold)
                    Text(log.workoutName).font(.largeTitle.weight(.bold)).foregroundStyle(Color.ink)
                        .multilineTextAlignment(.center)
                }
                HStack(spacing: 12) {
                    tile("\(minutes)", "minutes")
                    tile("\(log.sets.count)", log.sets.count == 1 ? "set" : "sets")
                    tile(volume > 0 ? Int(volume.rounded()).formatted() : "-", "kg lifted")
                }
                if !best.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(best.count == 1 ? "NEW PERSONAL BEST" : "NEW PERSONAL BESTS")
                            .font(.caption.weight(.semibold)).tracking(1.6).foregroundStyle(Color.gold)
                        ForEach(best, id: \.self) { name in
                            Label(name, systemImage: "trophy.fill").foregroundStyle(Color.ink)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                    .accessibilityElement(children: .combine)
                }
                if log.sets.isEmpty {
                    Text("No sets were ticked this time. Showing up still counts.")
                        .font(.footnote).foregroundStyle(Color.inkMuted).multilineTextAlignment(.center)
                }
                Button(action: onDone) {
                    Text("Done").font(.headline).foregroundStyle(Color.night)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(LinearGradient.brand, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("recapDone")
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color.night.ignoresSafeArea())
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.weight(.bold).monospacedDigit()).foregroundStyle(Color.ink)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption).foregroundStyle(Color.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
