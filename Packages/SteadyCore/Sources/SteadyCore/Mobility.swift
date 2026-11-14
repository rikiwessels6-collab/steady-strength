import Foundation

/// A short guided mobility or stretching routine: timed steps, played one after another.
public struct MobilityStep: Equatable, Sendable, Identifiable {
    public var id: String { name + (side ?? "") }
    public var name: String
    public var seconds: Int
    public var cue: String
    /// "Left" or "Right" for one-sided moves (they are listed as two steps).
    public var side: String?
}

public struct MobilityRoutine: Identifiable, Sendable {
    public var id: String
    public var name: String
    public var summary: String
    public var steps: [MobilityStep]
    public var minutes: Int { Int((Double(steps.reduce(0) { $0 + $1.seconds }) / 60).rounded()) }

    /// Builds the step list: a one-sided move becomes a left step and a right step.
    init(id: String, name: String, summary: String, moves: [(name: String, seconds: Int, cue: String, eachSide: Bool)]) {
        self.id = id; self.name = name; self.summary = summary
        self.steps = moves.flatMap { m -> [MobilityStep] in
            m.eachSide
                ? [MobilityStep(name: m.name, seconds: m.seconds, cue: m.cue, side: "Left"),
                   MobilityStep(name: m.name, seconds: m.seconds, cue: m.cue, side: "Right")]
                : [MobilityStep(name: m.name, seconds: m.seconds, cue: m.cue, side: nil)]
        }
    }
}

/// General stretching and mobility routines for rest days or after training. Gentle ranges only:
/// ease in, breathe slowly, and stop any move that causes pain.
public enum Mobility {
    public static let routines: [MobilityRoutine] = [
        MobilityRoutine(id: "hips-back", name: "Hips and lower back", summary: "For tight hips after sitting or lower-body days.", moves: [
            ("Cat-cow", 45, "On hands and knees, slowly round then arch your back with your breath.", false),
            ("Half-kneeling hip flexor stretch", 40, "Tuck your tailbone and squeeze the back glute until you feel the front of the hip.", true),
            ("90/90 hip switch", 45, "Sit tall and rotate your knees side to side, slowly and under control.", false),
            ("Figure-four glute stretch", 40, "On your back, cross one ankle over the other knee and draw the legs in.", true),
            ("Child's pose", 45, "Sit back onto your heels, arms long, and breathe into your back.", false),
        ]),
        MobilityRoutine(id: "shoulders-upper-back", name: "Shoulders and upper back", summary: "For desk days and before pressing or pulling.", moves: [
            ("Thread the needle", 40, "From hands and knees, reach one arm under your body and let your upper back rotate.", true),
            ("Open book", 40, "Lying on your side, knees bent, open the top arm across and follow it with your eyes.", true),
            ("Doorway chest stretch", 40, "Forearm on a door frame at shoulder height, step through gently.", true),
            ("Wall slides", 45, "Back and arms against a wall, slide up and down without arching your lower back.", false),
            ("Neck side stretch", 30, "Ear towards shoulder, shoulders relaxed, no pulling.", true),
        ]),
        MobilityRoutine(id: "full-body", name: "Full body reset", summary: "A rest-day routine from neck to ankles.", moves: [
            ("World's greatest stretch", 40, "Long lunge, hand inside the front foot, then rotate the other arm to the ceiling.", true),
            ("Downward dog", 45, "Hips high, pedal the heels slowly.", false),
            ("Seated hamstring stretch", 40, "Leg out straight, hinge from the hips with a long back.", true),
            ("Deep squat hold", 45, "Hold a support if you need to. Heels down, chest up.", false),
            ("Ankle rocks", 30, "Half-kneeling, drive the front knee forward over the toes and back.", true),
            ("Lying twist", 40, "On your back, knees to one side, shoulders on the floor.", true),
        ]),
    ]

    public static func routine(_ id: String) -> MobilityRoutine? { routines.first { $0.id == id } }
}

/// Cardio and conditioning sessions logged in the app.
public enum CardioKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case run, walk, bike, rower, elliptical, stairs, swim, intervals, other
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .run: return "Run or treadmill"
        case .walk: return "Walk or incline walk"
        case .bike: return "Bike"
        case .rower: return "Rower"
        case .elliptical: return "Cross-trainer"
        case .stairs: return "Stair climber"
        case .swim: return "Swim"
        case .intervals: return "Intervals or circuits"
        case .other: return "Other cardio"
        }
    }
    public var symbol: String {
        switch self {
        case .run: return "figure.run"
        case .walk: return "figure.walk"
        case .bike: return "figure.outdoor.cycle"
        case .rower: return "figure.rower"
        case .elliptical: return "figure.elliptical"
        case .stairs: return "figure.stair.stepper"
        case .swim: return "figure.pool.swim"
        case .intervals: return "figure.highintensity.intervaltraining"
        case .other: return "heart.circle"
        }
    }
    /// Whether distance is worth asking for.
    public var hasDistance: Bool { [.run, .walk, .bike, .rower, .swim].contains(self) }
}
