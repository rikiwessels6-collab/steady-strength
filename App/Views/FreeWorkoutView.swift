import SwiftUI
import SwiftData
import SteadyCore

/// An open workout: no program, you choose the exercises as you go. Your logged sets still feed
/// progression suggestions, records, and weekly volume. It does not move your program on.
enum FreeWorkout {
    static func start(in context: ModelContext) -> WorkoutLog {
        let log = WorkoutLog(programId: "open", weekNumber: 0, workoutPosition: 0, workoutName: "Open workout",
                             version: .standard, swaps: [:])
        log.isFreestyle = true
        context.insert(log)
        try? context.save()
        return log
    }

    /// Slot numbers for exercises added to a program session start here, clear of the program's own slots.
    static let extraBase = 3000

    /// An added exercise as a card: 3 sets to start, and always one more empty row once those are done.
    static func item(_ id: String, order: Int, log: WorkoutLog, content: BundledContent) -> PlannedExercise {
        let ex = content.library[id]
        let done = log.sets.filter { $0.slotOrder == order }.count
        return PlannedExercise(moduleExerciseId: id, name: ex?.name ?? "Exercise", id: order, sets: max(3, done + 1),
                               repMin: 8, repMax: 12, restSeconds: 90, perSide: ex?.unilateral ?? false)
    }

    /// Removes an added exercise that has no sets yet, and closes the gap in the sets recorded for the ones after it.
    /// `base` is 0 in an open workout and `extraBase` in a program session.
    static func remove(at index: Int, from log: WorkoutLog, base: Int = 0) {
        guard log.freeExerciseIds.indices.contains(index),
              !log.sets.contains(where: { $0.slotOrder == base + index }) else { return }
        log.freeExerciseIds.remove(at: index)
        for s in log.sets where s.slotOrder > base + index && s.slotOrder < base + 1000 { s.slotOrder -= 1 }
    }
}

/// Opens any workout, finished or not, in the right screen. Used by Today and by Workout history.
struct WorkoutLogEditor: View {
    let log: WorkoutLog
    @Environment(ContentStore.self) private var store

    var body: some View {
        if log.isFreestyle {
            FreeWorkoutView(log: log)
        } else if let program = store.content?.program(log.programId),
                  let week = program.weeks.first(where: { $0.number == log.weekNumber }),
                  let workout = week.workouts.first(where: { $0.position == log.workoutPosition }) {
            ActiveWorkoutView(log: log, program: program, workout: workout)
        } else {
            ContentUnavailableView("Can't open this workout", systemImage: "exclamationmark.triangle",
                                   description: Text("The program it came from isn't available. Its sets are still in your history."))
        }
    }
}

struct FreeWorkoutView: View {
    @Bindable var log: WorkoutLog
    @Environment(ContentStore.self) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var plans: [TrainingPlan]
    @Query private var logs: [WorkoutLog]
    @State private var restEndsAt: Date?
    @State private var restTotal = 90
    @State private var infoFor: String?
    @State private var picking = false
    @State private var confirmFinish = false
    @State private var confirmDiscard = false
    @State private var showRecap = false
    @State private var loggingCardio = false
    @State private var latestSet: SetLog?
    @State private var saveError = false
    private var nextUpText: String? { nil }
    @Query private var appSettings: [AppSettings]
    @FocusState private var focused: Bool

