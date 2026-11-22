import SwiftUI
import SwiftData
import SteadyCore
import Charts
import WidgetKit

enum AppTab: Hashable { case today, train, food, progress, settings }

private struct ShowTabKey: EnvironmentKey {
    static let defaultValue: (AppTab) -> Void = { _ in }
}

extension EnvironmentValues {
    /// Switches the main tab bar, for example back to Today after changing program.
    var showTab: (AppTab) -> Void {
        get { self[ShowTabKey.self] }
        set { self[ShowTabKey.self] = newValue }
    }
}

struct MainTabView: View {
    @Environment(\.modelContext) private var context
    @State private var tab: AppTab = .today
    @State private var foodNavigation = FoodDraftNavigation()

    var body: some View {
        TabView(selection: $tab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(AppTab.today)
            TrainView()
                .tabItem { Label("Train", systemImage: "dumbbell") }
                .tag(AppTab.train)
            FoodView()
                .tabItem { Label("Food", systemImage: "fork.knife") }
                .tag(AppTab.food)
            ProgressTabView()
                .tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }
                .tag(AppTab.progress)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .environment(\.showTab, { tab = $0 })
        .environment(foodNavigation)
        .onChange(of: foodNavigation.request?.id) { _, request in if request != nil { tab = .food } }
        .onAppear {
            foodNavigation.load(in: context)
            if NotificationRouter.shared.openMeal != nil { tab = .food }
        }
        .onChange(of: NotificationRouter.shared.openMeal) { _, meal in if meal != nil { tab = .food } }
    }
}

struct ComingSoonView: View {
    let title: String
    let systemImage: String
    let detail: String
    var body: some View {
        NavigationStack {
            ContentUnavailableView(title, systemImage: systemImage, description: Text(detail))
                .navigationTitle(title)
        }
    }
}

// MARK: - Today

struct TodayView: View {
    @Environment(ContentStore.self) private var store
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query private var plans: [TrainingPlan]
    @Query private var food: [NutritionPlan]
    @Query private var checkIns: [CheckInSettings]
    @Query(sort: \WorkoutLog.startedAt, order: .reverse) private var logs: [WorkoutLog]
    @Query private var foodEntries: [FoodEntry]
    @Query private var appSettings: [AppSettings]
    @Query(sort: \WaterEntry.date, order: .reverse) private var water: [WaterEntry]
    @Environment(\.showTab) private var showTab
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var startSheet = false
    @State private var activeLog: WorkoutLog?
    @Environment(FoodDraftNavigation.self) private var foodNavigation
    @AppStorage("upcomingWorkoutAdjustment") private var adjustmentData = Data()
    @State private var adjustingWorkout: WorkoutAdjustmentSheet.Focus?

    /// The session in progress: an open workout, or one from the program you are on now.
    private var unfinished: WorkoutLog? {
        logs.first { $0.finishedAt == nil && ($0.isFreestyle || $0.programId == plans.first?.programId) }
    }

