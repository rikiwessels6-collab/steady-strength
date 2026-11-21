import SwiftUI
import SwiftData
import SteadyCore

/// Create or edit a recipe: weigh in the raw ingredients, say how many servings it makes, optionally the cooked weight.
struct RecipeEditor: View {
    var editing: Recipe? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var servings: Double = 4
    @State private var cookedWeight: Double?
    @State private var ingredients: [RecipeIngredient] = []
    @State private var adding = false
    @State private var loaded = false

    private var totals: Macros { RecipeMath.totals(ingredients) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, for example Bolognese", text: $name)
                        .accessibilityIdentifier("recipeName")
                    Stepper(value: $servings, in: 1...24, step: 1) {
                        LabeledContent("Makes", value: "\(NumberText.format(servings)) servings")
                    }
                    HStack {
                        Text("Cooked weight (g, optional)")
                        TextField("0", value: $cookedWeight, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text("Weigh the finished dish if you can: cooking adds or loses water, so it makes logging by weight accurate.")
                }
                Section {
                    ForEach(ingredients) { i in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(i.name).lineLimit(2)
                                Text("\(NumberText.format(i.grams)) g").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(Int(i.kcal.rounded())) kcal").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { ingredients.remove(atOffsets: $0) }
                    Button { adding = true } label: { Label("Add ingredient", systemImage: "plus") }
                        .accessibilityIdentifier("addIngredient")
                } header: { Text("Ingredients, weighed raw") }
                if !ingredients.isEmpty {
                    Section("Per serving") {
                        let s = max(servings, 1)
                        LabeledContent("Calories", value: "\(Int((totals.kcal / s).rounded())) kcal")
                        LabeledContent("Protein", value: "\(Int((totals.protein / s).rounded())) g")
                        LabeledContent("Carbs", value: "\(Int((totals.carbs / s).rounded())) g")
                        LabeledContent("Fat", value: "\(Int((totals.fat / s).rounded())) g")
                    }
                }
            }
            .themedList()
            .navigationTitle(editing == nil ? "New recipe" : "Edit recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || ingredients.isEmpty)
                        .accessibilityIdentifier("saveRecipe")
                }
            }
            .sheet(isPresented: $adding) { IngredientPicker { ingredients.append($0) } }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let r = editing {
                    name = r.name; servings = r.servings; cookedWeight = r.cookedWeightGrams; ingredients = r.ingredients
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cooked = (cookedWeight ?? 0) > 0 ? cookedWeight : nil
        if let r = editing {
            r.name = trimmed; r.servings = servings; r.cookedWeightGrams = cooked; r.ingredients = ingredients
        } else {
            context.insert(Recipe(name: trimmed, ingredients: ingredients, servings: servings, cookedWeightGrams: cooked))
        }
        try? context.save()
        dismiss()
    }
}

/// Find an ingredient in your saved foods, online, or by barcode, then enter how much went in.
struct IngredientPicker: View {
    let onAdd: (RecipeIngredient) -> Void
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SavedFood.lastUsed, order: .reverse) private var saved: [SavedFood]
    @State private var query = ""
    @State private var online: [FoodItem] = []
    @State private var searching = false
    @State private var message: String?
    @State private var scanning = false
    @State private var chosen: FoodItem?
    @State private var grams: Double?