    var body: some View {
        if let content = store.content {
            let items = log.freeExerciseIds.enumerated().map { FreeWorkout.item($1, order: $0, log: log, content: content) }
            let completed = Dictionary(grouping: log.sets, by: \.slotOrder).mapValues { Set($0.map(\.setIndex)) }
            let upcoming = WorkoutSetOrder.next(in: items, completed: completed, extraSets: [:])
            ScrollView {
                VStack(spacing: 16) {
                    WorkoutHeader(name: log.workoutName, version: .standard, week: 0, done: log.sets.count,
                                  total: max(items.reduce(0) { $0 + $1.sets }, log.sets.count), started: log.startedAt,
                                  eyebrow: "NO PROGRAM · YOUR CHOICE")
                    if items.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "dumbbell").font(.largeTitle).foregroundStyle(Color.gold)
                            Text("Add your first exercise").font(.headline)
                            Text("Choose from the exercise list or create your own. Your sets count towards your records and weekly volume.")
                                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity).padding(24).card()
                    }
                    ForEach(items) { item in
                        let ex = content.library[item.exerciseId]
                        let plan = plans.first
                        VStack(spacing: 6) {
                            ExerciseCard(item: item, log: log, exercise: ex,
                                         suggestion: Progression.suggest(for: item, exercise: ex,
                                                                         history: WorkoutPlanner.history(item.exerciseId, logs: logs.filter { $0 !== log }),
                                                                         oneRepMaxes: plan?.oneRepMaxes ?? [:],
                                                                         increment: plan?.upperIncrement ?? 2.5),
                                         isSwapped: false, canSwap: false,
                                         lastTime: WorkoutPlanner.lastTime(item.exerciseId, logs: logs.filter { $0 !== log }),
                                         focused: $focused,
                                         onSetDone: { set in latestSet = set; setDone(item) }, onSwap: {}, onInfo: { infoFor = item.exerciseId })
                            if !log.sets.contains(where: { $0.slotOrder == item.id }) {
                                Button("Remove \(item.name)", role: .destructive) {
                                    FreeWorkout.remove(at: item.id, from: log)
                                    try? context.save()
                                }
                                .font(.footnote)
                            }
                        }
                    }
                    Button { picking = true } label: {
                        Label("Add exercise", systemImage: "plus").font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("addExercise")
                    Button { loggingCardio = true } label: {
                        Label("Log cardio", systemImage: "heart.circle").font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    VStack(spacing: 10) {
                        if log.finishedAt != nil {
                            Button { try? context.save(); dismiss() } label: {
                                Text("Save changes").font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("saveChanges")
                        } else {
                            Button { if log.sets.isEmpty { confirmDiscard = true } else { confirmFinish = true } } label: {
                                Text("Finish workout").font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("finishWorkout")
                            Button("Discard workout", role: .destructive) { confirmDiscard = true }.font(.subheadline)
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.night.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if log.finishedAt == nil && !focused {
                    let controls = VStack(spacing: 6) {
                        if let end = restEndsAt {
                            RestTimerBar(endsAt: end, total: restTotal,
                                         onAdd: { restEndsAt = end.addingTimeInterval(30); restTotal += 30 },
                                         onLess: { restEndsAt = end.addingTimeInterval(-15); restTotal = max(15, restTotal - 15) },
                                         onDone: { restEndsAt = nil })
                        }
                        if let upcoming {
                            let item = items[upcoming.exerciseIndex]
                            let exercise = content.library[item.exerciseId]
                            let history = logs.filter { $0 !== log }
                            let suggestion = Progression.suggest(for: item, exercise: exercise,
                                                                  history: WorkoutPlanner.history(item.exerciseId, logs: history),
                                                                  oneRepMaxes: plans.first?.oneRepMaxes ?? [:],
                                                                  increment: plans.first?.upperIncrement ?? 2.5)
                            let previous = log.sets.filter { $0.slotOrder == item.id }.max { $0.setIndex < $1.setIndex }
                            QuickSetPanel(item: item, index: upcoming.setIndex, setCount: item.sets,
                                          loadable: exercise?.loadable ?? true,
                                          weight: WorkoutPlanner.quickWeight(item, exercise, suggestion, previous, log: log),
                                          lastTime: WorkoutPlanner.lastTime(item.exerciseId, logs: history),
                                          undo: undoAction) { weight, reps in
                                do {
                                    guard let set = try WorkoutPlanner.recordSet(item, index: upcoming.setIndex,
                                                                                 weight: weight, reps: reps, log: log, context: context) else { return }
                                    latestSet = set
                                    setDone(item)
                                } catch { saveError = true }
                            }
                            .id("\(item.id):\(item.exerciseId):\(upcoming.setIndex)")
                        } else if let undoAction {
                            Button("Undo last set", action: undoAction).frame(minHeight: 44)
                        }
                    }
                    controls.background(.regularMaterial)
                }
            }
            .alert("Couldn’t update the set", isPresented: $saveError) { Button("OK", role: .cancel) {} }
            .animation(.snappy, value: restEndsAt)
            .task(id: restEndsAt) {
                // A notification for a locked phone (if switched on), and a tap on the wrist or hand when rest ends in the app.
                guard let end = restEndsAt else { RestAlert.cancel(); await RestLiveActivity.end(); return }
                if appSettings.first?.restAlerts == true { await RestAlert.schedule(at: end) }
                await RestLiveActivity.show(workout: log.workoutName, start: .now, end: end, next: nextUpText)
                let wait = end.timeIntervalSinceNow
                if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
                guard !Task.isCancelled else { return }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                await RestLiveActivity.end()
            }
            .onDisappear {
                // Leaving the workout clears the lock-screen timer; locking the phone does not.
                Task { await RestLiveActivity.end() }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Later") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = false }.fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $loggingCardio) { CardioLogSheet() }
            .sheet(isPresented: $picking) {
                ExercisePicker { id in
                    log.freeExerciseIds.append(id)
                    try? context.save()
                }
            }
            .sheet(item: Binding(get: { infoFor.map { InfoID(id: $0) } }, set: { infoFor = $0?.id })) { info in
                ExerciseSheet(exerciseId: info.id)
            }
            .confirmationDialog("Finish this workout?", isPresented: $confirmFinish, titleVisibility: .visible) {
                Button("Finish") {
                    log.finishedAt = .now
                    try? context.save()
                    HealthSync.saveIfWanted(log, settings: appSettings.first, context: context)
                    showRecap = true
                }
            } message: { Text("It is saved to your history. Your program stays where it was.") }
            .fullScreenCover(isPresented: $showRecap) {
                WorkoutRecapView(log: log, onDone: {
                    showRecap = false
                    dismiss()
                }, onAddMore: { showRecap = false })
            }
            .confirmationDialog("Discard this workout?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) {
                    context.delete(log)
                    try? context.save()
                    dismiss()
                }
            } message: { Text("Nothing from this session is kept.") }
        }
    }

    private var undoAction: (() -> Void)? {
        guard let set = latestSet, log.sets.contains(where: { $0 === set }) else { return nil }
        return {
            context.delete(set)
            do {
                try context.save()
                latestSet = nil
                restEndsAt = nil
            } catch {
                context.rollback()
                saveError = true
            }
        }
    }

    private struct InfoID: Identifiable { let id: String }

    private func setDone(_ item: PlannedExercise) {
        focused = false
        restTotal = item.restSeconds
        restEndsAt = Date.now.addingTimeInterval(TimeInterval(item.restSeconds))
    }
}