    /// Everything the widgets show, as one key: when it changes, the snapshot is rewritten.
    private var widgetKey: String {
        let today = foodEntries.filter { Calendar.current.isDateInToday($0.eatenAt) }
        let t = totals(today)
        let w = water.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.ml }
        let plan = plans.first
        return "\(plan?.programId ?? "")-\(plan?.nextSessionIndex ?? 0)-\(Int(t.kcal))-\(Int(t.protein))-\(w)-\(food.first?.calories ?? 0)-\(scenePhase == .active)-\(logs.count)"
    }

    /// Writes what the home and lock screen widgets show, and asks them to redraw if it changed.
    private func refreshWidgets() async {
        guard scenePhase == .active else { return }
        let today = foodEntries.filter { Calendar.current.isDateInToday($0.eatenAt) }
        let t = totals(today)
        var next: String?, week: String?, minutes: Int?
        var streak = 0
        if let plan = plans.first, let program = store.content?.program(plan.programId) {
            if let n = program.session(at: plan.nextSessionIndex, includeOptional: plan.daysPerWeek >= 3) {
                next = n.workout.name
                week = "Week \(n.week.number) of \(program.weeks.count)"
                minutes = n.workout.estimatedMinutes
            }
            streak = Consistency.weekStreak(sessionDates: logs.compactMap(\.finishedAt), planned: plan.daysPerWeek)
        }
        var sleep: Double?
        if appSettings.first?.consents[DataType.appleHealth.rawValue] != nil,
           let n = await HealthService.nightlySleep(days: 1).last,
           let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: .now)),
           n.night >= yesterday {
            sleep = n.hours
        }
        let snapshot = WidgetSnapshot(updated: .now, nextSession: next, weekLabel: week, sessionMinutes: minutes,
                                      kcalTarget: food.first?.calories ?? 0, kcalEaten: Int(t.kcal.rounded()),
                                      proteinTarget: food.first?.protein ?? 0, proteinEaten: Int(t.protein.rounded()),
                                      waterMl: water.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.ml },
                                      waterGoalMl: checkIns.first?.waterGoalMl ?? 2500, sleepHours: sleep, streakWeeks: streak)
        if snapshot.save() { WidgetCenter.shared.reloadAllTimelines() }
    }

    /// The most recent workout finished today, to add sets or exercises to it afterwards.
    private var doneToday: WorkoutLog? {
        logs.first { $0.finishedAt != nil && Calendar.current.isDateInToday($0.startedAt) }
    }

    /// True once there is something worth keeping and no backup file has been made for 30 days.
    private var backupDue: Bool {
        let finished = logs.filter { $0.finishedAt != nil }
        guard finished.count >= 3, let oldest = finished.last?.startedAt else { return false }
        let since = appSettings.first?.lastBackupAt ?? oldest
        return Date.now.timeIntervalSince(since) > 30 * 86_400
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                            .font(.caption.weight(.semibold)).tracking(1.6).foregroundStyle(Color.gold)
                        Text(greeting).font(.largeTitle.weight(.bold)).foregroundStyle(Color.ink)
                    }
                    .padding(.top, 8)

                    if let plan = plans.first, let program = store.content?.program(plan.programId) {
                        sessionCard(plan: plan, program: program)
                    }
                    foodShortcuts
                    NavigationLink {
                        WellnessView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "leaf.circle.fill").font(.title2).foregroundStyle(Color.emerald)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("WELLNESS TOOLS").font(.caption.weight(.semibold)).tracking(1.4).foregroundStyle(Color.gold)
                                Text("Fasting, supplements and research-backed guidance").font(.subheadline).foregroundStyle(Color.ink)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Color.inkMuted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("wellnessTools")
                    if let plan = plans.first {
                        WeekStrip(logs: logs, plan: plan, adjustment: adjustment(for: plan))
                        let streak = Consistency.weekStreak(sessionDates: logs.compactMap(\.finishedAt), planned: plan.daysPerWeek)
                        if streak >= 2 {
                            Label("\(streak) weeks in a row hitting your \(plan.daysPerWeek) sessions", systemImage: "flame.fill")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Color.gold)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("streak")
                        }
                    }
                    if let c = checkIns.first {
                        SleepCard(goalHours: c.sleepGoalHours,
                                  healthOn: appSettings.first?.consents[DataType.appleHealth.rawValue] != nil)
                    }
                    if let d = doneToday {
                        Button { activeLog = d } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(Color.emerald)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("DONE TODAY").font(.caption.weight(.semibold)).tracking(1.6).foregroundStyle(Color.gold)
                                    Text(d.workoutName).font(.headline).foregroundStyle(Color.ink).lineLimit(1)
                                    Text("Tap to add sets or exercises").font(.footnote).foregroundStyle(Color.inkMuted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.inkMuted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card()
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("doneToday")
                    }
                    if let n = food.first {
                        let range = Calendar.current.dayRange(.now)
                        FoodCard(plan: n, totals: totals(foodEntries.filter { $0.eatenAt >= range.0 && $0.eatenAt < range.1 }))
                    }
                    if let c = checkIns.first {
                        HabitsCard(settings: c, proteinTarget: food.first?.protein ?? 0,
                                   protein: totals(foodEntries.filter { Calendar.current.isDateInToday($0.eatenAt) }).protein,
                                   healthOn: appSettings.first?.consents[DataType.appleHealth.rawValue] != nil)
                    }
                    if let c = checkIns.first { CheckInCard(settings: c) }
                    if backupDue {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("BACK UP YOUR DATA").font(.caption.weight(.semibold)).tracking(1.6).foregroundStyle(Color.gold)
                            Text("Everything lives only on this phone. It has been a month or more since your last backup file.")
                                .font(.subheadline).foregroundStyle(Color.inkMuted)
                            Button("Go to Export my data") { showTab(.settings) }
                                .buttonStyle(.bordered).tint(Color.gold)
                                .accessibilityIdentifier("backupNudge")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color.night.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .task {
                if let p = profiles.first, let n = food.first, GoalSwitch.finishEaseInIfDue(profile: p, nutrition: n) {
                    try? context.save()
                }
                if let plan = plans.first {
                    ProgramSwitch.closeStaleSessions(in: context, currentProgramId: plan.programId)
                }
            }
            .sheet(isPresented: $startSheet) {
                if let plan = plans.first, let program = store.content?.program(plan.programId),
                   let next = program.session(at: plan.nextSessionIndex, includeOptional: plan.daysPerWeek >= 3) {
                    let changes = adjustment(for: plan)
                    StartWorkoutSheet(program: program, week: next.week, workout: next.workout,
                                      initialVersion: changes.version) { version, choice, code in
                        start(plan: plan, program: program, week: next.week, workout: next.workout, version: version,
                              choice: choice, code: code, swaps: changes.swaps)
                    }
                }
            }
            .sheet(item: $adjustingWorkout) { focus in
                if let plan = plans.first, let program = store.content?.program(plan.programId),
                   let next = program.session(at: plan.nextSessionIndex, includeOptional: plan.daysPerWeek >= 3) {
                    WorkoutAdjustmentSheet(program: program, workout: next.workout, week: next.week,
                                           equipment: Set(plan.equipment), preferredDay: preferredDay(plan),
                                           focus: focus, adjustment: adjustment(for: plan)) { updated in
                        if let data = try? JSONEncoder().encode(updated) { adjustmentData = data }
                    }
                }
            }
            .navigationDestination(item: $activeLog) { log in WorkoutLogEditor(log: log) }
            .task(id: widgetKey) { await refreshWidgets() }
        }
    }

    private var foodShortcuts: some View {
        let today = FoodDraftNavigation.Meal(slot: MealSlot.suggested(for: .now))
        let log = Button {
            foodNavigation.request = .init(meal: today)
            showTab(.food)
        } label: {
            Label("Log food", systemImage: "fork.knife").frame(maxWidth: .infinity, minHeight: 44)
        }.accessibilityIdentifier("todayLogFood")
        let scan = Button {
            foodNavigation.request = .init(meal: today, scan: true)
            showTab(.food)
        } label: {
            Label("Scan barcode", systemImage: "barcode.viewfinder").frame(maxWidth: .infinity, minHeight: 44)
        }.accessibilityIdentifier("todayScanBarcode")

        return VStack(spacing: 8) {
            if let pending = foodNavigation.latest {
                Button {
                    foodNavigation.request = .init(meal: pending)
                    showTab(.food)
                } label: {
                    Label("Continue meal", systemImage: "arrow.uturn.forward")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityIdentifier("todayContinueMeal")
                .accessibilityHint("\(pending.slot.label), \(pending.day.formatted(date: .abbreviated, time: .omitted))")
            }
            ViewThatFits(in: .horizontal) {
                HStack { log; scan }
                VStack { log; scan }
            }
        }
        .buttonStyle(.bordered)
    }

    private func adjustment(for plan: TrainingPlan) -> SessionAdjustment {
        if let stored = try? JSONDecoder().decode(SessionAdjustment.self, from: adjustmentData),
           stored.applies(programID: plan.programId, planStart: plan.startDate, sessionIndex: plan.nextSessionIndex) {
            return stored
        }
        return SessionAdjustment(programID: plan.programId, planStart: plan.startDate, sessionIndex: plan.nextSessionIndex)
    }

    private func preferredDay(_ plan: TrainingPlan) -> Date {
        let now: Date = .now
        let first = doneToday == nil ? now : Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        return SessionAdjustment.preferredDay(onOrAfter: first, weekdays: plan.preferredWeekdays)
    }

    @ViewBuilder
    private func sessionCard(plan: TrainingPlan, program: Program) -> some View {
        if let next = program.session(at: plan.nextSessionIndex, includeOptional: plan.daysPerWeek >= 3) {
            let changes = adjustment(for: plan)
            let startsEarly = changes.movedTo.map { $0 > Calendar.current.startOfDay(for: .now) } ?? false
            let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 12))
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(unfinished == nil ? "NEXT SESSION" : "IN PROGRESS")
                        .font(.caption.weight(.semibold)).tracking(1.6).foregroundStyle(Color.gold)
                    Spacer()
                    Text("WEEK \(next.week.number) OF \(program.weeks.count)")
                        .font(.caption2.weight(.semibold)).tracking(1.2).foregroundStyle(Color.inkMuted)
                }
                NavigationLink {
                    WorkoutPreview(program: program, week: next.week, workout: next.workout)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(next.workout.name).font(.system(.title, design: .default).weight(.bold))
                                .foregroundStyle(Color.ink)
                            Image(systemName: "chevron.right").font(.headline).foregroundStyle(Color.inkMuted)
                        }
                        layout {
                            Label("\(next.workout.estimatedMinutes) min", systemImage: "clock")
                            Label("\(next.workout.slots.count) exercises", systemImage: "dumbbell")
                            if let phase = next.week.phase { Label(phase, systemImage: "flag") }
                        }
                        .font(.subheadline).foregroundStyle(Color.inkMuted)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("nextSession")
                if unfinished == nil {
                    if let date = changes.movedTo {
                        Label(date.formatted(date: .complete, time: .omitted), systemImage: "calendar")
                            .font(.subheadline).accessibilityIdentifier("scheduledWorkoutDay")
                    }
                    if changes.version != .standard { Text(changes.version.label).font(.subheadline) }
                    Menu {
                        ForEach([WorkoutAdjustmentSheet.Focus.shorter, .swap, .move]) { focus in
                            Button(focus.title) { adjustingWorkout = focus }
                        }
                    } label: {
                        Label("Adjust workout", systemImage: "slider.horizontal.3").frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("adjustWorkout")
                }
                Button {
                    if let open = unfinished { activeLog = open } else { startSheet = true }
                } label: {
                    Text(unfinished.map { "Resume \($0.workoutName)" } ?? (startsEarly ? "Start workout early" : "Start workout"))
                        .font(.headline).foregroundStyle(Color.night)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(LinearGradient.brand, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(unfinished == nil ? "startWorkoutButton" : "resumeWorkout")
            }
            .padding(18)
            .background(LinearGradient.night, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(LinearGradient.brand.opacity(0.6), lineWidth: 1))
        } else if let unfinished {
            Button { activeLog = unfinished } label: {
                Label("Resume \(unfinished.workoutName)", systemImage: "play.fill")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("resumeWorkout")
        } else {
            Text("Program complete. Choose your next one in Settings.").card()
        }
    }

    private func start(plan: TrainingPlan, program: Program, week: ProgramWeek, workout: ProgramWorkout, version: SessionVersion,
                       choice: Readiness.Choice = .asPlanned, code: ReasonCode? = nil, swaps: [Int: String] = [:]) {
        guard let content = store.content, choice != .rest else { return }
        let built = WorkoutPlanner.plan(program: program, workout: workout, version: version, content: content,
                                        equipment: Set(plan.equipment), chosenSwaps: swaps, week: week.number)
        let log = WorkoutLog(programId: program.id, weekNumber: week.number, workoutPosition: workout.position,
                             workoutName: workout.name, version: version, swaps: built.swaps)
        log.loadFactor = choice.loadFactor
        log.readinessChoiceRaw = choice.rawValue
        log.readinessCode = code?.rawValue ?? ""
        context.insert(log)
        try? context.save()
        activeLog = log
    }

    private var greeting: String {
        let name = profiles.first?.name ?? ""
        let hour = Calendar.current.component(.hour, from: .now)
        let part = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
        return name.isEmpty ? part : "\(part), \(name)"
    }
}

