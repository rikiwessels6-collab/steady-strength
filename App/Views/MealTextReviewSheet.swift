import SwiftUI
import SwiftData
import SteadyCore

struct MealTextReviewSheet: View {
    let meal: MealSlot
    let day: Date
    let onAdd: ([FoodDiaryDraft]) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(ContentStore.self) private var store
    @Query(sort: \SavedFood.lastUsed, order: .reverse) private var saved: [SavedFood]
    @Query private var recipes: [Recipe]
    @State private var text = ""
    @State private var lines: [ReviewLine] = []
    @FocusState private var typing: Bool

    private struct ReviewLine: Identifiable {
        let id = UUID()
        let typed: MealText.Line
        let options: [FoodItem]
        let fallback: String?
        var selectedID: String?
        var measure: FoodMeasure?
        var quantity: Double?

        init(typed: MealText.Line, options: [FoodItem], fallback: String?) {
            self.typed = typed
            self.options = options
            self.fallback = fallback
            let suggested = options.first { typed.portion(for: $0)?.amount != nil } ?? options.first
            select(suggested?.id)
        }

        var food: FoodItem? { options.first { $0.id == selectedID } }
        var amount: Double? {
            guard let quantity else { return nil }
            let total = measure.map { $0.grams * quantity } ?? quantity
            return (0...100_000).contains(total) && total > 0 ? total : nil
        }

        mutating func select(_ id: String?) {
            selectedID = id
            let portion = food.flatMap { typed.portion(for: $0) }
            measure = portion?.measure
            quantity = portion?.quantity
            if portion == nil, let food, food.isPerServe {
                measure = food.defaultQuantityMeasure
            }
        }
    }

    private var canAdd: Bool { !lines.isEmpty && lines.allSatisfy { $0.food != nil && $0.amount != nil } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Describe your meal") {
                    TextField("2 eggs, 2 slices of sourdough and a flat white", text: $text, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($typing)
                        .accessibilityIdentifier("mealTextInput")
                    Button("Find foods", action: findFoods)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("findMealTextFoods")
                } footer: {
                    Text("Separate foods with commas or “and”. Review each match and amount before adding it.")
                }
                ForEach($lines) { $line in
                    Section(line.typed.name) {
                        if line.options.isEmpty {
                            Text("No local match. Edit your description, or remove this item and use food search or the barcode scanner.")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else {
                            Picker("Food", selection: Binding(get: { line.selectedID }, set: { line.select($0) })) {
                                ForEach(line.options) { food in
                                    Text([food.name, food.brand].compactMap { $0 }.joined(separator: " · "))
                                        .tag(Optional(food.id))
                                }
                            }
                            if let fallback = line.fallback {
                                Text("Suggested alternative: \(fallback). Check it suits what you ate.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            if let food = line.food {
                                if !food.isPerServe && !food.quantityMeasures.isEmpty {
                                    Picker("Portion", selection: Binding(get: { line.measure }, set: { measure in
                                        line.measure = measure
                                        line.quantity = nil
                                    })) {
                                        Text("Enter \(food.portionUnit)").tag(nil as FoodMeasure?)
                                        ForEach(food.quantityMeasures, id: \.self) { measure in
                                            Text(measure.label).tag(Optional(measure))
                                        }
                                    }
                                }
                                let label = line.measure == nil ? "Amount (\(food.portionUnit))" : "Quantity"
                                LabeledContent(label) {
                                    TextField(label, value: $line.quantity, format: .number)
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.trailing)
                                }
                                if let amount = line.amount {
                                    Text("\(food.macros(grams: amount).kcal.formatted(.number.precision(.fractionLength(0)))) kcal")
                                        .font(.footnote).foregroundStyle(.secondary)
                                } else {
                                    Text("Check the portion and enter the amount you ate.")
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Button("Remove item", role: .destructive) {
                            let id = line.id
                            lines.removeAll { $0.id == id }
                        }
                    }
                }
            }
            .themedList()
            .navigationTitle("Type a meal")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: text) { _, _ in lines = [] }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add to meal", action: addToMeal)
                        .disabled(!canAdd)
                        .accessibilityIdentifier("addTypedMeal")
                }
            }
        }
    }

    private func findFoods() {
        typing = false
        lines = MealText.parse(text).map { typed in
            let options = matches(typed.name)
            let suitable = options.contains { typed.portion(for: $0)?.amount != nil }
            if !suitable, MealText.searchTerms(typed.name).contains("sourdough") {
                let bread = matches("bread")
                if !bread.isEmpty {
                    return ReviewLine(typed: typed, options: unique(options + bread), fallback: "bread matches")
                }
            }
            return ReviewLine(typed: typed, options: options, fallback: nil)
        }
    }

    private func matches(_ name: String) -> [FoodItem] {
        let words = MealText.searchTerms(name)
        let query = words.joined(separator: " ")
        guard !query.isEmpty else { return [] }
        let personal = (saved.compactMap(\.item) + recipes.map(\.asFood)).filter { food in
            let title = MealText.searchTerms(food.name + " " + (food.brand ?? ""))
            return words.allSatisfy(title.contains)
        }
        let menu = store.restaurants?.search(query).map { $0.item.food(chain: $0.chain) } ?? []
        var general = store.genericFoods?.search(query, limit: 18) ?? []
        if query == "egg", let foods = store.genericFoods {
            let common = foods.search("egg chicken whole", limit: 20).filter { food in
                let name = food.name.lowercased()
                return name.hasPrefix("egg, chicken, whole,") && !name.contains("raw")
            }
            general = common + general
        }
        let catalogue = store.nutritionCatalogue?.search(query) ?? []
        var coffee: [FoodItem] = []
        if let style = CoffeeStyle.allCases.first(where: { $0.label.lowercased() == query }),
           let foods = store.genericFoods, let built = CoffeeBuilder.build(CoffeeOrder(style: style), foods: foods) {
            coffee = [built.item]
        }
        return unique(personal + coffee + catalogue + menu + general)
    }

    private func unique(_ options: [FoodItem]) -> [FoodItem] {
        var seen = Set<String>()
        return Array(options.filter { seen.insert($0.id).inserted }.prefix(24))
    }

    private func addToMeal() {
        guard canAdd else { return }
        let date = FoodTiming.defaultEatenAt(for: day)
        let drafts = lines.compactMap { line -> FoodDiaryDraft? in
            guard let food = line.food, let amount = line.amount else { return nil }
            let entry = FoodEntry(item: food, grams: amount, meal: meal, source: .search, eatenAt: date)
            let recipe = recipes.first { $0.asFood.id == food.id }
            return FoodDiaryDraft(entry: entry, food: recipe == nil ? food : nil, recipe: recipe)
        }
        guard drafts.count == lines.count else { return }
        onAdd(drafts)
        dismiss()
    }
}
