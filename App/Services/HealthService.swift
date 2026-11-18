import Foundation
import HealthKit
import SteadyCore

/// Apple Health: reads daily steps, workouts, sleep and body weight. Writes only one thing, and only if switched on in
/// Settings: each finished workout as a strength-training session (start and end time). Nothing leaves the phone.
/// iOS never tells an app whether read access was granted, so a missing value just means "nothing found".
enum HealthService {
    private static let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private static var stepType: HKQuantityType? { HKQuantityType.quantityType(forIdentifier: .stepCount) }
    private static var weightType: HKQuantityType? { HKQuantityType.quantityType(forIdentifier: .bodyMass) }

    /// Shows the iPhone's Health permission sheet. Returns false only when Health isn't available or the request errored.
    static func requestAccess() async -> Bool {
        guard isAvailable, let steps = stepType, let weight = weightType else { return false }
        var types: Set<HKObjectType> = [steps, weight, HKObjectType.workoutType()]
        if let energy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(energy) }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        do {
            try await store.requestAuthorization(toShare: [], read: types)
            return true
        } catch {
            return false
        }
    }

    /// Asks to save workouts. Returns true if saving is allowed afterwards.
    static func requestWorkoutWriteAccess() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [])
        } catch {
            return false
        }
        return store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }

    /// Saves one strength-training workout. Returns true when Health accepted it.
    static func saveStrengthWorkout(start: Date, end: Date) async -> Bool {
        await saveWorkout(.traditionalStrengthTraining, start: start, end: end)
    }

    /// Saves one workout of any kind (start and end time only). Returns true when Health accepted it.
    static func saveWorkout(_ activity: HKWorkoutActivityType, start: Date, end: Date) async -> Bool {
        guard isAvailable, store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized,
              end > start else { return false }
        let config = HKWorkoutConfiguration()
        config.activityType = activity
        config.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        do {
            try await builder.beginCollection(at: start)
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
            return true
        } catch {
            return false
        }
    }

    /// Average steps a day over the last full `days` days, counting only days that have data.
    static func averageDailySteps(days: Int = 7) async -> Int? {
        guard isAvailable, let type = stepType else { return nil }
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: .now)
        guard let start = calendar.date(byAdding: .day, value: -days, to: end) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: predicate,
                                                    options: .cumulativeSum, anchorDate: start,
                                                    intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, results, _ in
                var totals: [Double] = []
                results?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    if let sum = statistics.sumQuantity()?.doubleValue(for: HKUnit.count()), sum > 0 { totals.append(sum) }
                }
                if totals.isEmpty {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: Int((totals.reduce(0, +) / Double(totals.count)).rounded()))
                }
            }
            store.execute(query)
        }
    }

    /// The most recent body weight in Health, in kilograms.
    static func latestWeightKg() async -> Double? {
        guard isAvailable, let type = weightType else { return nil }
        let newestFirst = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [newestFirst]) { _, samples, _ in
                let kg = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo))
                continuation.resume(returning: kg)
            }
            store.execute(query)
        }
    }

    // MARK: Week at a glance

    struct DailySteps: Identifiable, Sendable {
        let date: Date
        let steps: Int
        var id: Date { date }
    }

    struct Workout: Identifiable, Sendable {
        let id: UUID
        let name: String
        let start: Date
        let minutes: Int
        let kcal: Int?
    }

    /// Steps so far today. Nil if Health has nothing for today or access wasn't given.
    static func stepsToday() async -> Int? {
        guard isAvailable, let type = stepType else { return nil }
        let start = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                let sum = result?.sumQuantity()?.doubleValue(for: HKUnit.count())
                continuation.resume(returning: sum.map { Int($0.rounded()) })
            }
            store.execute(query)
        }
    }

    /// Steps for each of the last `days` full days, oldest first. Days with no data show as 0.
    static func dailySteps(days: Int = 7) async -> [DailySteps] {
        guard isAvailable, let type = stepType else { return [] }
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: .now)
        guard let start = calendar.date(byAdding: .day, value: -days, to: end) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: predicate,
                                                    options: .cumulativeSum, anchorDate: start,
                                                    intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, results, _ in
                var out: [DailySteps] = []
                results?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    let sum = statistics.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0
                    out.append(DailySteps(date: statistics.startDate, steps: Int(sum.rounded())))
                }
                continuation.resume(returning: out)
            }
            store.execute(query)
        }
    }

    /// Workouts and activities recorded in Health (runs, walks, yoga, strength sessions, other apps and watches), newest first.
    static func recentWorkouts(days: Int = 7) async -> [Workout] {
        guard isAvailable else { return [] }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
        let newestFirst = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: 60,
                                      sortDescriptors: [newestFirst]) { _, samples, _ in
                // Leave out the sessions this app saved, so they aren't counted twice next to your own logs.
                let ours = Bundle.main.bundleIdentifier
                let workouts = (samples as? [HKWorkout] ?? []).filter { $0.sourceRevision.source.bundleIdentifier != ours }.map { w in
                    Workout(id: w.uuid, name: activityName(w.workoutActivityType), start: w.startDate,
                            minutes: max(1, Int((w.duration / 60).rounded())), kcal: activeEnergy(w))
                }
                continuation.resume(returning: workouts)
            }
            store.execute(query)
        }
    }

    /// Active calories from workouts recorded in Health on one day (not this app's own sessions).
    static func workoutCalories(on day: Date) async -> (kcal: Int, count: Int) {
        let (start, end) = Calendar.current.dayRange(day)
        let days = max(1, (Calendar.current.dateComponents([.day], from: start, to: .now).day ?? 0) + 1)
        let list = await recentWorkouts(days: days).filter { $0.start >= start && $0.start < end }
        let withEnergy = list.compactMap(\.kcal)
        return (withEnergy.reduce(0, +), withEnergy.count)
    }

    private static func activeEnergy(_ workout: HKWorkout) -> Int? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
              let sum = workout.statistics(for: type)?.sumQuantity() else { return nil }
        return Int(sum.doubleValue(for: HKUnit.kilocalorie()).rounded())
    }

    static func activityName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "Run"
        case .walking: return "Walk"
        case .hiking: return "Hike"
        case .cycling: return "Ride"
        case .swimming: return "Swim"
        case .yoga: return "Yoga"
        case .pilates: return "Pilates"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "Strength"
        case .highIntensityIntervalTraining: return "HIIT"
        case .elliptical: return "Elliptical"
        case .rowing: return "Rowing"
        case .stairClimbing: return "Stairs"
        case .dance, .socialDance, .cardioDance: return "Dance"
        case .coreTraining: return "Core"
        case .flexibility: return "Stretching"
        case .mindAndBody: return "Mind and body"
        case .crossTraining: return "Cross training"
        case .tennis: return "Tennis"
        case .golf: return "Golf"
        case .cricket: return "Cricket"
        default: return "Workout"
        }
    }

    /// Hours asleep for each of the last `days` nights (oldest first), counting only the asleep stages.
    /// Time in bed and time awake are not counted, and duplicate recordings are merged.
    static func nightlySleep(days: Int = 7) async -> [SleepNight] {
        guard isAvailable, let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let start = Calendar.current.date(byAdding: .day, value: -(days + 1), to: .now) ?? .now
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
        let asleep: Set<Int> = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                                HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                                HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                                HKCategoryValueSleepAnalysis.asleepREM.rawValue]
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                                      sortDescriptors: nil) { _, samples, _ in
                let intervals = (samples as? [HKCategorySample] ?? [])
                    .filter { asleep.contains($0.value) }
                    .map { DateInterval(start: $0.startDate, end: max($0.endDate, $0.startDate)) }
                continuation.resume(returning: Array(SleepMath.nights(intervals).suffix(days)))
            }
            store.execute(query)
        }
    }
}