/// This week, Monday to Sunday: trained days filled, planned days ringed, fixed activities dotted.
struct WeekStrip: View {
    let logs: [WorkoutLog]
    let plan: TrainingPlan
    var adjustment: SessionAdjustment? = nil
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        let cal: Calendar = {
            var calendar = Calendar(identifier: .iso8601)
            calendar.timeZone = Calendar.current.timeZone
            return calendar
        }()
        let start = cal.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
        let trained = Set(logs.filter { $0.finishedAt != nil }.map { cal.startOfDay(for: $0.startedAt) })
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 0))
        layout {
            ForEach(days, id: \.self) { day in
                let weekday = Calendar.current.component(.weekday, from: day)
                let isToday = cal.isDateInToday(day)
                let done = trained.contains(cal.startOfDay(for: day))
                let planned = adjustment?.isTrainingDay(day, weekdays: plan.preferredWeekdays, calendar: cal)
                    ?? plan.preferredWeekdays.contains(weekday)
                let fixed = plan.fixedCommitments.contains { $0.weekday == weekday }
                VStack(spacing: 6) {
                    Text(day.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isToday ? Color.gold : Color.inkMuted)
                    ZStack {
                        if done {
                            Circle().fill(LinearGradient.brand)
                            Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Color.night)
                        } else {
                            Circle().stroke(planned ? Color.gold.opacity(0.7) : Color.hairline,
                                            style: StrokeStyle(lineWidth: 1.5, dash: planned ? [] : [3, 3]))
                            Text(day.formatted(.dateTime.day())).font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(isToday ? Color.ink : Color.inkMuted)
                        }
                    }
                    .frame(width: 34, height: 34)
                    Circle().fill(fixed ? Color.emerald : Color.clear).frame(width: 5, height: 5)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(day.formatted(.dateTime.weekday(.wide))): \(done ? "trained" : planned ? "training day" : "rest")\(fixed ? ", fixed activity" : "")")
            }
        }
        .card()
    }
}

