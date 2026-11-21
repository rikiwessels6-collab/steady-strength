import SwiftUI
import SwiftData
import SteadyCore

// MARK: - Building today's session

enum WorkoutPlanner {
    /// Programs for beginners: weeks 1-4 are an easy on-ramp (2 sets, about 3-4 reps in reserve).
    static let onRampPrograms: Set<String> = ["ss-strength-foundations", "ss-strong-for-life"]

    /// A suggested weight scaled by the session's load factor, kept to 0.5 kg steps.
    static func scaled(_ w: Double, factor: Double) -> Double {
        factor == 1 ? w : max(0, (w * factor * 2).rounded(.down) / 2)
    }

    /// Today's exercises: the version applied, then swaps for missing equipment
    /// (automatic) and any the user chose (stored on the log).
    static func plan(program: Program, workout: ProgramWorkout, version: SessionVersion, content: BundledContent,
                     equipment: Set<String>, chosenSwaps: [Int: String], week: Int = 99) -> (plan: [PlannedExercise], swaps: [Int: String]) {
        var plan = SessionBuilder.build(workout, version: version, library: content.library)
        if onRampPrograms.contains(program.id) { plan = SessionBuilder.applyOnRamp(plan, week: week) }
        var swaps = chosenSwaps
        for i in plan.indices {
            let slot = workout.slots.first { $0.order == plan[i].id }
            if let chosen = chosenSwaps[plan[i].id] {
                apply(&plan[i], chosen, content)
                continue
            }
            let pick = Substitution.choose(plan[i].exerciseId, library: content.library, available: equipment,
                                           maxDifficulty: program.maxSwapDifficulty ?? 3,
                                           slotAlternatives: slot?.alternativeIds ?? [])
            if let id = pick.id, id != plan[i].exerciseId {
                apply(&plan[i], id, content)
                swaps[plan[i].id] = id
            }
        }
        return (plan, swaps)
    }

    static func apply(_ e: inout PlannedExercise, _ newId: String, _ content: BundledContent) {
        guard let ex = content.library[newId] else { return }
        let old = content.library[e.exerciseId]
        e.exerciseId = newId
        e.name = ex.name
        if ex.unilateral && !(old?.unilateral ?? false) { e.perSide = true; e.repsText = e.repsText.hasSuffix("each side") ? e.repsText : e.repsText + " each side" }
    }

    /// Where an empty field starts the first time: the bar, light dumbbells, or a light pin.
    static func defaultStartWeight(_ ex: Exercise?) -> Double {
        guard let e = ex, e.loadable else { return 0 }
        let kit = Set(e.equipment.flatMap { $0.split(separator: "/").map(String.init) })
        if kit.contains("barbell") || kit.contains("trap_bar") { return 20 }
        if kit.contains("ez_bar") { return 10 }
        if kit.contains("dumbbells") || kit.contains("kettlebell") { return e.unilateral ? 6 : 8 }
        return 10
    }

    static func suggestion(for item: PlannedExercise, exercise: Exercise?, logs: [WorkoutLog],
                           trainingPlan: TrainingPlan) -> LoadSuggestion {
        let lower = exercise?.tier == "main"
            && (exercise?.pattern.hasPrefix("squat") == true || exercise?.pattern.hasPrefix("hinge") == true)
        return Progression.suggest(for: item, exercise: exercise, history: history(item.exerciseId, logs: logs),
                                   oneRepMaxes: trainingPlan.oneRepMaxes,
                                   increment: lower ? trainingPlan.lowerIncrement : trainingPlan.upperIncrement)
    }

    static func baseWeight(for suggestion: LoadSuggestion, item: PlannedExercise,
                           log: WorkoutLog) -> Double? {
        guard let weight = suggestion.weight else { return nil }
        let usePrevious = suggestion.needsConfirmation && !log.acceptedSuggestions.contains(item.exerciseId)
        return scaled(usePrevious ? suggestion.previousWeight ?? weight : weight, factor: log.loadFactor)
    }

    static func quickWeight(_ item: PlannedExercise, _ exercise: Exercise?, _ suggestion: LoadSuggestion,
                            _ previous: SetLog?, log: WorkoutLog) -> Double {
        guard let previous else {
            return baseWeight(for: suggestion, item: item, log: log) ?? defaultStartWeight(exercise)
        }
        guard exercise?.loadable != false, exercise?.timed != true else { return previous.weight }
        let advice = SetAdvisor.next(lastWeight: previous.weight, lastReps: previous.reps,
                                    minReps: previous.minReps ?? item.minimumReps(set: previous.setIndex),
                                    topReps: previous.targetReps ?? item.targetReps(set: previous.setIndex),
                                    step: Progression.increment(for: exercise))
        return advice.kind == .lighter ? advice.weight : previous.weight
    }

    @MainActor
    static func recordSet(_ item: PlannedExercise, index: Int, weight: Double, reps: Int,
                          log: WorkoutLog, context: ModelContext) throws -> SetLog? {
        guard weight.isFinite, weight >= 0, reps > 0,
              !log.sets.contains(where: { $0.slotOrder == item.id && $0.setIndex == index }) else { return nil }
        let set = SetLog(exerciseId: item.exerciseId, slotOrder: item.id, setIndex: index, weight: weight, reps: reps,
                         rpe: nil, targetSets: item.sets, targetReps: item.targetReps(set: index),
                         minReps: item.minimumReps(set: index), maxRPE: item.effortType == .rpe ? item.effortMax : nil)
        context.insert(set)
        set.workout = log
        do { try context.save(); return set }
        catch { context.rollback(); throw error }
    }

