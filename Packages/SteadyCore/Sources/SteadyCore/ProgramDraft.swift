import Foundation

/// A program you build in the app: the same sessions every week for a number of weeks, with your own
/// exercises, sets, reps, reps in reserve and rest. Weights progress from what you log, like every program.
public struct ProgramDraft: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var weeks: Int
    public var notes: String
    public var workouts: [WorkoutDraft]

    public init(id: String = "mine-" + UUID().uuidString.prefix(8).lowercased(), name: String = "", weeks: Int = 8,
                notes: String = "", workouts: [WorkoutDraft] = []) {
        self.id = id; self.name = name; self.weeks = weeks; self.notes = notes; self.workouts = workouts
    }

    /// Ready to save: a name, and at least one session with at least one exercise.
    public var isComplete: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !workouts.isEmpty && workouts.allSatisfy { !$0.slots.isEmpty }
    }
}

public struct WorkoutDraft: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var slots: [SlotDraft]
    public init(id: String = UUID().uuidString, name: String, slots: [SlotDraft] = []) {
        self.id = id; self.name = name; self.slots = slots
    }

    /// About how long the session takes: working time and rest for each set, plus a 7 minute warm-up and 5 minute cool-down.
    public var estimatedMinutes: Int {
        let seconds = slots.reduce(0) { $0 + $1.sets * (40 + $1.restSeconds) }
        return Int((Double(seconds) / 60).rounded()) + 12
    }
}

public struct SlotDraft: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var exerciseId: String
    public var exerciseName: String
    public var sets: Int
    public var repMin: Int
    public var repMax: Int
    /// Reps in reserve, if you want to prescribe effort.
    public var rirMin: Double?
    public var rirMax: Double?
    public var restSeconds: Int
    public var perSide: Bool

    public init(id: String = UUID().uuidString, exerciseId: String, exerciseName: String, sets: Int = 3, repMin: Int = 8,
                repMax: Int = 12, rirMin: Double? = 2, rirMax: Double? = 3, restSeconds: Int = 90, perSide: Bool = false) {
        self.id = id; self.exerciseId = exerciseId; self.exerciseName = exerciseName; self.sets = sets
        self.repMin = repMin; self.repMax = repMax; self.rirMin = rirMin; self.rirMax = rirMax
        self.restSeconds = restSeconds; self.perSide = perSide
    }

    /// "3 × 8-12 · 2-3 RIR · 90 s rest"
    public var summary: String {
        let reps = repMin == repMax ? "\(repMin)" : "\(repMin)-\(repMax)"
        var parts = ["\(sets) × \(reps)\(perSide ? " each side" : "")"]
        if let lo = rirMin, let hi = rirMax {
            parts.append(lo == hi ? "\(NumberText.format(lo)) RIR" : "\(NumberText.format(lo))-\(NumberText.format(hi)) RIR")
        }
        parts.append(restSeconds >= 60 && restSeconds % 30 == 0 ? "\(NumberText.format(Double(restSeconds) / 60)) min rest" : "\(restSeconds) s rest")
        return parts.joined(separator: " · ")
    }
}

extension ProgramDraft {
    /// Builds the program the rest of the app runs, in exactly the shape of a bundled one.
    /// - mainLiftIds: exercises to treat as main lifts (warm-up sets, larger weight steps).
    public func makeProgram(mainLiftIds: Set<String> = []) throws -> Program {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let sessions: [[String: Any]] = workouts.enumerated().map { pos, w in
            let slots: [[String: Any]] = w.slots.enumerated().map { order, s in
                let lo = max(1, min(s.repMin, s.repMax)), hi = max(s.repMin, s.repMax, 1)
                let reps: [String: Any] = lo == hi
                    ? ["raw": "\(lo)", "perSide": s.perSide, "kind": "fixed", "reps": lo]
                    : ["raw": "\(lo)-\(hi)", "perSide": s.perSide, "kind": "range", "min": lo, "max": hi]
                var slot: [String: Any] = [
                    "exercise": s.exerciseName, "exerciseId": s.exerciseId, "order": order + 1,
                    "sets": ["count": max(1, s.sets), "perSide": false], "reps": reps,
                    "rest": ["raw": "\(s.restSeconds)sec", "minSec": s.restSeconds, "maxSec": s.restSeconds],
                    "isMainLift": mainLiftIds.contains(s.exerciseId), "alternativeIds": [String](),
                ]
                if let a = s.rirMin, let b = s.rirMax {
                    let lo = min(a, b), hi = max(a, b)
                    slot["effort"] = ["type": "rir", "raw": lo == hi ? NumberText.format(lo) : "\(NumberText.format(lo))-\(NumberText.format(hi))",
                                      "min": lo, "max": hi]
                }
                return slot
            }
            return ["name": w.name, "rawName": w.name, "position": pos + 1, "estimatedMinutes": w.estimatedMinutes,
                    "optional": false, "displayName": "\(cleanName) · \(w.name)", "slots": slots]
        }
        let weekCount = max(1, weeks)
        let program: [String: Any] = [
            "id": id, "name": cleanName, "masterName": cleanName, "author": "You",
            "intensityType": "rir", "unit": "kg", "status": "complete", "family": "mine",
            "catalogue": "mine", "contentStatus": "owner-built",
            "description": "Your own program: \(weekCount) week\(weekCount == 1 ? "" : "s"), \(workouts.count) session\(workouts.count == 1 ? "" : "s") a week.",
            "programNotes": notes.isEmpty ? [String]() : [notes], "maxSwapDifficulty": 3,
            "equipmentNeeded": [String](), "equipmentCoverage": [String: Any](),
            "weeks": (1...weekCount).map { n in ["number": n, "label": "Week \(n)", "workouts": sessions] as [String: Any] },
        ]
        let data = try JSONSerialization.data(withJSONObject: program)
        return try JSONDecoder().decode(Program.self, from: data)
    }

    /// A starting point copied from an existing program's first week, to change as you like.
    public static func copy(of program: Program, name: String) -> ProgramDraft {
        let first = program.weeks.first?.workouts ?? []
        let workouts = first.map { w in
            WorkoutDraft(name: w.name, slots: w.slots.map { s in
                var lo = 8, hi = 12
                switch s.reps.scheme {
                case .fixed(let n): lo = n; hi = n
                case .range(let a, let b): lo = Int(a); hi = Int(b)
                case .perSet(let list): lo = list.min() ?? 8; hi = list.max() ?? 12
                case .plus(let n): lo = n; hi = n
                default: break
                }
                let rest = s.rest.flatMap { r in r.maxSec.map { max($0, r.minSec ?? $0) } } ?? 90
                return SlotDraft(exerciseId: s.exerciseId, exerciseName: s.exercise.capitalized, sets: s.sets.count ?? 3,
                                 repMin: lo, repMax: hi,
                                 rirMin: s.effort?.type == .rir ? s.effort?.min : nil,
                                 rirMax: s.effort?.type == .rir ? s.effort?.max : nil,
                                 restSeconds: rest, perSide: s.reps.perSide)
            })
        }
        return ProgramDraft(name: name, weeks: program.weeks.count, workouts: workouts)
    }
}
