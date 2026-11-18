import XCTest
@testable import SteadyCore

final class RestaurantTests: XCTestCase {
    private func bundled() throws -> RestaurantMenus {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Restaurants/restaurants.json")
        return try RestaurantMenus(data: Data(contentsOf: url))
    }

    func testBundledMenusDecode() throws {
        let menus = try bundled()
        XCTAssertFalse(menus.chains.isEmpty)
        XCTAssertTrue(menus.chains.allSatisfy { !$0.items.isEmpty })
    }

    func testOneServeLogsTheGuideNumbers() throws {
        let menus = try bundled()
        let chain = try XCTUnwrap(menus.chains.first { $0.id == "mcdonalds-au" })
        let cookie = try XCTUnwrap(chain.items.first { $0.id == "mcd-loaded-choc-chip-cookie" })
        let food = cookie.food(chain: chain)
        let m = food.macros(grams: try XCTUnwrap(food.servingGrams))
        XCTAssertEqual(m.kcal, 601, accuracy: 0.5)
        XCTAssertEqual(m.protein, 6.9, accuracy: 0.05)
        XCTAssertEqual(m.sugar ?? 0, 46.4, accuracy: 0.05)
        XCTAssertEqual(food.brand, "McDonald's")
    }

    func testBurgersWithoutAWeightAreLoggedByTheServe() throws {
        let menus = try bundled()
        let chain = try XCTUnwrap(menus.chains.first { $0.id == "mcdonalds-au" })
        let bigMac = try XCTUnwrap(chain.items.first { $0.id == "mcd-au-big-mac-2025" })
        XCTAssertTrue(bigMac.isPerServe)
        let food = bigMac.food(chain: chain)
        XCTAssertTrue(food.isPerServe)
        XCTAssertEqual(food.macros(grams: 100).kcal, 559, accuracy: 0.01)          // one burger
        XCTAssertEqual(food.macros(grams: 150).protein, 25.9 * 1.5, accuracy: 0.01) // one and a half
        XCTAssertEqual(food.servingLabel, "1 standard burger")
        XCTAssertFalse(chain.sources.isEmpty)
    }

    func testSearchMatchesEveryWord() throws {
        let menus = try bundled()
        XCTAssertFalse(menus.search("tiramisu oat large").isEmpty)
        XCTAssertTrue(menus.search("tiramisu oat large").allSatisfy { $0.item.name.lowercased().contains("oat") })
        XCTAssertFalse(menus.search("mcdonald's cookie").isEmpty)
        XCTAssertTrue(menus.search("").isEmpty)
        XCTAssertTrue(menus.search("zzzz").isEmpty)
    }

    func testKFCEnergyOnlyItemsLogCaloriesWithoutMacros() throws {
        let menus = try bundled()
        let chain = try XCTUnwrap(menus.chains.first { $0.id == "kfc-au" })
        let wings = try XCTUnwrap(chain.items.first { $0.id == "kfc-3-wicked-wings" })
        XCTAssertTrue(wings.isEnergyOnly)
        XCTAssertNil(wings.protein)
        let food = wings.food(chain: chain)
        let m = food.macros(grams: 100)                                   // one serve
        XCTAssertEqual(m.kcal, 389, accuracy: 0.5)                        // 1629 kJ
        XCTAssertEqual(m.protein + m.carbs + m.fat, 0)

        let burger = try XCTUnwrap(chain.items.first { $0.id == "kfc-original-crispy-burger" })
        XCTAssertFalse(burger.isEnergyOnly)
        XCTAssertEqual(burger.food(chain: chain).macros(grams: 183).protein, 24.7, accuracy: 0.01)
    }
}