    /// "Last time (12 Nov): 60 kg × 8, 8, 7", from the most recent finished session with this exercise.
    static func lastTime(_ exerciseId: String, logs: [WorkoutLog]) -> String? {
        guard let h = history(exerciseId, logs: logs).last else { return nil }
        let text = LastTime.summary(h.sets)
        guard !text.isEmpty else { return nil }
        return "Last time (\(h.date.formatted(.dateTime.day().month(.abbreviated)))): \(text)"
    }

    /// Past finished sessions of one exercise, oldest first, for progression.
    static func history(_ exerciseId: String, logs: [WorkoutLog]) -> [ExerciseHistory] {
        logs.filter { $0.finishedAt != nil }
            .sorted { $0.startedAt < $1.startedAt }
            .compactMap { log in
                let sets = log.sets.filter { $0.exerciseId == exerciseId }.sorted { $0.setIndex < $1.setIndex }
                guard let first = sets.first else { return nil }
                return ExerciseHistory(date: log.startedAt,
                                       sets: sets.map { LoggedSet(weight: $0.weight, reps: $0.reps, rpe: $0.rpe) },
                                       targetSets: first.targetSets, targetTop: sets.map(\.targetReps),
                                       targetMin: sets.map(\.minReps), maxRPE: first.maxRPE)
            }
    }
}

// MARK: - Start sheet