struct FoodCard: View {
    let plan: NutritionPlan
    var totals: Macros = Macros()
    /// The day shown; a hard training day raises its targets.
    var day: Date = .now
    @Query private var settings: [AppSettings]
    @Environment(\.modelContext) private var context
    private var eaten: Int { Int(totals.kcal.rounded()) }
    @Environment(\.scenePhase) private var scenePhase
    @State private var health: (kcal: Int, count: Int) = (0, 0)
    private var manual: Int { settings.first?.hardDayExtraKcal ?? 0 }
    private var percent: Int { settings.first?.healthAddBackPercent ?? 0 }
    private var isHard: Bool { settings.first?.hardDays.contains(HardDay.key(day)) ?? false }
    private var healthExtra: Int { HardDay.healthExtra(burnedKcal: health.kcal, percent: percent) }
    private var extra: Int { HardDay.extra(manualKcal: manual, isHardDay: isHard, healthKcal: healthExtra) }
    private var target: (calories: Int, carbs: Int) {
        HardDay.targets(calories: plan.calories, carbs: plan.carbs, extraKcal: extra, isHardDay: extra > 0)
    }

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().stroke(Color.hairline, lineWidth: 10)
                Circle().trim(from: 0, to: min(1, CGFloat(eaten) / CGFloat(max(target.calories, 1))))
                    .stroke(LinearGradient.brand, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(abs(target.calories - eaten))").font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(Color.ink)
                    Text(eaten > target.calories ? "kcal over" : "kcal left").font(.caption2).foregroundStyle(Color.inkMuted)
                }
            }
            .frame(width: 104, height: 104)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("caloriesLeft")
            VStack(alignment: .leading, spacing: 10) {
                Text("FOOD TODAY").font(.caption.weight(.semibold)).tracking(1.6).foregroundStyle(Color.gold)
                MacroBar(label: "Protein", value: Int(totals.protein.rounded()), target: plan.protein)
                MacroBar(label: "Carbs", value: Int(totals.carbs.rounded()), target: target.carbs)
                MacroBar(label: "Fat", value: Int(totals.fat.rounded()), target: plan.fat)
                if healthExtra > 0 {
                    Label("Apple Health workouts: \(health.kcal) kcal, +\(healthExtra) added (\(percent)%)", systemImage: "heart.fill")
                        .font(.caption2).foregroundStyle(Color.inkMuted)
                }
                if manual > 0, let s = settings.first {
                    Button {
                        s.hardDays = HardDay.toggled(s.hardDays, key: HardDay.key(day))
                        try? context.save()
                    } label: {
                        Label(isHard ? "Hard training day: +\(manual) kcal" : "Hard training day?",
                              systemImage: isHard ? "flame.fill" : "flame")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered).tint(isHard ? Color.gold : Color.inkMuted)
                    .accessibilityIdentifier("hardDayToggle")
                }
                if plan.startAtMaintenance {
                    Text(plan.easeInUntil.map { "Maintenance until \($0.formatted(.dateTime.day().month(.abbreviated))), then your goal targets" }
                         ?? "Maintenance for your first two weeks")
                        .font(.caption2).foregroundStyle(Color.inkMuted)
                }
            }
        }
        .card()
        .accessibilityElement(children: .contain)
        .task(id: "\(HardDay.key(day))-\(percent)-\(scenePhase == .active)") {
            guard percent > 0, HealthService.isAvailable else { health = (0, 0); return }
            health = await HealthService.workoutCalories(on: day)
        }
    }
}

