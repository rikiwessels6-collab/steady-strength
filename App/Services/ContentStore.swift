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
    private(set) var nutritionCatalogue: NutritionCatalogue?
    private var refreshingCatalogue = false

    func refreshNutritionCatalogue() async {
        guard !refreshingCatalogue,
              let address = Bundle.main.object(forInfoDictionaryKey: "NutritionCatalogueURL") as? String,
              let url = URL(string: address), url.scheme == "https", url.host != nil else { return }
        refreshingCatalogue = true
        defer { refreshingCatalogue = false }

        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("au-operator-menus.json")
        if nutritionCatalogue == nil, let cache, let data = try? Data(contentsOf: cache) {
            nutritionCatalogue = try? NutritionCatalogue(data: data)
        }
        if let cache, let date = (try? cache.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
           nutritionCatalogue != nil, Date.now.timeIntervalSince(date) < 24 * 60 * 60 { return }
        do {
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  http.url?.scheme == "https", data.count <= 10 * 1024 * 1024 else { return }
            let catalogue = try NutritionCatalogue(data: data)
            if let cache { try? data.write(to: cache, options: .atomic) }
            nutritionCatalogue = catalogue
        } catch {
            // Keep the last validated snapshot available if the source is offline.
        }
    }

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