import SwiftData

extension CardioKind {
    var healthActivity: HKWorkoutActivityType {
        switch self {
        case .run: return .running
        case .walk: return .walking
        case .bike: return .cycling
        case .rower: return .rowing
        case .elliptical: return .elliptical
        case .stairs: return .stairClimbing
        case .swim: return .swimming
        case .intervals: return .highIntensityIntervalTraining
        case .other: return .mixedCardio
        }
    }
}

enum HealthSync {
    /// Saves a logged cardio session to Apple Health once, if the person has switched that on.
    @MainActor
    static func saveIfWanted(_ s: CardioSession, settings: AppSettings?, context: ModelContext) {
        guard settings?.saveWorkoutsToHealth == true, !s.savedToHealth, s.minutes > 0 else { return }
        let end = s.date, start = s.date.addingTimeInterval(-Double(s.minutes) * 60), kind = s.kind
        Task {
            if await HealthService.saveWorkout(kind.healthActivity, start: start, end: end) {
                s.savedToHealth = true
                try? context.save()
            }
        }
    }

    /// Saves a finished workout to Apple Health once, if the person has switched that on.
    @MainActor
    static func saveIfWanted(_ log: WorkoutLog, settings: AppSettings?, context: ModelContext) {
        guard settings?.saveWorkoutsToHealth == true, !log.savedToHealth, let end = log.finishedAt else { return }
        let start = log.startedAt
        Task {
            if await HealthService.saveStrengthWorkout(start: start, end: end) {
                log.savedToHealth = true
                try? context.save()
            }
        }
    }
}