struct StartWorkoutSheet: View {
    let program: Program
    let week: ProgramWeek
    let workout: ProgramWorkout
    var initialVersion: SessionVersion = .standard
    let onStart: (SessionVersion, Readiness.Choice, ReasonCode?) -> Void
    @Environment(ContentStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var version: SessionVersion = .standard
    @State private var answers = ReadinessAnswers()
    @State private var checkOpen = false
    @State private var choice: Readiness.Choice = .asPlanned
    @State private var easeBack = true
    @Query(filter: #Predicate<WorkoutLog> { $0.finishedAt != nil }, sort: \WorkoutLog.startedAt, order: .reverse) private var finished: [WorkoutLog]

    private var advice: Readiness.Advice { Readiness.advise(answers) }
    private var effectiveVersion: SessionVersion { choice == .fewerSets ? .lowEnergy : version }

    var body: some View {
        NavigationStack {
            Form {
                returnSection
                readinessSection
                if let note = week.phaseNote, week.lowFatigueOptional != true {
                    Section("Week \(week.number) · \(week.phase ?? "")") { Text(note).font(.footnote) }
                }
                Section {
                    ForEach(SessionVersion.allCases) { v in
                        Button { version = v } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(v.label).foregroundStyle(.primary)
                                    Text("\(v.detail) About \(minutes(v)) min.").font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if version == v { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }
                        .accessibilityAddTraits(version == v ? .isSelected : [])
                        .accessibilityIdentifier("version-\(v.rawValue)")
                    }
                } header: { Text("How much today?") } footer: {
                    if week.lowFatigueOptional == true {
                        Text("\(week.phase ?? "Lower-fatigue week"): \(week.phaseNote ?? "Low energy is a good choice if you're feeling run down.")")
                    } else {
                        Text("Short on time or energy? A shorter version keeps your progress going; the program itself doesn't change.")
                    }
                }
            }
            .onAppear { version = initialVersion }
            .navigationTitle(workout.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        let easing = returnAdvice != nil && easeBack && choice == .asPlanned
                        onStart(effectiveVersion, easing ? .lowerLoad : choice, easing ? ReasonCode.missedReturnReduction : (checkOpen ? advice.code : nil))
                        dismiss()
                    }.accessibilityIdentifier("startWorkout")
                }
            }
        }
    }

    private var returnAdvice: ReturnAdvice? { ReturnToTraining.advice(lastSession: finished.first?.finishedAt) }

    @ViewBuilder private var returnSection: some View {
        if let advice = returnAdvice {
            Section {
                Toggle(isOn: $easeBack) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ease back in")
                        Text(advice.message).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("easeBack")
            }
        }
    }

    @ViewBuilder private var readinessSection: some View {
        Section {
            DisclosureGroup("How are you today? (optional)", isExpanded: $checkOpen) {
                Picker("Sleep", selection: $answers.sleep) {
                    ForEach(ReadinessAnswers.Level.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker("Energy", selection: $answers.energy) {
                    ForEach(ReadinessAnswers.Level.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker("Anything bothering you?", selection: $answers.concern) {
                    ForEach(ReadinessAnswers.Concern.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                TextField("Note (stays on this phone)", text: $answers.note)
                if let stop = advice.stopMessage {
                    Label(stop, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color.gold).font(.callout)
                }
                ForEach(Readiness.Choice.allCases) { c in
                    Button { choice = c } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.label + (c == advice.suggested ? " (suggested)" : "")).foregroundStyle(.primary)
                                Text(c.detail).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if choice == c { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }
                    }
                    .accessibilityAddTraits(choice == c ? .isSelected : [])
                }
            }
            .onChange(of: answers) { _, _ in choice = advice.suggested }
        } footer: {
            Text("These are suggestions, not medical advice. You decide.")
        }
    }

    private func minutes(_ v: SessionVersion) -> Int {
        guard let c = store.content else { return workout.estimatedMinutes }
        return SessionBuilder.estimatedMinutes(SessionBuilder.build(workout, version: v, library: c.library), version: v)
    }
}

// MARK: - Active workout

struct ActiveWorkoutView: View {
    @Bindable var log: WorkoutLog
    let program: Program
    let workout: ProgramWorkout
    @Environment(ContentStore.self) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var plans: [TrainingPlan]
    @Query private var logs: [WorkoutLog]
    @State private var restEndsAt: Date?
    @State private var restTotal: Int = 90
    @State private var swapFor: PlannedExercise?
    @State private var infoFor: PlannedExercise?
    @State private var confirmFinish = false
    @State private var confirmDiscard = false
    @State private var showRecap = false
    @State private var addingExercise = false
    @State private var loggingCardio = false
    @State private var nextUp: String?
    @State private var latestSet: SetLog?
    @State private var saveError = false
    private var nextUpText: String? { nextUp }
    @Query private var appSettings: [AppSettings]
    @FocusState private var focused: Bool

    var body: some View {
        if let content = store.content, let trainingPlan = plans.first {
            let built = WorkoutPlanner.plan(program: program, workout: workout, version: log.version, content: content,
                                            equipment: Set(trainingPlan.equipment), chosenSwaps: log.swaps, week: log.weekNumber)
            let extras = log.freeExerciseIds.enumerated().map {
                FreeWorkout.item($1, order: FreeWorkout.extraBase + $0, log: log, content: content)
            }
            let all = built.plan + extras
            let previousLogs = logs.filter { $0 !== log }
            let completed = Dictionary(grouping: log.sets, by: \.slotOrder).mapValues { Set($0.map(\.setIndex)) }
            let upcoming = WorkoutSetOrder.next(in: all, completed: completed, extraSets: log.extraSets)
            let totalSets = built.plan.reduce(0) { $0 + $1.sets + (log.extraSets[$1.id] ?? 0) } + extras.reduce(0) { $0 + $1.sets }
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    WorkoutHeader(name: log.workoutName, version: log.version, week: log.weekNumber,
                                  done: log.sets.count, total: totalSets, started: log.startedAt)
                    RoutineCard(kind: .warmup, version: log.version)
                    ForEach(Array(all.enumerated()), id: \.element.id) { index, item in
                        let ex = content.library[item.exerciseId]
                        let isExtra = item.id >= FreeWorkout.extraBase
                        VStack(spacing: 6) {
                        ExerciseCard(item: item, log: log, exercise: ex,
                                     suggestion: WorkoutPlanner.suggestion(for: item, exercise: ex,
                                                                           logs: previousLogs, trainingPlan: trainingPlan),
                                     isSwapped: item.exerciseId != item.originalExerciseId,
                                     canSwap: !isExtra,
                                     lastTime: WorkoutPlanner.lastTime(item.exerciseId, logs: logs.filter { $0 !== log }),
                                     extraSets: isExtra ? 0 : (log.extraSets[item.id] ?? 0),
                                     onAddSet: isExtra ? nil : { log.extraSets[item.id, default: 0] += 1; try? context.save() },
                                     onRemoveSet: isExtra ? nil : {
                                         let n = (log.extraSets[item.id] ?? 0) - 1
                                         log.extraSets[item.id] = n > 0 ? n : nil
                                         try? context.save()
                                     },
                                     focused: $focused,
                                     onSetDone: { set in
                                         latestSet = set
                                         setDone(item, index: index, plan: all, proxy: proxy)
                                     },
                                     onSwap: { swapFor = item },
                                     onInfo: { infoFor = item })
                            if isExtra, !log.sets.contains(where: { $0.slotOrder == item.id }) {
                                Button("Remove \(item.name)", role: .destructive) {
                                    FreeWorkout.remove(at: item.id - FreeWorkout.extraBase, from: log, base: FreeWorkout.extraBase)
                                    try? context.save()
                                }
                                .font(.footnote)
                            }
                        }
                        .id("ex-\(item.id)")
                    }
                    Button { addingExercise = true } label: {
                        Label("Add exercise", systemImage: "plus").font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("addExerciseToSession")
                    Button { loggingCardio = true } label: {
                        Label("Log cardio", systemImage: "heart.circle").font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    RoutineCard(kind: .cooldown, version: log.version)
                    VStack(spacing: 10) {
                        if log.finishedAt != nil {
                            // Reopened after finishing: saving never moves the program on a second time.
                            Button { try? context.save(); dismiss() } label: {
                                Text("Save changes").font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("saveChanges")
                        } else {
                            Button { confirmFinish = true } label: {
                                Text("Finish workout").font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("finishWorkout")
                            Button("Discard workout", role: .destructive) { confirmDiscard = true }
                                .font(.subheadline)
                        }
                    }
                    .padding(.top, 8)
                    .id("finish")
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if log.finishedAt == nil && !focused {
                    let controls = VStack(spacing: 6) {
                        if let end = restEndsAt {
                            RestTimerBar(endsAt: end, total: restTotal,
                                         onAdd: { restEndsAt = end.addingTimeInterval(30); restTotal += 30 },
                                         onLess: { restEndsAt = end.addingTimeInterval(-15); restTotal = max(15, restTotal - 15) },
                                         onDone: { restEndsAt = nil }, nextText: nextUp)
                        }
                        if let upcoming {
                            let item = all[upcoming.exerciseIndex]
                            let exercise = content.library[item.exerciseId]
                            let previous = log.sets.filter { $0.slotOrder == item.id }.max { $0.setIndex < $1.setIndex }
                            let suggestion = WorkoutPlanner.suggestion(for: item, exercise: exercise,
                                                                      logs: previousLogs, trainingPlan: trainingPlan)
                            QuickSetPanel(item: item, index: upcoming.setIndex,
                                          setCount: item.sets + (log.extraSets[item.id] ?? 0),
                                          loadable: exercise?.loadable ?? true,
                                          weight: WorkoutPlanner.quickWeight(item, exercise, suggestion, previous, log: log),
                                          lastTime: WorkoutPlanner.lastTime(item.exerciseId, logs: previousLogs),
                                          undo: undoAction) { weight, reps in
                                do {
                                    guard let set = try WorkoutPlanner.recordSet(item, index: upcoming.setIndex,
                                                                                 weight: weight, reps: reps, log: log, context: context) else { return }
                                    latestSet = set
                                    setDone(item, index: upcoming.exerciseIndex, plan: all, proxy: proxy)
                                } catch { saveError = true }
                            }
                            .id("\(item.id):\(item.exerciseId):\(upcoming.setIndex)")
                        } else {
                            HStack {
                                Button("Finish workout") { confirmFinish = true }
                                    .buttonStyle(.borderedProminent).frame(minHeight: 44)
                                    .accessibilityIdentifier("quickFinishWorkout")
                                if let undoAction {
                                    Button("Undo last set", action: undoAction).frame(minHeight: 44)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    controls.background(.regularMaterial)
                }
            }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.night.ignoresSafeArea())
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
            .sheet(item: $swapFor) { item in
                SwapSheet(item: item, content: content, equipment: Set(trainingPlan.equipment),
                          maxDifficulty: program.maxSwapDifficulty ?? 3) { newId in
                    log.swaps[item.id] = newId
                    try? context.save()
                }
            }
            .sheet(item: $infoFor) { item in
                ExerciseSheet(exerciseId: item.exerciseId, slot: workout.slots.first { $0.order == item.id },
                              maxDifficulty: program.maxSwapDifficulty ?? 3)
            }
            .confirmationDialog("Finish this workout?", isPresented: $confirmFinish, titleVisibility: .visible) {
                Button("Finish") {
                    log.finishedAt = .now
                    trainingPlan.nextSessionIndex += 1
                    try? context.save()
                    HealthSync.saveIfWanted(log, settings: appSettings.first, context: context)
                    showRecap = true
                }
            } message: { Text("Sets you didn't tick count as not done, and your next session moves on.") }
            .fullScreenCover(isPresented: $showRecap) {
                WorkoutRecapView(log: log, onDone: {
                    showRecap = false
                    dismiss()
                }, onAddMore: { showRecap = false })
            }
            .sheet(isPresented: $loggingCardio) { CardioLogSheet() }
            .sheet(isPresented: $addingExercise) {
                ExercisePicker { id in
                    log.freeExerciseIds.append(id)
                    try? context.save()
                }
            }
            .confirmationDialog("Discard this workout?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) {
                    context.delete(log)
                    try? context.save()
                    dismiss()
                }
            } message: { Text("Nothing from this session is kept, and it stays as your next session.") }
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
                nextUp = nil
            } catch {
                context.rollback()
                saveError = true
            }
        }
    }

    /// Rest after a set: none between superset partners, the round's rest after the last one.
    private func setDone(_ item: PlannedExercise, index: Int, plan: [PlannedExercise], proxy: ScrollViewProxy) {
        focused = false
        // Work out what comes next, and move the screen there once this exercise is finished.
        let rows = plan.map { p in (name: p.name, done: log.sets.filter { $0.slotOrder == p.id }.count,
                                    total: p.sets + (p.id >= FreeWorkout.extraBase ? 0 : (log.extraSets[p.id] ?? 0))) }
        nextUp = NextUp.text(remaining: rows, current: index)
        if rows.indices.contains(index), rows[index].done >= rows[index].total {
            let later = rows.indices.first { $0 > index && rows[$0].done < rows[$0].total }
            let target = later ?? rows.indices.first { rows[$0].done < rows[$0].total }
            withAnimation(.easeInOut) {
                if let t = target { proxy.scrollTo("ex-\(plan[t].id)", anchor: .top) } else { proxy.scrollTo("finish", anchor: .bottom) }
            }
        }
        let completed = Dictionary(grouping: log.sets, by: \.slotOrder).mapValues { Set($0.map(\.setIndex)) }
        if let group = item.supersetGroup, let next = WorkoutSetOrder.next(in: plan, completed: completed, extraSets: log.extraSets),
           plan[next.exerciseIndex].supersetGroup == group, next.exerciseIndex > index {
            restEndsAt = nil
            return
        }
        let rest = item.restSeconds > 0 ? item.restSeconds : 60
        restTotal = rest
        restEndsAt = Date.now.addingTimeInterval(TimeInterval(rest))
    }
}

/// The next set stays reachable while the full workout remains scrollable above it.
struct QuickSetPanel: View {
    let item: PlannedExercise
    let index: Int
    let setCount: Int
    let loadable: Bool
    let weight: Double
    let lastTime: String?
    let undo: (() -> Void)?
    let onLog: (Double, Int) -> Void
    @State private var enteredWeight: Double?
    @State private var enteredReps: Int?
    @State private var showDetails = false
    @FocusState private var focused: Bool
    @Environment(\.dynamicTypeSize) private var textSize

    private var prescribedCount: Int {
        if case .duration(_, let upper) = item.reps { return Int(upper.rounded()) }
        return item.targetReps(set: index) ?? 10
    }
    private var countLabel: String {
        if case .duration = item.reps { return "Seconds" }
        return "Reps"
    }
    private var reps: Int { enteredReps ?? prescribedCount }
    private var setLabel: String { "Set \(index + 1) of \(setCount)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if textSize.isAccessibilitySize {
                Button("Set details") { showDetails = true }
                    .frame(minHeight: 44)
                    .accessibilityHint("\(item.name), \(setLabel)")
            } else {
                summary
                HStack { fields }
            }
            HStack {
                Button {
                    focused = false
                    onLog(loadable ? (enteredWeight ?? weight) : 0, reps)
                } label: {
                    Text("Log set").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(reps <= 0 || (loadable && (!(enteredWeight ?? weight).isFinite || (enteredWeight ?? weight) < 0)))
                .accessibilityIdentifier("quickLogSet")
                .accessibilityHint("\(item.name), \(setLabel)")
                if let undo {
                    Button("Undo", action: undo).frame(minHeight: 44)
                        .accessibilityLabel("Undo last set").accessibilityIdentifier("quickUndoSet")
                }
            }
        }
        .padding(.horizontal).padding(.bottom, 6)
        .sheet(isPresented: $showDetails) {
            NavigationStack {
                Form {
                    Section { summary }
                    Section { fields }
                }
                .themedList()
                .navigationTitle("Set details")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showDetails = false } } }
            }
        }
        .onAppear { enteredWeight = weight; enteredReps = prescribedCount }
        .onChange(of: weight) { old, new in if enteredWeight == old { enteredWeight = new } }
    }

    @ViewBuilder private var summary: some View {
        Text(item.name).font(.headline).accessibilityAddTraits(.isHeader)
        Text("\(setLabel) · \(item.repsText)")
            .font(.subheadline).foregroundStyle(Color.inkMuted)
            .accessibilityIdentifier("quickSetNumber")
        if let lastTime { Text(lastTime).font(.footnote).foregroundStyle(Color.inkMuted) }
    }

    @ViewBuilder private var fields: some View {
        if loadable {
            LabeledContent("kg") {
                TextField("Weight", value: $enteredWeight, format: .number)
                    .keyboardType(.decimalPad).focused($focused).modifier(PillField())
                    .accessibilityLabel("Set weight in kilograms")
            }
        }
        LabeledContent(countLabel) {
            TextField(countLabel, value: $enteredReps, format: .number)
                .keyboardType(.numberPad).focused($focused).modifier(PillField())
                .accessibilityLabel(countLabel == "Seconds" ? "Set duration in seconds" : "Set repetitions")
        }
    }
}

struct WorkoutHeader: View {
    let name: String
    let version: SessionVersion
    let week: Int
    let done: Int
    let total: Int
    let started: Date
    /// Replaces the "WEEK n" line, for workouts that aren't part of a program.
    var eyebrow: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(eyebrow ?? "WEEK \(week)\(version == .standard ? "" : " · \(version.label.uppercased())")")
                        .font(.caption.weight(.semibold)).tracking(1.6).foregroundStyle(Color.gold)
                    Text(name).font(.largeTitle.weight(.bold))
                }
                Spacer()
                TimelineView(.periodic(from: started, by: 1)) { ctx in
                    Text(Duration.seconds(ctx.date.timeIntervalSince(started)), format: .time(pattern: .minuteSecond))
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Elapsed time")
                }
            }
            HStack(spacing: 12) {
                BrandProgress(value: Double(done) / Double(max(total, 1)))
                Text("\(done)/\(total) sets").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }
}

struct ExerciseCard: View {
    let item: PlannedExercise
    @Bindable var log: WorkoutLog
    let exercise: Exercise?
    let suggestion: LoadSuggestion
    let isSwapped: Bool
    var canSwap = true
    /// The previous session's sets for this exercise, if any.
    var lastTime: String? = nil
    /// Sets added beyond the prescription, and the buttons that add or remove one (nil hides them).
    var extraSets = 0
    var onAddSet: (() -> Void)? = nil
    var onRemoveSet: (() -> Void)? = nil
    var focused: FocusState<Bool>.Binding
    let onSetDone: (SetLog) -> Void
    let onSwap: () -> Void
    let onInfo: () -> Void
    @Environment(\.modelContext) private var context
    @Query private var appSettings: [AppSettings]
    @Query private var notes: [ExerciseNote]
    @State private var showPlates = false
    @State private var heavierAccepted: Double?
    @State private var saveError = false
    @Environment(\.dynamicTypeSize) private var textSize

    private var done: [SetLog] {
        log.sets.filter { $0.slotOrder == item.id }.sorted { $0.setIndex < $1.setIndex }
    }
    private var loadable: Bool { exercise?.loadable ?? true }
    private var accepted: Bool { log.acceptedSuggestions.contains(item.exerciseId) }
    private var declined: Bool { log.declinedSuggestions.contains(item.exerciseId) }
    /// Increases and deloads are only applied once you accept them.
    private var pendingConfirmation: Bool { suggestion.needsConfirmation && !accepted && !declined && done.isEmpty }
    private var suggestedWeight: Double? {
        WorkoutPlanner.baseWeight(for: suggestion, item: item, log: log)
    }
    /// Judged from the set just done: lighter is applied straight away, heavier only once you tap to accept it.
    private var advice: SetAdvice? {
        guard loadable, exercise?.timed != true, let last = done.last, done.count < item.sets + extraSets else { return nil }
        let a = SetAdvisor.next(lastWeight: last.weight, lastReps: last.reps,
                                minReps: last.minReps ?? item.minimumReps(set: last.setIndex),
                                topReps: last.targetReps ?? item.targetReps(set: last.setIndex),
                                step: Progression.increment(for: exercise))
        return a.kind == .keep ? nil : a
    }
    private var startWeight: Double {
        if let a = advice {
            if a.kind == .lighter { return a.weight }
            if a.kind == .heavier && heavierAccepted == a.weight { return a.weight }
        }
        return done.last?.weight ?? suggestedWeight ?? WorkoutPlanner.defaultStartWeight(exercise)
    }
    private var isBarbell: Bool {
        exercise?.equipment.contains { $0.contains("barbell") || $0.contains("ez_bar") || $0.contains("trap_bar") } ?? false
    }
    /// A guide for the warm-up before a heavy lift; never logged.
    private var warmup: [LoggedSet] {
        guard item.isMainLift, loadable, let settings = appSettings.first else { return [] }
        return Warmup.sets(style: Warmup.Style(rawValue: settings.warmupStyleRaw) ?? .percent, working: startWeight, bar: settings.barWeightKg)
    }
    private var myNote: String? {
        let text = notes.first { $0.exerciseId == item.exerciseId }?.text ?? ""
        return text.isEmpty ? nil : text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        if let g = item.supersetGroup { Chip(text: "SUPERSET \(g)", prominent: true) }
                        if item.isMainLift { Chip(text: "MAIN LIFT", prominent: false) }
                        if isSwapped { Chip(text: "SWAPPED", prominent: false) }
                    }
                    Button(action: onInfo) {
                        HStack(spacing: 6) {
                            Text(item.name).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Image(systemName: "info.circle").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Form cues and demo video")
                    Text(prescription).font(.subheadline).foregroundStyle(.secondary)
                    Button(action: onInfo) {
                        Label("How to do it", systemImage: "play.circle.fill")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.bordered).tint(Color.emerald).controlSize(.small)
                    .accessibilityIdentifier("howTo-\(item.id)")
                    if let lastTime {
                        Label(lastTime, systemImage: "clock.arrow.circlepath")
                            .font(.footnote.monospacedDigit()).foregroundStyle(Color.inkMuted)
                            .accessibilityIdentifier("lastTime")
                    }
                    if let myNote {
                        Label(myNote, systemImage: "note.text").font(.footnote).foregroundStyle(Color.gold)
                            .accessibilityLabel("Your note: \(myNote)")
                    }
                }
                Spacer()
                if canSwap {
                    Button(action: onSwap) {
                        Image(systemName: "arrow.triangle.swap")
                            .font(.body.weight(.semibold))
                            .frame(width: 40, height: 40)
                            .background(Color.surfaceRaised, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Swap \(item.name)")
                }
            }
            if let line = suggestionLine {
                Label(line, systemImage: suggestionIcon)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gold.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                if pendingConfirmation {
                    HStack(spacing: 10) {
                        Button("Use \(NumberText.format(WorkoutPlanner.scaled(suggestion.weight ?? 0, factor: log.loadFactor))) kg") {
                            log.acceptedSuggestions.append(item.exerciseId); try? context.save()
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("acceptSuggestion")
                        Button("Keep \(NumberText.format(WorkoutPlanner.scaled(suggestion.previousWeight ?? 0, factor: log.loadFactor))) kg") {
                            log.declinedSuggestions.append(item.exerciseId); try? context.save()
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("declineSuggestion")
                    }
                    .font(.subheadline)
                }
            }
            if loadable && isBarbell {
                Button { showPlates = true } label: {
                    Label("Plates for \(NumberText.format(startWeight)) kg", systemImage: "circle.grid.2x1")
                }
                .font(.footnote).buttonStyle(.bordered).tint(Color.gold)
                .accessibilityIdentifier("platesButton")
            }
            if !warmup.isEmpty {
                DisclosureGroup {
                    Text(warmup.map { "\(NumberText.format($0.weight)) kg × \($0.reps)" }.joined(separator: "   ·   "))
                        .font(.footnote.monospacedDigit()).foregroundStyle(Color.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text("Warm-up sets (a guide)").font(.footnote.weight(.semibold)).foregroundStyle(Color.inkMuted)
                }
                .tint(Color.gold)
            }
            VStack(spacing: 8) {
                if !textSize.isAccessibilitySize {
                HStack {
                    Text("SET").frame(width: 34, alignment: .leading)
                    Text(loadable ? "KG" : "LOAD").frame(maxWidth: .infinity)
                    Text("REPS").frame(maxWidth: .infinity)
                    Color.clear.frame(width: 44)
                }
                .font(.caption2.weight(.semibold)).tracking(1.2).foregroundStyle(Color.inkMuted.opacity(0.7))
                }
                ForEach(0..<(item.sets + extraSets), id: \.self) { i in
                    SetRow(index: i, item: item, logged: done.first { $0.setIndex == i },
                           startWeight: startWeight, loadable: loadable, focused: focused) { weight, reps in
                        do {
                            if let set = try WorkoutPlanner.recordSet(item, index: i, weight: weight, reps: reps,
                                                                      log: log, context: context) {
                                onSetDone(set)
                            }
                        } catch { saveError = true }
                    } onUndo: { set in
                        context.delete(set)
                        try? context.save()
                    } onEffort: { set, value in
                        set.rpe = value
                        try? context.save()
                    }
                }
                if onAddSet != nil || onRemoveSet != nil {
                    HStack(spacing: 10) {
                        if let onAddSet {
                            Button(action: onAddSet) { Label("Add set", systemImage: "plus") }
                                .accessibilityIdentifier("addSet-\(item.id)")
                        }
                        if extraSets > 0, let onRemoveSet,
                           !done.contains(where: { $0.setIndex == item.sets + extraSets - 1 }) {
                            Button(role: .destructive, action: onRemoveSet) { Label("Remove set", systemImage: "minus") }
                        }
                        Spacer()
                        if extraSets > 0 {
                            Text("+\(extraSets) extra").font(.caption).foregroundStyle(Color.inkMuted)
                        }
                    }
                    .font(.footnote.weight(.semibold)).buttonStyle(.bordered).tint(Color.gold)
                }
                if let a = advice, let note = a.note {
                    if a.kind == .lighter {
                        Label("\(note) Now \(NumberText.format(a.weight)) kg.", systemImage: "arrow.down.circle")
                            .font(.footnote).foregroundStyle(Color.gold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("setAdviceLighter")
                    } else if heavierAccepted != a.weight {
                        HStack(spacing: 10) {
                            Text(note).font(.footnote).foregroundStyle(Color.inkMuted)
                            Spacer()
                            Button("Use \(NumberText.format(a.weight)) kg") { heavierAccepted = a.weight }
                                .font(.footnote.weight(.semibold)).buttonStyle(.bordered).tint(Color.gold)
                                .accessibilityIdentifier("setAdviceHeavier")
                        }
                    }
                }
                if !done.isEmpty && done.allSatisfy({ $0.rpe == nil }) {
                    Text("Press and hold a ticked set to record how hard it felt (RPE).")
                        .font(.caption2).foregroundStyle(Color.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .card()
        .alert("Couldn’t log the set", isPresented: $saveError) { Button("OK", role: .cancel) {} }
        .sheet(isPresented: $showPlates) {
            NavigationStack {
                PlateCalculatorView(target: startWeight)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showPlates = false } } }
            }
        }
    }

    private var prescription: String {
        var parts = ["\(item.sets) × \(item.repsText)"]
        if let e = item.effortText { parts.append(e) }
        if item.restSeconds > 0 {
            parts.append(item.restSeconds >= 60 ? "\(NumberText.format(Double(item.restSeconds) / 60)) min rest" : "\(item.restSeconds) s rest")
        }
        return parts.joined(separator: "  ·  ")
    }

    private var suggestionIcon: String {
        switch suggestion.kind {
        case .increase: return "arrow.up.circle.fill"
        case .deload: return "arrow.down.circle"
        case .percent: return "percent"
        case .byFeel: return "hand.raised"
        default: return "equal.circle"
        }
    }

    private var suggestionLine: String? {
        guard loadable else { return nil }
        switch suggestion.kind {
        case .byFeel: return suggestion.reason
        default:
            guard let w = suggestion.weight else { return suggestion.reason }
            if declined { return "Keeping \(NumberText.format(suggestedWeight ?? w)) kg for today." }
            return "\(NumberText.format(WorkoutPlanner.scaled(w, factor: log.loadFactor))) kg. \(suggestion.reason)"
        }
    }
}

struct Chip: View {
    let text: String
    let prominent: Bool
    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold)).tracking(0.8)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .foregroundStyle(prominent ? Color.night : Color.gold)
            .background(prominent ? Color.gold : Color.gold.opacity(0.14), in: Capsule())
    }
}

struct SetRow: View {
    let index: Int
    let item: PlannedExercise
    let logged: SetLog?
    let startWeight: Double
    let loadable: Bool
    var focused: FocusState<Bool>.Binding
    let onDone: (Double, Int) -> Void
    let onUndo: (SetLog) -> Void
    let onEffort: (SetLog, Double) -> Void
    @State private var weight: Double?
    @State private var reps: Int?
    @State private var ready = false
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 10))
        layout {
            Text(textSize.isAccessibilitySize ? "Set \(index + 1)" : "\(index + 1)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(logged == nil ? Color.inkMuted : Color.gold)
                .frame(width: textSize.isAccessibilitySize ? nil : 34, alignment: .leading)
            if let logged {
                ValuePill(text: loadable ? NumberText.format(logged.weight) : "BW", done: true)
                ValuePill(text: logged.rpe.map { "\(logged.reps) @\(NumberText.format($0))" } ?? "\(logged.reps)", done: true)
                Button { onUndo(logged) } label: {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.bold)).foregroundStyle(Color.night)
                        .frame(width: 44, height: 44)
                        .background(LinearGradient.brand, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .accessibilityLabel("Set \(index + 1) done, \(NumberText.format(logged.weight)) kilograms, \(logged.reps) reps. Tap to undo. Hold to record effort.")
                .contextMenu {
                    ForEach([6.0, 7.0, 8.0, 9.0, 10.0], id: \.self) { value in
                        Button("RPE \(NumberText.format(value)): \(SetRow.effortWord(value))") { onEffort(logged, value) }
                    }
                }
            } else {
                if loadable {
                    TextField("0", value: $weight, format: .number)
                        .keyboardType(.decimalPad)
                        .focused(focused)
                        .modifier(PillField())
                        .accessibilityLabel("Weight for set \(index + 1), kilograms")
                } else {
                    ValuePill(text: "BW", done: false)
                }
                TextField("0", value: $reps, format: .number)
                    .keyboardType(.numberPad)
                    .focused(focused)
                    .modifier(PillField())
                    .accessibilityLabel("Reps for set \(index + 1)")
                Button { onDone(weight ?? 0, reps ?? 0) } label: {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.bold)).foregroundStyle(.tertiary)
                        .frame(width: 44, height: 44)
                        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .accessibilityLabel("Mark set \(index + 1) done")
                .accessibilityIdentifier("setDone-\(item.id)-\(index)")
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: logged != nil)
        .onAppear {
            if !ready { weight = startWeight; reps = item.targetReps(set: index) ?? 10; ready = true }
        }
        .onChange(of: startWeight) { _, w in if logged == nil { weight = w } }
    }
}

extension SetRow {
    /// Plain words for the effort scale (reps left in the tank: RPE 10 means none).
    static func effortWord(_ rpe: Double) -> String {
        switch rpe {
        case ..<6.5: return "easy"
        case ..<7.5: return "comfortable"
        case ..<8.5: return "challenging"
        case ..<9.5: return "very hard"
        default: return "all-out"
        }
    }
}

struct PillField: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.title3.weight(.semibold).monospacedDigit())
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(Color.ink)
            .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct ValuePill: View {
    let text: String
    let done: Bool
    var body: some View {
        Text(text)
            .font(.title3.weight(.semibold).monospacedDigit())
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(done ? Color.gold : Color.inkMuted)
            .background(done ? Color.gold.opacity(0.12) : Color.surfaceRaised,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct RestTimerBar: View {
    let endsAt: Date
    let total: Int
    let onAdd: () -> Void
    let onLess: () -> Void
    let onDone: () -> Void
    /// What comes after this rest, for example "Next: set 2 of 3".
    var nextText: String? = nil
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let left = max(0, Int(endsAt.timeIntervalSince(ctx.date).rounded(.up)))
            let clock = "\(left / 60):\(String(format: "%02d", left % 60))"
            VStack(alignment: .leading, spacing: 8) {
                if textSize.isAccessibilitySize {
                    Menu {
                        if left > 0 {
                            Button("15 seconds less", action: onLess)
                            Button("30 seconds more", action: onAdd)
                        }
                        Button(left > 0 ? "Skip rest" : "Dismiss timer", action: onDone)
                    } label: {
                        Label(left > 0 ? "Rest \(clock)" : "Rest done", systemImage: "timer").frame(minHeight: 44)
                    }
                    .accessibilityHint("Rest timer options")
                } else {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().stroke(Color.white.opacity(0.12), lineWidth: 4)
                            Circle().trim(from: 0, to: total > 0 ? min(1, CGFloat(left) / CGFloat(total)) : 0)
                                .stroke(LinearGradient.brand, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                        .frame(width: 30, height: 30).accessibilityHidden(true)
                        Text(left > 0 ? clock : "Next set").font(.title2.weight(.bold).monospacedDigit())
                        Spacer(minLength: 0)
                        if left > 0 {
                            Button("−15", action: onLess).accessibilityLabel("15 seconds less rest")
                            Button("+30", action: onAdd).accessibilityLabel("30 seconds more rest")
                        }
                        Button(left > 0 ? "Skip rest" : "OK", action: onDone)
                    }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    if let nextText {
                        Text(nextText).font(.footnote.weight(.medium)).opacity(0.8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("nextUp")
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18).padding(.vertical, 14)
            .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.gold.opacity(0.35), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
            .padding(.horizontal)
            .padding(.bottom, 6)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(left > 0 ? "Rest, \(left) seconds left" : "Rest done")
        }
    }
}

struct SwapSheet: View {
    let item: PlannedExercise
    let content: BundledContent
    let equipment: Set<String>
    let maxDifficulty: Int
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if item.exerciseId != item.originalExerciseId, let orig = content.library[item.originalExerciseId] {
                        Button("Back to \(orig.name)") { onPick(orig.id); dismiss() }
                    }
                    ForEach(Substitution.options(item.originalExerciseId, library: content.library, available: equipment,
                                                 maxDifficulty: maxDifficulty, limit: 8)) { ex in
                        Button { onPick(ex.id); dismiss() } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ex.name).foregroundStyle(.primary)
                                Text(ex.cues).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                } footer: {
                    Text("For this session only. Each exercise keeps its own weight history; a swap starts by feel at the same effort.")
                }
            }
            .navigationTitle("Swap \(item.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
