import Foundation
import Observation
import SteadyCore

/// The bundled programs, exercise library, equipment profiles and check-in
/// defaults (Resources/Generated, built by tools/importer). Loaded once, off
/// the main thread.
@Observable
@MainActor
final class ContentStore {
    enum State { case loading, ready(BundledContent), failed(String) }
    private(set) var state: State = .loading
    /// The user's own exercises, merged into `content.library`.
    private var custom: [Exercise] = []
    private var customPrograms: [Program] = []
    private(set) var content: BundledContent?
    /// Restaurant and takeaway menus, loaded with the rest of the content.
    private(set) var restaurants: RestaurantMenus?
    /// Everyday generic foods (AUSNUT 2023), searchable offline.
    private(set) var genericFoods: GenericFoods?
    private var base: BundledContent?

    /// Replaces the user's own exercises (called at launch and after one is added or edited).
    func setCustom(_ exercises: [Exercise]) {
        custom = exercises
        rebuild()
    }

    /// Replaces the programs you built (called at launch and after one is saved or deleted).
    func setCustomPrograms(_ programs: [Program]) {
        customPrograms = programs
        rebuild()
    }

    private func rebuild() {
        content = base?.adding(custom, programs: customPrograms)
    }

    func load() async {
        guard case .loading = state else { return }
        do {
            let loaded = try await Task.detached(priority: .userInitiated) { () throws -> BundledContent in
                func data(_ name: String) throws -> Data {
                    guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
                        throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "\(name).json"])
                    }
                    return try Data(contentsOf: url)
                }
                return try BundledContent(programs: data("programs"), library: data("exercise_library"),
                                          equipment: data("equipment"), checkIn: data("checkin_defaults"))
            }.value
            base = loaded
            if let url = Bundle.main.url(forResource: "restaurants", withExtension: "json"),
               let data = try? Data(contentsOf: url) {
                restaurants = try? RestaurantMenus(data: data)
            }
            rebuild()
            state = .ready(loaded)
            genericFoods = await Task.detached(priority: .utility) { () -> GenericFoods? in
                guard let url = Bundle.main.url(forResource: "ausnut_2023", withExtension: "json"),
                      let data = try? Data(contentsOf: url) else { return nil }
                return try? GenericFoods(data: data)
            }.value
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
