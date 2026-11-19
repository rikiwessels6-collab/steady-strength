import Foundation

/// Nutrition per 100 g (or 100 ml), the way labels and Open Food Facts give it.
public struct Per100: Codable, Equatable, Sendable {
    public var kcal: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public var fibre: Double
    /// Optional detail, when the label or database gives it: sugars and saturated fat in grams, sodium in milligrams.
    public var sugar: Double? = nil
    public var satFat: Double? = nil
    public var sodium: Double? = nil
    public init(kcal: Double, protein: Double, carbs: Double, fat: Double, fibre: Double = 0,
                sugar: Double? = nil, satFat: Double? = nil, sodium: Double? = nil) {
        self.kcal = kcal; self.protein = protein; self.carbs = carbs; self.fat = fat; self.fibre = fibre
        self.sugar = sugar; self.satFat = satFat; self.sodium = sodium
    }
}

public struct Macros: Equatable, Sendable {
    public var kcal: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public var fibre: Double
    /// Detail totals (nil when no food in the total listed it).
    public var sugar: Double?
    public var satFat: Double?
    public var sodium: Double?
    public init(kcal: Double = 0, protein: Double = 0, carbs: Double = 0, fat: Double = 0, fibre: Double = 0,
                sugar: Double? = nil, satFat: Double? = nil, sodium: Double? = nil) {
        self.kcal = kcal; self.protein = protein; self.carbs = carbs; self.fat = fat; self.fibre = fibre
        self.sugar = sugar; self.satFat = satFat; self.sodium = sodium
    }
    public static func + (a: Macros, b: Macros) -> Macros {
        func add(_ x: Double?, _ y: Double?) -> Double? { x == nil && y == nil ? nil : (x ?? 0) + (y ?? 0) }
        return Macros(kcal: a.kcal + b.kcal, protein: a.protein + b.protein, carbs: a.carbs + b.carbs,
                      fat: a.fat + b.fat, fibre: a.fibre + b.fibre,
                      sugar: add(a.sugar, b.sugar), satFat: add(a.satFat, b.satFat), sodium: add(a.sodium, b.sodium))
    }
}

/// A household portion and its weight, e.g. "1 slice" = 35 g.
public struct FoodMeasure: Codable, Equatable, Sendable, Hashable {
    public var label: String
    public var grams: Double
    public init(label: String, grams: Double) { self.label = label; self.grams = grams }
}

/// A food you can log: from a barcode, a search, or entered by hand.
public struct FoodItem: Codable, Equatable, Sendable, Identifiable {
    public var id: String               // barcode, or a generated id for custom foods
    public var name: String
    public var brand: String?
    public var barcode: String?
    public var per100: Per100
    public var servingGrams: Double?    // one serving as printed on the pack
    public var servingLabel: String?
    /// Household portions from a food database ("1 slice", "1 cup"), when it lists them.
    public var measures: [FoodMeasure]? = nil
    /// Nil for legacy foods and foods measured in grams.
    public var amountUnit: String?
    public var portionUnit: String { amountUnit == "mL" ? "mL" : "g" }

    public init(id: String, name: String, brand: String?, barcode: String?, per100: Per100,
                servingGrams: Double?, servingLabel: String?, measures: [FoodMeasure]? = nil, amountUnit: String? = nil) {
        self.id = id; self.name = name; self.brand = brand; self.barcode = barcode
        self.per100 = per100; self.servingGrams = servingGrams; self.servingLabel = servingLabel
        self.measures = measures
        self.amountUnit = amountUnit
    }

    public func macros(grams: Double) -> Macros {
        let f = grams / 100
        return Macros(kcal: per100.kcal * f, protein: per100.protein * f, carbs: per100.carbs * f,
                      fat: per100.fat * f, fibre: per100.fibre * f,
                      sugar: per100.sugar.map { $0 * f }, satFat: per100.satFat.map { $0 * f }, sodium: per100.sodium.map { $0 * f })
    }

    public var defaultGrams: Double { servingGrams ?? 100 }
}

public enum MealSlot: String, Codable, CaseIterable, Sendable, Identifiable {
    case breakfast, lunch, dinner, snacks
    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }

    /// The likely meal for a time of day.
    public static func suggested(for date: Date, calendar: Calendar = .current) -> MealSlot {
        switch calendar.component(.hour, from: date) {
        case 4..<11: return .breakfast
        case 11..<15: return .lunch
        case 17..<22: return .dinner
        default: return .snacks
        }
    }
}

/// How a food entry was made. Kept on every entry with its timestamps.
public enum FoodSource: String, Codable, CaseIterable, Sendable {
    case barcode, search, recent, saved, manual, photo
}

/// Open Food Facts (openfoodfacts.org, data under the ODbL licence).
/// Only the barcode or search words are sent; nothing about the user.
public enum OpenFoodFacts {
    public static let userAgent = "SteadyStrength/0.1 (https://github.com/rikiwessels6-collab/steady-strength)"
    static let fields = "code,product_name,product_name_en,brands,nutriments,serving_quantity,serving_size,stores_tags,countries_tags"

