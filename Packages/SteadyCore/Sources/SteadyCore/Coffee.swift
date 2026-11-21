import Foundation

/// A coffee made at home, built from AUSNUT 2023 values for the coffee, the milk and the sugar.
/// Volumes are converted to grams with each food's published density.
public enum CoffeeStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case espresso, doubleEspresso, flatWhite, latte, cappuccino, longBlack, mug
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .espresso: "Espresso"
        case .doubleEspresso: "Double espresso"
        case .flatWhite: "Flat white"
        case .latte: "Latte"
        case .cappuccino: "Cappuccino"
        case .longBlack: "Long black"
        case .mug: "Mug coffee"
        }
    }

    /// Starting amounts (coffee per capsule or shot, then milk), which the user can change.
    public var defaults: (brewMl: Double, milkMl: Double) {
        switch self {
        case .espresso: (40, 0)
        case .doubleEspresso: (80, 0)
        case .flatWhite: (80, 150)
        case .latte: (80, 200)
        case .cappuccino: (40, 120)
        case .longBlack: (150, 0)
        case .mug: (230, 0)
        }
    }
}

public enum CoffeeMilk: String, Codable, CaseIterable, Sendable, Identifiable {
    case noMilk, fullCream, lactoseFree, creamy, reducedFat, skim, soy, oat, almond
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .noMilk: "No milk"
        case .fullCream: "Full cream"
        case .lactoseFree: "Lactose free"
        case .creamy: "Rich or creamy"
        case .reducedFat: "Reduced fat"
        case .skim: "Skim"
        case .soy: "Soy"
        case .oat: "Oat"
        case .almond: "Almond, unsweetened"
        }
    }

    /// The AUSNUT 2023 food used for this milk.
    public var ausnutId: String? {
        switch self {
        case .noMilk: nil
        case .fullCream: "F005634"   // Milk, cow, fluid, regular fat (~3.5%)
        case .lactoseFree: "F005599" // Milk, cow, fluid, regular fat (~3.5%), lactose free
        case .creamy: "F009840"      // Milk, cow, fluid, rich or creamy (~4.5% fat)
        case .reducedFat: "F005614"  // Milk, cow, fluid, reduced fat (~1%)
        case .skim: "F005637"        // Milk, cow, fluid, skim (~0.1% fat)
        case .soy: "F008717"         // Soy beverage, regular fat (~3%), not further defined
        case .oat: "F006132"         // Oat beverage, unfortified
        case .almond: "F009824"      // Almond beverage, no added sugar, unfortified
        }
    }
}

public struct CoffeeOrder: Codable, Equatable, Sendable {
    public var style: CoffeeStyle
    /// Coffee per capsule or shot, in mL.
    public var brewMl: Double
    public var capsules: Int
    public var capsuleName: String?
    public var milk: CoffeeMilk
    public var milkMl: Double
    /// Level 5 mL teaspoons of white sugar.
    public var sugarTsp: Double

    public init(style: CoffeeStyle, brewMl: Double? = nil, capsules: Int = 1, milk: CoffeeMilk = .fullCream,
                milkMl: Double? = nil, sugarTsp: Double = 0, capsuleName: String? = nil) {
        self.style = style
        self.brewMl = brewMl ?? style.defaults.brewMl
        self.capsules = capsules
        self.capsuleName = capsuleName
        self.milkMl = milkMl ?? style.defaults.milkMl
        self.milk = (milkMl ?? style.defaults.milkMl) > 0 ? milk : .noMilk
        self.sugarTsp = sugarTsp
    }

    public var namedCapsule: String? {
        let name = capsuleName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? nil : name
    }

    /// Vertuo cup sizes (nominal), offered as quick picks for the coffee amount.
    public static let vertuoSizes: [CupSize] = [
        CupSize(label: "Espresso", ml: 40), CupSize(label: "Double espresso", ml: 80), CupSize(label: "Gran lungo", ml: 150),
        CupSize(label: "Mug", ml: 230), CupSize(label: "Alto", ml: 355), CupSize(label: "Carafe", ml: 535),
    ]