struct MacroBar: View {
    let label: String
    let value: Int
    let target: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.caption.weight(.medium)).foregroundStyle(Color.ink)
                Spacer()
                Text("\(value) / \(target) g").font(.caption.monospacedDigit()).foregroundStyle(Color.inkMuted)
            }
            BrandProgress(value: Double(value) / Double(max(target, 1)))
        }
    }
}

/// Today's steps and last night's sleep from Apple Health, against the goals set at check-in. Read-only.
/// Last night's sleep and the past week, from Apple Health. Read-only, on this phone.
struct SleepCard: View {
    let goalHours: Double
    let healthOn: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.showTab) private var showTab
    @State private var nights: [SleepNight] = []
    @State private var loaded = false

    /// Last night: the most recent night that started yesterday or today.
    private var lastNight: SleepNight? {
        guard let n = nights.last, let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: .now)),
              n.night >= yesterday, n.hours >= 1 else { return nil }
        return n
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("SLEEP", systemImage: "moon.stars.fill").font(.caption.weight(.semibold)).tracking(1.6).foregroundStyle(Color.gold)
                Spacer()
                if let avg = SleepMath.average(nights) {
                    Text("7-night avg \(SleepMath.text(avg))").font(.caption.monospacedDigit()).foregroundStyle(Color.inkMuted)
                }
            }
            if !healthOn {
                Text("See last night's sleep and your week here. It comes from Apple Health, recorded by your Apple Watch or your iPhone's sleep schedule.")
                    .font(.subheadline).foregroundStyle(Color.inkMuted)
                Button("Turn on Apple Health") { showTab(.settings) }
                    .buttonStyle(.bordered).tint(Color.gold)
                    .accessibilityIdentifier("sleepTurnOnHealth")
            } else if !loaded {
                ProgressView().frame(maxWidth: .infinity)
            } else if nights.isEmpty {
                Text("No sleep found in Apple Health this week. An Apple Watch worn to bed, or the Sleep schedule in the Health app, records it.")
                    .font(.subheadline).foregroundStyle(Color.inkMuted)
            } else {
                if let n = lastNight {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(SleepMath.text(n.hours)).font(.system(.title, design: .rounded).weight(.bold).monospacedDigit())
                            .foregroundStyle(Color.ink)
                        Text("last night").font(.subheadline).foregroundStyle(Color.inkMuted)
                    }
                    if let bed = n.bedtime, let wake = n.wake {
                        Text("Asleep \(bed.formatted(date: .omitted, time: .shortened)) to \(wake.formatted(date: .omitted, time: .shortened))")
                            .font(.footnote).foregroundStyle(Color.inkMuted)
                    }
                    BrandProgress(value: n.hours / max(goalHours, 0.1))
                    Text(n.hours >= goalHours ? "Goal of \(NumberText.format(goalHours)) h reached."
                                              : "\(SleepMath.text(goalHours - n.hours)) under your \(NumberText.format(goalHours)) h goal.")
                        .font(.caption).foregroundStyle(Color.inkMuted)
                } else {
                    Text("Nothing recorded last night yet.").font(.subheadline).foregroundStyle(Color.inkMuted)
                }
                Chart {
                    ForEach(nights) { n in
                        BarMark(x: .value("Night", n.night, unit: .day), y: .value("Hours", n.hours))
                            .foregroundStyle(n.hours >= goalHours ? Color.emerald : Color.gold)
                            .cornerRadius(4)
                    }
                    RuleMark(y: .value("Goal", goalHours))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Color.inkMuted)
                }
                .chartYAxis { AxisMarks(position: .leading, values: [0, 4, 8]) }
                .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
                .frame(height: 90)
                .accessibilityLabel("Hours asleep each night for the last 7 nights")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityIdentifier("sleepCard")
        .task(id: "\(scenePhase)-\(healthOn)") {
            guard healthOn, scenePhase == .active else { return }
            nights = await HealthService.nightlySleep(days: 7)
            loaded = true
        }
    }
}

