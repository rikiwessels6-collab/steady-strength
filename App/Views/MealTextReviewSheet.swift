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
    @State private var customLineID: UUID?
    @FocusState private var typing: Bool

    private struct ReviewLine: Identifiable {
        let id = UUID()
        let typed: MealText.Line
        var options: [FoodItem]
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
                Section {
                    TextField("2 eggs, 2 slices of sourdough and a flat white", text: $text, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($typing)
                        .accessibilityIdentifier("mealTextInput")
                    Button("Find foods", action: findFoods)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("findMealTextFoods")
                } header: {
                    Text("Describe your meal")
                } footer: {
                    Text("Separate foods with commas or “and”. Review each match and amount before adding it.")
                }
                ForEach($lines) { $line in
                    Section {
                        if line.options.isEmpty {
                            Text("We could not find a close local match. You can still add it yourself and save it for next time.")
                                .font(.footnote).foregroundStyle(.secondary)
                            Button("Create custom food") { customLineID = line.id }
                                .accessibilityIdentifier("createTypedFood")
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
                    } header: {
                        Text(line.typed.name)
                    }
                }
            }
            .themedList()
            .navigationTitle("Type a meal")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: text) { _, _ in lines = [] }
            .sheet(isPresented: Binding(get: { customLineID != nil }, set: { if !$0 { customLineID = nil } })) {
                if let id = customLineID, let line = lines.first(where: { $0.id == id }) {
                    CustomFoodForm(initialName: line.typed.name) { food in
                        replaceLine(id, with: food)
                        customLineID = nil
                    }
                }
            }
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
                let bread = unique(matches("bread white commercial") + matches("bread"))
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
        func search(_ terms: [String], limit: Int = 18) -> [FoodItem] {
            let search = terms.joined(separator: " ")
            let personal = (saved.compactMap(\.item) + recipes.map(\.asFood)).filter { food in
                let title = MealText.searchTerms(food.name + " " + (food.brand ?? ""))
                return terms.allSatisfy(title.contains)
            }
            let menu = store.restaurants?.search(search).map { $0.item.food(chain: $0.chain) } ?? []
            let general = store.genericFoods?.search(search, limit: limit) ?? []
            let catalogue = store.nutritionCatalogue?.search(search) ?? []
            return unique(personal + catalogue + menu + general)
        }
        var found = search(words)
        if found.isEmpty {
            // People naturally add detail such as “diced”, “spread on both slices”
            // or a cooking method. Fall back to the most useful food words rather
            // than making them retype a simpler version.
            let filler: Set<String> = ["and", "with", "on", "both", "the", "of", "a", "an", "spread", "diced", "sliced", "cooked"]
            let anchors = Array(Set(words.filter { $0.count > 2 && !filler.contains($0) })).sorted {
                $0.count == $1.count ? $0 < $1 : $0.count > $1.count
            }
            found = unique(anchors.flatMap { search([$0], limit: 8) })
        }
        var general = found
        if query == "egg", let foods = store.genericFoods {
            let common = foods.search("egg chicken whole", limit: 20).filter { food in
                let name = food.name.lowercased()
                return name.hasPrefix("egg, chicken, whole,") && !name.contains("raw")
            }
            general = unique(common + general)
        }
        var coffee: [FoodItem] = []
        if let style = CoffeeStyle.allCases.first(where: { $0.label.lowercased() == query }),
           let foods = store.genericFoods, let built = CoffeeBuilder.build(CoffeeOrder(style: style), foods: foods) {
            coffee = [built.item]
        }
        return unique(coffee + general)
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

    private func replaceLine(_ id: UUID, with food: FoodItem) {
        guard let index = lines.firstIndex(where: { $0.id == id }) else { return }
        lines[index].options = [food]
        lines[index].selectedID = food.id
        if let measure = food.defaultQuantityMeasure {
            lines[index].measure = measure
            lines[index].quantity = 1
        } else {
            lines[index].measure = nil
            lines[index].quantity = food.servingGrams ?? 100
        }
    }
}
