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

    func testSearchMatchesEveryWord() throws {
        let menus = try bundled()
        XCTAssertFalse(menus.search("tiramisu oat large").isEmpty)
        XCTAssertTrue(menus.search("tiramisu oat large").allSatisfy { $0.item.name.lowercased().contains("oat") })
        XCTAssertFalse(menus.search("mcdonald's cookie").isEmpty)
        XCTAssertTrue(menus.search("").isEmpty)
        XCTAssertTrue(menus.search("zzzz").isEmpty)
    }
}