    public static func barcodeKey(_ barcode: String) -> String? {
        let code = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (8...14).contains(code.count), code.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return String(repeating: "0", count: 14 - code.count) + code
    }

    public static func productURL(barcode: String) -> URL? {
        guard barcodeKey(barcode) != nil else { return nil }
        let code = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json?fields=\(fields)")
    }

    public enum Retailer: String, CaseIterable, Identifiable, Sendable {
        case aldi = "ALDI", woolworths = "Woolworths", coles = "Coles", iga = "IGA"
        public var id: String { rawValue }
    }

    /// Search, preferring products sold in Australia.
    public static func searchURL(_ query: String, page: Int = 1, retailer: Retailer? = nil) -> URL? {
        var c = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")!
        c.queryItems = [
            .init(name: "search_terms", value: query), .init(name: "search_simple", value: "1"),
            .init(name: "action", value: "process"), .init(name: "json", value: "1"),
            .init(name: "page_size", value: "25"), .init(name: "page", value: String(page)),
            .init(name: "tagtype_0", value: "countries"), .init(name: "tag_contains_0", value: "contains"),
            .init(name: "tag_0", value: "australia"), .init(name: "fields", value: fields),
        ]
        if let retailer {
            c.queryItems?.append(contentsOf: [
                .init(name: "tagtype_1", value: "stores"), .init(name: "tag_contains_1", value: "contains"),
                .init(name: "tag_1", value: retailer.rawValue.lowercased()),
            ])
        }
        return c.url
    }

    struct ProductResponse: Decodable { let status: Int?; let product: Product? }
    struct SearchResponse: Decodable { let products: [Product] }

    struct Product: Decodable {
        let code: String?
        let product_name: String?
        let product_name_en: String?
        let brands: String?
        let nutriments: [String: Flexible]?
        let serving_quantity: Flexible?
        let serving_size: String?
        let stores_tags: [String]?
        let countries_tags: [String]?
    }

    /// OFF numbers arrive as numbers or strings.
    struct Flexible: Decodable {
        let value: Double?
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let d = try? c.decode(Double.self) { value = d }
            else if let s = try? c.decode(String.self) { value = Double(s.replacingOccurrences(of: ",", with: ".")) }
            else { value = nil }
        }
    }

    static func item(from p: Product) -> FoodItem? {
        let name = (p.product_name_en?.isEmpty == false ? p.product_name_en : p.product_name)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name, !name.isEmpty, let n = p.nutriments else { return nil }
        func v(_ k: String, atMost limit: Double) -> Double? {
            guard let value = n[k]?.value, (0...limit).contains(value) else { return nil }
            return value
        }
        // Energy: prefer kcal; otherwise convert kJ (Australian labels are kJ-first).
        let kcal = v("energy-kcal_100g", atMost: 950)
            ?? (v("energy-kj_100g", atMost: 3974.8) ?? v("energy_100g", atMost: 3974.8)).map { $0 / 4.184 }
        guard let kcal else { return nil }
        let sodiumMg = v("sodium_100g", atMost: 40).map { $0 * 1000 }
            ?? v("salt_100g", atMost: 100).map { $0 / 2.5 * 1000 }
        let per = Per100(kcal: kcal, protein: v("proteins_100g", atMost: 100) ?? 0,
                         carbs: v("carbohydrates_100g", atMost: 100) ?? 0, fat: v("fat_100g", atMost: 100) ?? 0,
                         fibre: v("fiber_100g", atMost: 100) ?? 0, sugar: v("sugars_100g", atMost: 100),
                         satFat: v("saturated-fat_100g", atMost: 100), sodium: sodiumMg)
        let code = p.code ?? UUID().uuidString
        let brand = p.brands?.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }
        let serving = p.serving_quantity?.value.flatMap { (0.001...10_000).contains($0) ? $0 : nil }
        return FoodItem(id: code, name: name, brand: brand, barcode: p.code, per100: per,
                        servingGrams: serving, servingLabel: p.serving_size)
    }

    public static func parseProduct(_ data: Data) throws -> FoodItem? {
        let r = try JSONDecoder().decode(ProductResponse.self, from: data)
        guard r.status != 0, let p = r.product else { return nil }
        // A barcode match with missing core values goes to label capture instead of being saved as zero.
        guard hasCoreNutrition(p) else { return nil }
        return item(from: p)
    }

    private static func hasCoreNutrition(_ product: Product) -> Bool {
        ["proteins_100g", "carbohydrates_100g", "fat_100g"].allSatisfy { key in
            guard let value = product.nutriments?[key]?.value else { return false }
            return (0...100).contains(value)
        }
    }

    public static func parseSearch(_ data: Data, retailer: Retailer? = nil) throws -> [FoodItem] {
        let products = try JSONDecoder().decode(SearchResponse.self, from: data).products
        guard let retailer else { return products.compactMap(item(from:)) }
        return products.filter { product in
            product.countries_tags?.contains("en:australia") == true
                && product.stores_tags?.contains(retailer.rawValue.lowercased()) == true
                && hasCoreNutrition(product)
        }.compactMap(item(from:))
    }
}
