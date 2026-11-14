import SwiftUI
import SwiftData
import SteadyCore

enum ProgramBuilderSync {
    /// Turns stored drafts into programs and hands them to the content store.
    @MainActor
    static func refresh(_ stored: [CustomProgram], store: ContentStore) {
        let main = Set((store.content?.library.values.filter(\.isMainLift).map(\.id)) ?? [])
        store.setCustomPrograms(stored.compactMap { try? $0.draft?.makeProgram(mainLiftIds: main) })
    }

    @MainActor
    static func save(_ draft: ProgramDraft, in context: ModelContext, store: ContentStore) {
        let id = draft.id
        if let existing = try? context.fetch(FetchDescriptor<CustomProgram>(predicate: #Predicate { $0.programId == id })).first {
            existing.update(draft)
        } else {
            context.insert(CustomProgram(draft: draft))
        }
        try? context.save()
        if let all = try? context.fetch(FetchDescriptor<CustomProgram>()) { refresh(all, store: store) }
    }
}

/// Build or edit your own program: its sessions, and for each exercise the sets, reps, effort and rest.
struct ProgramBuilderView: View {
    @State var draft: ProgramDraft
    let isNew: Bool
    @Environment(ContentStore.self) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var newWorkoutName = ""
    @State private var addingWorkout = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Program name", text: $draft.name)
                        .accessibilityIdentifier("programName")
                    Stepper(value: $draft.weeks, in: 1...52) {
                        LabeledContent("Length", value: "\(draft.weeks) week\(draft.weeks == 1 ? "" : "s")")
                    }
                    TextField("Notes (optional)", text: $draft.notes, axis: .vertical).lineLimit(1...4)
                } footer: {
                    Text("Every week repeats these sessions. Weights go up from what you log: reach the top of the rep range on every set and the app suggests more.")
                }
                Section {
                    ForEach($draft.workouts) { $w in
                        NavigationLink {
                            WorkoutBuilderView(workout: $w)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(w.name)
                                Text(w.slots.isEmpty ? "No exercises yet" : "\(w.slots.count) exercises · about \(w.estimatedMinutes) min")
                                    .font(.caption).foregroundStyle(w.slots.isEmpty ? Color.gold : .secondary)
                            }
                        }
                    }
                    .onDelete { draft.workouts.remove(atOffsets: $0) }
                    .onMove { draft.workouts.move(fromOffsets: $0, toOffset: $1) }
                    Button { newWorkoutName = "Day \(draft.workouts.count + 1)"; addingWorkout = true } label: {
                        Label("Add a session", systemImage: "plus")
                    }
                    .accessibilityIdentifier("addSession")
                } header: { Text("Sessions each week") } footer: {
                    Text("Sessions run in this order. Drag to reorder with Edit, or swipe to delete.")
                }
            }
            .themedList()
            .navigationTitle(isNew ? "New program" : "Edit program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        ProgramBuilderSync.save(draft, in: context, store: store)
                        dismiss()
                    }
                    .disabled(!draft.isComplete)
                    .accessibilityIdentifier("saveProgram")
                }
                ToolbarItem(placement: .bottomBar) { EditButton() }
            }
            .alert("New session", isPresented: $addingWorkout) {
                TextField("Name, for example Upper A", text: $newWorkoutName)
                Button("Add") {
                    let name = newWorkoutName.trimmingCharacters(in: .whitespaces)
                    draft.workouts.append(WorkoutDraft(name: name.isEmpty ? "Day \(draft.workouts.count + 1)" : name))
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

/// One session: its exercises in order.
struct WorkoutBuilderView: View {
    @Binding var workout: WorkoutDraft
    @Environment(ContentStore.self) private var store
    @State private var picking = false
    @State private var editingSlot: SlotDraft.ID?

    var body: some View {
        Form {
            Section("Session name") {
                TextField("Name", text: $workout.name)
            }
            Section {
                ForEach($workout.slots) { $slot in
                    Button { editingSlot = slot.id } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(slot.exerciseName).foregroundStyle(Color.ink)
                            Text(slot.summary).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { workout.slots.remove(atOffsets: $0) }
                .onMove { workout.slots.move(fromOffsets: $0, toOffset: $1) }
                Button { picking = true } label: { Label("Add exercise", systemImage: "plus") }
                    .accessibilityIdentifier("builderAddExercise")
            } header: { Text("Exercises") } footer: {
                Text(workout.slots.isEmpty ? "Add at least one exercise." : "About \(workout.estimatedMinutes) min including warm-up and cool-down. Tap an exercise to change its sets, reps, effort and rest.")
            }
        }
        .themedList()
        .navigationTitle(workout.name.isEmpty ? "Session" : workout.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { EditButton() } }
        .sheet(isPresented: $picking) {
            ExercisePicker { id in
                let ex = store.content?.library[id]
                workout.slots.append(SlotDraft(exerciseId: id, exerciseName: ex?.name ?? id,
                                               repMin: ex?.timed == true ? 30 : 8, repMax: ex?.timed == true ? 45 : 12,
                                               restSeconds: ex?.isMainLift == true ? 150 : 90,
                                               perSide: ex?.unilateral ?? false))
            }
        }
        .sheet(item: Binding(get: { editingSlot.flatMap { id in workout.slots.firstIndex { $0.id == id } }.map { SlotIndex(index: $0) } },
                             set: { editingSlot = $0.map { workout.slots[$0.index].id } })) { s in
            SlotEditor(slot: $workout.slots[s.index])
        }
    }

    private struct SlotIndex: Identifiable { let index: Int; var id: Int { index } }
}

/// Sets, reps, effort and rest for one exercise.
struct SlotEditor: View {
    @Binding var slot: SlotDraft
    @Environment(\.dismiss) private var dismiss

    private var usesEffort: Binding<Bool> {
        Binding(get: { slot.rirMin != nil }, set: { on in
            slot.rirMin = on ? 2 : nil
            slot.rirMax = on ? 3 : nil
        })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $slot.sets, in: 1...10) { LabeledContent("Sets", value: "\(slot.sets)") }
                    Stepper(value: Binding(get: { slot.repMin }, set: { slot.repMin = $0; if slot.repMax < $0 { slot.repMax = $0 } }), in: 1...100) {
                        LabeledContent("Reps, lowest", value: "\(slot.repMin)")
                    }
                    Stepper(value: Binding(get: { slot.repMax }, set: { slot.repMax = max($0, slot.repMin) }), in: 1...100) {
                        LabeledContent("Reps, highest", value: "\(slot.repMax)")
                    }
                    Toggle("Each side", isOn: $slot.perSide)
                } header: { Text(slot.exerciseName) } footer: {
                    Text("Use the same number twice for a fixed target, for example 5 and 5.")
                }
                Section {
                    Toggle("Set an effort target", isOn: usesEffort)
                    if slot.rirMin != nil {
                        Stepper(value: Binding(get: { slot.rirMin ?? 2 }, set: { slot.rirMin = $0; if (slot.rirMax ?? $0) < $0 { slot.rirMax = $0 } }),
                                in: 0...5, step: 1) {
                            LabeledContent("Reps in reserve, from", value: NumberText.format(slot.rirMin ?? 2))
                        }
                        Stepper(value: Binding(get: { slot.rirMax ?? 3 }, set: { slot.rirMax = max($0, slot.rirMin ?? 0) }),
                                in: 0...5, step: 1) {
                            LabeledContent("to", value: NumberText.format(slot.rirMax ?? 3))
                        }
                    }
                } footer: {
                    Text("Reps in reserve: how many more you could have done. 2-3 is a common working range.")
                }
                Section {
                    Stepper(value: $slot.restSeconds, in: 0...600, step: 15) {
                        LabeledContent("Rest", value: slot.restSeconds >= 60 ? "\(NumberText.format(Double(slot.restSeconds) / 60)) min" : "\(slot.restSeconds) s")
                    }
                }
            }
            .themedList()
            .navigationTitle("Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