    private var local: [FoodItem] {
        let items = saved.compactMap(\.item)
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? Array(items.prefix(20)) : items.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { scanning = true } label: { Label("Scan a barcode", systemImage: "barcode.viewfinder") }
                    if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button { Task { await searchOnline() } } label: { Label("Search online for \"\(query)\"", systemImage: "magnifyingglass") }
                    }
                    if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }
                if !local.isEmpty {
                    Section("Your foods") { ForEach(local) { row($0) } }
                }
                if !online.isEmpty {
                    Section("Online") { ForEach(online) { row($0) } }
                }
            }
            .themedList()
            .overlay { if searching { ProgressView() } }
            .searchable(text: $query, prompt: "Search ingredients")
            .onSubmit(of: .search) { Task { await searchOnline() } }
            .navigationTitle("Add ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .fullScreenCover(isPresented: $scanning) {
                BarcodeScanner { code in
                    scanning = false
                    Task { await lookup(code) }
                } onCancel: { scanning = false }
            }
            .alert("How much went in?", isPresented: Binding(get: { chosen != nil }, set: { if !$0 { chosen = nil } })) {
                TextField("Grams", value: $grams, format: .number).keyboardType(.decimalPad)
                Button("Add") {
                    if let item = chosen, let g = grams, g > 0 {
                        onAdd(RecipeIngredient(food: item, grams: g))
                        dismiss()
                    }
                    chosen = nil
                }
                Button("Cancel", role: .cancel) { chosen = nil }
            } message: {
                Text(chosen.map { "\($0.name), raw weight in grams." } ?? "")
            }
        }
    }

    private func row(_ item: FoodItem) -> some View {
        Button { grams = item.servingGrams ?? 100; chosen = item } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).foregroundStyle(Color.ink).lineLimit(2)
                    if let b = item.brand { Text(b).font(.caption).foregroundStyle(Color.inkMuted) }
                }
                Spacer()
                Text(item.energyLabel).font(.caption.monospacedDigit()).foregroundStyle(Color.inkMuted)
            }
        }
    }

    private func searchOnline() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searching = true; message = nil
        defer { searching = false }
        do {
            online = try await FoodService.search(q)
            if online.isEmpty { message = "Nothing found online. Try fewer words, or create the food first." }
        } catch {
            message = "Couldn't reach the food database. Check your connection."
        }
    }

    private func lookup(_ code: String) async {
        if let hit = saved.first(where: { $0.foodId == code })?.item { grams = hit.servingGrams ?? 100; chosen = hit; return }
        searching = true; defer { searching = false }
        do {
            if let item = try await FoodService.lookup(barcode: code) { grams = item.servingGrams ?? 100; chosen = item }
            else { message = "Barcode \(code) isn't in the food database. Create it as a food first, then add it here." }
        } catch {
            message = "Couldn't look up that barcode. Check your connection."
        }
    }
}

/// Log a portion of a recipe, by servings or by weight.
struct RecipePortionSheet: View {
    let recipe: Recipe
    let meal: MealSlot
    let day: Date
    let onDone: (FoodDiaryDraft) -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var byWeight = false
    @State private var servings: Double = 1
    @State private var grams: Double = 0
    @State private var editing = false
    @State private var loaded = false

    private var portionGrams: Double {
        byWeight ? grams : RecipeMath.grams(servings: servings, servingsInRecipe: recipe.servings, totalWeight: recipe.totalWeight)
    }

    var body: some View {
        let food = recipe.asFood
        let m = food.macros(grams: portionGrams)
        NavigationStack {
            Form {
                Section {
                    Picker("Portion", selection: $byWeight) {
                        Text("Servings").tag(false)
                        Text("Weight").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if byWeight {
                        HStack {
                            Text("Grams")
                            TextField("0", value: $grams, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        }
                    } else {
                        Stepper(value: $servings, in: 0.25...12, step: 0.25) {
                            LabeledContent("Servings", value: NumberText.format(servings))
                        }
                    }
                } footer: {
                    Text("The recipe makes \(NumberText.format(recipe.servings)) servings, \(Int(recipe.totalWeight.rounded())) g in all.")
                }
                Section("This portion") {
                    LabeledContent("Calories", value: "\(Int(m.kcal.rounded())) kcal")
                    LabeledContent("Protein", value: "\(Int(m.protein.rounded())) g")
                    LabeledContent("Carbs", value: "\(Int(m.carbs.rounded())) g")
                    LabeledContent("Fat", value: "\(Int(m.fat.rounded())) g")
                }
                Section {
                    Button("Edit recipe") { editing = true }
                }
            }
            .themedList()
            .navigationTitle(recipe.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let entry = FoodEntry(item: food, grams: portionGrams, meal: meal, source: .saved,
                                              eatenAt: FoodTiming.defaultEatenAt(for: day))
                        onDone(FoodDiaryDraft(entry: entry, recipe: recipe))
                        dismiss()
                    }
                    .disabled(portionGrams <= 0)
                    .accessibilityIdentifier("addRecipePortion")
                }
            }
            .sheet(isPresented: $editing) { RecipeEditor(editing: recipe) }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                let standard = recipe.totalWeight / max(recipe.servings, 1)
                if let last = try? FoodDiary.lastAmount(for: food, in: context) {
                    let count = (last / standard * 4).rounded() / 4
                    if standard > 0, (0.25...12).contains(count), abs(count * standard - last) < 0.01 {
                        servings = count
                    } else {
                        byWeight = true
                    }
                    grams = last
                } else {
                    grams = standard.rounded()
                }
            }
        }
    }
}