/// Four daily habits in one place: water (tap to log), protein, steps and sleep, each ticked when its goal is met.
struct HabitsCard: View {
    let settings: CheckInSettings
    let proteinTarget: Int
    let protein: Double
    let healthOn: Bool
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \WaterEntry.date, order: .reverse) private var water: [WaterEntry]
    @State private var steps: Int?
    @State private var sleepHours: Double?

    private var waterToday: Int { water.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.ml } }

    var body: some View {
        let goalsMet = [waterToday >= settings.waterGoalMl,
                        proteinTarget > 0 && protein >= Double(proteinTarget) * 0.9,
                        (steps ?? 0) >= settings.stepsGoal,
                        (sleepHours ?? 0) >= settings.sleepGoalHours].filter { $0 }.count
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("DAILY HABITS").font(.caption.weight(.semibold)).tracking(1.6).foregroundStyle(Color.gold)
                Spacer()
                Text("\(goalsMet) of 4 done").font(.caption.monospacedDigit()).foregroundStyle(Color.inkMuted)
            }
            VStack(alignment: .leading, spacing: 6) {
                habitRow("Water", systemImage: "drop.fill", value: "\(NumberText.format(Double(waterToday) / 1000)) / \(NumberText.format(Double(settings.waterGoalMl) / 1000)) L",
                         share: Double(waterToday) / Double(max(settings.waterGoalMl, 1)))
                HStack(spacing: 8) {
                    ForEach([250, 500], id: \.self) { ml in
                        Button("+\(ml) ml") { context.insert(WaterEntry(ml: ml)); try? context.save() }
                            .font(.caption.weight(.semibold)).buttonStyle(.bordered).tint(Color.emerald)
                            .accessibilityIdentifier("water-\(ml)")
                    }
                    if let last = water.first, Calendar.current.isDateInToday(last.date) {
                        Button("Undo") { context.delete(last); try? context.save() }
                            .font(.caption).buttonStyle(.borderless).foregroundStyle(Color.inkMuted)
                    }
                }
            }
            habitRow("Protein", systemImage: "fork.knife", value: "\(Int(protein.rounded())) / \(proteinTarget) g",
                     share: proteinTarget > 0 ? protein / Double(proteinTarget) : 0)
            if healthOn {
                habitRow("Steps", systemImage: "figure.walk", value: "\((steps ?? 0).formatted()) / \(settings.stepsGoal.formatted())",
                         share: Double(steps ?? 0) / Double(max(settings.stepsGoal, 1)))
                habitRow("Sleep", systemImage: "moon.fill",
                         value: "\(sleepHours.map { String(format: "%.1f", $0) } ?? "-") / \(NumberText.format(settings.sleepGoalHours)) h",
                         share: (sleepHours ?? 0) / max(settings.sleepGoalHours, 0.1))
            } else {
                Text("Turn on Apple Health in Settings to tick off steps and sleep automatically.")
                    .font(.caption).foregroundStyle(Color.inkMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityIdentifier("habitsCard")
        .task(id: "\(scenePhase)-\(healthOn)") {
            guard healthOn, scenePhase == .active else { return }
            steps = await HealthService.stepsToday()
            let nights = await HealthService.nightlySleep(days: 1)
            if let n = nights.last, let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: .now)),
               n.night >= yesterday { sleepHours = n.hours }
        }
    }

    private func habitRow(_ label: String, systemImage: String, value: String, share: Double) -> some View {
        let done = share >= (label == "Protein" ? 0.9 : 1)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: done ? "checkmark.circle.fill" : systemImage)
                    .foregroundStyle(done ? Color.emerald : Color.inkMuted).frame(width: 20)
                Text(label).font(.subheadline.weight(.medium)).foregroundStyle(Color.ink)
                Spacer()
                Text(value).font(.subheadline.monospacedDigit()).foregroundStyle(Color.inkMuted)
            }
            BrandProgress(value: min(max(share, 0), 1))
        }
        .accessibilityElement(children: .combine)
    }
}

