import SwiftUI
import SteadyCore

struct WorkoutAdjustmentSheet: View {
    enum Focus: String, Identifiable {
        case shorter, swap, move
        var id: Self { self }
        var title: String {
            switch self {
            case .shorter: "Shorter session"
            case .swap: "Swap exercise"
            case .move: "Move to another day"
            }
        }
    }

    let program: Program
    let workout: ProgramWorkout
    let week: ProgramWeek
    let equipment: Set<String>
    let preferredDay: Date
    let focus: Focus
    let onSave: (SessionAdjustment) -> Void
    @Environment(ContentStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var adjustment: SessionAdjustment
    @State private var changing: PlannedExercise?

    init(program: Program, workout: ProgramWorkout, week: ProgramWeek, equipment: Set<String>,
         preferredDay: Date, focus: Focus, adjustment: SessionAdjustment, onSave: @escaping (SessionAdjustment) -> Void) {
        self.program = program
        self.workout = workout
        self.week = week
        self.equipment = equipment
        self.preferredDay = preferredDay
        self.focus = focus
        self.onSave = onSave
        var draft = adjustment
        if focus == .shorter && draft.version == .standard { draft.version = .express }
        _adjustment = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            if let content = store.content {
                let plan = WorkoutPlanner.plan(program: program, workout: workout, version: adjustment.version,
                                               content: content, equipment: equipment, chosenSwaps: adjustment.swaps, week: week.number)
                Form {
                    switch focus {
                    case .shorter:
                        Picker("Session length", selection: $adjustment.version) {
                            ForEach(SessionVersion.allCases) { version in Text(version.label).tag(version) }
                        }
                        Text(adjustment.version.detail).font(.footnote).foregroundStyle(.secondary)
                    case .move:
                        DatePicker("New day", selection: moveDate, in: Calendar.current.startOfDay(for: .now)..., displayedComponents: .date)
                            .accessibilityIdentifier("moveWorkoutDate")
                        if adjustment.movedTo != nil {
                            Button("Use usual schedule") { adjustment.movedFrom = nil; adjustment.movedTo = nil }
                        }
                    case .swap:
                        EmptyView()
                    }
                    Section("Revised session") {
                        LabeledContent("Day", value: (adjustment.movedTo ?? preferredDay).formatted(date: .complete, time: .omitted))
                        LabeledContent("Version", value: adjustment.version.label)
                        ForEach(plan.plan) { item in
                            if focus == .swap {
                                Button { changing = item } label: {
                                    Label("\(item.name) · \(item.sets) sets", systemImage: "arrow.triangle.swap")
                                }
                                .accessibilityHint("Choose an alternative exercise")
                            } else {
                                LabeledContent(item.name, value: "\(item.sets) sets")
                            }
                        }
                    }
                }
                .sheet(item: $changing) { item in
                    SwapSheet(item: item, content: content, equipment: equipment,
                              maxDifficulty: program.maxSwapDifficulty ?? 3) { id in
                        adjustment.swaps[item.id] = id
                    }
                }
                .themedList()
                .navigationTitle(focus.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Apply") { onSave(adjustment); dismiss() }
                            .accessibilityIdentifier("applyWorkoutAdjustment")
                    }
                }
            }
        }
    }

    private var moveDate: Binding<Date> {
        Binding(get: {
            max(Calendar.current.startOfDay(for: .now), adjustment.movedTo ?? preferredDay)
        }, set: { date in
            let day = Calendar.current.startOfDay(for: date)
            let original = adjustment.movedFrom ?? preferredDay
            adjustment.movedFrom = day == original ? nil : original
            adjustment.movedTo = day == original ? nil : day
        })
    }
}