    public struct CupSize: Sendable, Identifiable, Hashable {
        public let label: String
        public let ml: Double
        public var id: Double { ml }
    }
}

public struct CoffeePart: Equatable, Sendable {
    public let name: String
    public let grams: Double
    public let macros: Macros
}

public struct BuiltCoffee: Sendable {
    public let item: FoodItem
    /// The whole cup, in grams (log this amount).
    public let grams: Double
    public let parts: [CoffeePart]
    public var macros: Macros { parts.reduce(Macros()) { $0 + $1.macros } }
}

public enum CoffeeBuilder {
    public static let espressoId = "F003041"   // Coffee, espresso
    public static let longBlackId = "F003063"  // Coffee, long black, double shot (espresso topped up with water)
    public static let sugarId = "F008976"      // Sugar, white, granulated or lump
    public static let teaspoonMl = 5.0         // Australian standard teaspoon

    /// Coffee up to 80 mL per capsule is treated as espresso; longer pours as long black.
    public static func coffeeId(brewMl: Double) -> String { brewMl <= 80 ? espressoId : longBlackId }

    public static func build(_ order: CoffeeOrder, foods: GenericFoods) -> BuiltCoffee? {
        var parts: [CoffeePart] = []
        func add(_ id: String, ml: Double, label: String) -> Bool {
            guard ml > 0 else { return true }
            guard let f = foods.food(id: id) else { return false }
            let g = ml * (f.density ?? 1)
            parts.append(CoffeePart(name: label, grams: g, macros: foods.item(f).macros(grams: g)))
            return true
        }
        let coffeeMl = order.brewMl * Double(max(order.capsules, 1))
        guard add(coffeeId(brewMl: order.brewMl), ml: coffeeMl, label: order.namedCapsule ?? "Coffee") else { return nil }
        if let milk = order.milk.ausnutId, order.milkMl > 0 {
            guard add(milk, ml: order.milkMl, label: order.milk.label + " milk") else { return nil }
        }
        guard add(sugarId, ml: order.sugarTsp * teaspoonMl, label: "Sugar") else { return nil }

        let grams = parts.reduce(0) { $0 + $1.grams }
        guard grams > 0 else { return nil }
        let m = parts.reduce(Macros()) { $0 + $1.macros }
        let k = 100 / grams
        let per = Per100(kcal: m.kcal * k, protein: m.protein * k, carbs: m.carbs * k, fat: m.fat * k, fibre: m.fibre * k,
                         sugar: m.sugar.map { $0 * k }, satFat: m.satFat.map { $0 * k }, sodium: m.sodium.map { $0 * k })
        let totalMl = coffeeMl + (order.milk == .noMilk ? 0 : order.milkMl)
        let item = FoodItem(id: id(order), name: name(order), brand: "Home coffee · AUSNUT 2023", barcode: nil, per100: per,
                            servingGrams: grams, servingLabel: "1 cup, \(NumberText.format(totalMl)) mL")
        return BuiltCoffee(item: item, grams: grams, parts: parts)
    }

    /// The same coffee always gets the same id, so a favourite stays one favourite.
    public static func id(_ o: CoffeeOrder) -> String {
        let base = "coffee-\(o.style.rawValue)-\(Int(o.brewMl))x\(o.capsules)-\(o.milk.rawValue)-\(Int(o.milkMl))-\(Int((o.sugarTsp * 10).rounded()))"
        guard let capsule = o.namedCapsule else { return base }
        let key = Data(capsule.lowercased().utf8).base64EncodedString()
        return base + "-capsule-" + key
    }

    public static func name(_ o: CoffeeOrder) -> String {
        let coffee = o.namedCapsule ?? "coffee"
        var bits = ["\(NumberText.format(o.brewMl * Double(max(o.capsules, 1)))) mL \(coffee)"]
        if o.milk != .noMilk && o.milkMl > 0 { bits.append("\(NumberText.format(o.milkMl)) mL \(o.milk.label.lowercased()) milk") }
        if o.sugarTsp > 0 { bits.append("\(NumberText.format(o.sugarTsp)) tsp sugar") }
        return "\(o.style.label) (\(bits.joined(separator: ", ")))"
    }
}