struct TodayActivityCard: View {
    let settings: CheckInSettings
    @Environment(\.scenePhase) private var scenePhase
    @State private var steps: Int?
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("STEPS TODAY").font(.caption.weight(.semibold)).tracking(1.6).foregroundStyle(Color.gold)
            if loaded && steps == nil {
                Text("Nothing from Apple Health yet today.").font(.subheadline).foregroundStyle(Color.inkMuted)
            } else {
                row("Steps", value: steps.map { $0.formatted() } ?? "-", goal: settings.stepsGoal.formatted(),
                    share: Double(steps ?? 0) / Double(max(settings.stepsGoal, 1)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            steps = await HealthService.stepsToday()
            loaded = true
        }
    }

    private func row(_ label: String, value: String, goal: String, share: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.subheadline.weight(.medium)).foregroundStyle(Color.ink)
                Spacer()
                Text("\(value) / \(goal)").font(.subheadline.monospacedDigit()).foregroundStyle(Color.inkMuted)
            }
            BrandProgress(value: min(max(share, 0), 1))
        }
        .accessibilityElement(children: .combine)
    }
}

struct CheckInCard: View {
    let settings: CheckInSettings
    var body: some View {
        let days = daysUntil(settings.weekday)
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("WEEKLY CHECK-IN").font(.caption.weight(.semibold)).tracking(1.6).foregroundStyle(Color.gold)
                Text(days == 0 ? "Today" : days == 1 ? "Tomorrow" : "\(weekdayNames[settings.weekday - 1]), in \(days) days")
                    .font(.title3.weight(.semibold)).foregroundStyle(Color.ink)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Label(String(format: "%g h sleep", settings.sleepGoalHours), systemImage: "moon.stars")
                Label("\(settings.stepsGoal.formatted()) steps", systemImage: "figure.walk")
            }
            .font(.caption).foregroundStyle(Color.inkMuted)
        }
        .card()
    }

    private func daysUntil(_ weekday: Int) -> Int {
        let today = Calendar.current.component(.weekday, from: .now)
        return (weekday - today + 7) % 7
    }
}


// MARK: - Train

struct TrainView: View {
    @Environment(ContentStore.self) private var store
    @Query private var plans: [TrainingPlan]
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<WorkoutLog> { $0.finishedAt == nil }) private var openLogs: [WorkoutLog]
    @State private var changingProgram = false
    @State private var openLog: WorkoutLog?
    @State private var loggingCardio = false

    var body: some View {
        NavigationStack {
            if let plan = plans.first, let program = store.content?.program(plan.programId) {
                List {
                    Section {
                        Button {
                            if let existing = openLogs.first(where: { $0.isFreestyle }) { openLog = existing }
                            else { openLog = FreeWorkout.start(in: context) }
                        } label: {
                            Label(openLogs.contains(where: { $0.isFreestyle }) ? "Resume open workout" : "Start an open workout", systemImage: "plus.circle")
                        }
                        .accessibilityIdentifier("openWorkout")
                        Button { loggingCardio = true } label: { Label("Log cardio", systemImage: "heart.circle") }
                            .accessibilityIdentifier("logCardio")
                    } footer: {
                        Text("Train off-plan: pick any exercises, including your own. It doesn't move your program on.")
                    }
                    MobilitySection()
                    Section {
                        LabeledContent("Program", value: program.name)
                        LabeledContent("Sessions a week", value: program.sessionsPerWeekText)
                        LabeledContent("Typical session", value: "about \(program.averageSessionMinutes) min")
                    } footer: {
                        Text("Preview any session here. Start your next one from Today.")
                    }
                    ForEach(program.weeks) { week in
                        Section {
                            ForEach(week.workouts) { workout in
                                NavigationLink {
                                    WorkoutPreview(program: program, week: week, workout: workout)
                                } label: {
                                    LabeledContent(workout.name, value: "\(workout.estimatedMinutes) min")
                                }
                            }
                        } header: {
                            Text(weekHeader(week))
                        }
                    }
                }
                .themedList()
                .navigationTitle("Train")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Change program") { changingProgram = true }.accessibilityIdentifier("trainChangeProgram")
                    }
                }
                .sheet(isPresented: $changingProgram) { ChangeProgramView() }
                .navigationDestination(item: $openLog) { FreeWorkoutView(log: $0) }
                .sheet(isPresented: $loggingCardio) { CardioLogSheet() }
            } else {
                ContentUnavailableView("No program yet", systemImage: "dumbbell")
                    .navigationTitle("Train")
            }
        }
    }

    private func weekHeader(_ w: ProgramWeek) -> String {
        var s = "Week \(w.number)"
        if let phase = w.phase { s += " · \(phase)" } else if w.isDeload == true { s += " · Easier week" }
        return s
    }
}

struct WorkoutPreview: View {
    let program: Program
    let week: ProgramWeek
    let workout: ProgramWorkout
    @State private var selected: ExerciseSlot?

    var body: some View {
        List {
            Section {
                Text("About \(workout.estimatedMinutes) min including a 7 minute warm-up and 5 minute cool-down.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(workout.slots) { slot in
                Button { selected = slot } label: { SlotRow(slot: slot) }
                    .accessibilityHint("Shows form cues and swaps")
            }
        }
        .themedList()
        .navigationTitle(workout.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { slot in
            ExerciseSheet(exerciseId: slot.exerciseId, slot: slot, maxDifficulty: program.maxSwapDifficulty ?? 3)
        }
    }
}

struct SlotRow: View {
    let slot: ExerciseSlot
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let ss = slot.superset {
                Text(ss.label ?? ss.group)
                    .font(.caption.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.tint.opacity(0.15), in: Capsule())
                    .accessibilityLabel("Superset \(ss.label ?? ss.group)")
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(slot.exercise.capitalized).foregroundStyle(.primary)
                    if slot.isMainLift == true {
                        Text("Main").font(.caption2.bold()).foregroundStyle(.secondary)
                    }
                }
                Text(prescription).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "play.circle").font(.title3).foregroundStyle(Color.emerald)
                .accessibilityLabel("How to do it")
        }
        .accessibilityElement(children: .combine)
    }

    private var prescription: String {
        var parts: [String] = []
        let sets = slot.sets.count ?? 0
        parts.append("\(sets) × \(slot.reps.display)")
        if let e = slot.effort { parts.append(e.display) }
        if let p = slot.pct1RM, let lo = p.min, let hi = p.max {
            parts.append(lo == hi ? "\(Int(lo * 100))% 1RM" : "\(Int(lo * 100))-\(Int(hi * 100))% 1RM")
        }
        if let r = slot.rest, !(r.display.isEmpty) { parts.append("rest \(r.display.lowercased())") }
        return parts.joined(separator: " · ")
    }
}
