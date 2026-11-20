import SwiftUI
import SteadyCore

/// Build a home coffee (capsule, milk, sugar) from AUSNUT values, then log it like any food.
struct CoffeeBuilderView: View {
    let onBuilt: (FoodItem) -> Void
    @Environment(ContentStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("lastCoffeeOrder") private var lastOrder = ""
    @State private var order = CoffeeOrder(style: .flatWhite)
    @State private var loaded = false

    var body: some View {
        let built = store.genericFoods.flatMap { CoffeeBuilder.build(order, foods: $0) }
        NavigationStack {
            Form {
                Section("Style") {
                    Picker("Style", selection: Binding(get: { order.style }, set: { choose($0) })) {
                        ForEach(CoffeeStyle.allCases) { Text($0.label).tag($0) }
                    }
                    .accessibilityIdentifier("coffeeStyle")
                }
                Section {
                    TextField("Capsule name (optional)", text: Binding(
                        get: { order.capsuleName ?? "" },
                        set: { order.capsuleName = String($0.prefix(60)) }
                    ))
                    .accessibilityIdentifier("coffeeCapsule")
                    Stepper(value: $order.brewMl, in: 20...600, step: 10) {
                        LabeledContent("Coffee per capsule", value: "\(NumberText.format(order.brewMl)) mL")
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(CoffeeOrder.vertuoSizes) { s in
                                Button("\(s.label) \(NumberText.format(s.ml))") { order.brewMl = s.ml }
                                    .font(.footnote.weight(.semibold)).buttonStyle(.bordered)
                                    .tint(order.brewMl == s.ml ? Color.emerald : Color.inkMuted)
                            }
                        }
                    }
                    Stepper("Capsules or shots: \(order.capsules)", value: $order.capsules, in: 1...4)
                } header: { Text("Coffee") } footer: {
                    Text("Quick picks are Vertuo's nominal cup sizes in mL.")
                }
                Section("Milk") {
                    Picker("Milk", selection: $order.milk) {
                        ForEach(CoffeeMilk.allCases) { Text($0.label).tag($0) }
                    }
                    if order.milk != .noMilk {
                        Stepper(value: $order.milkMl, in: 0...500, step: 10) {
                            LabeledContent("Milk", value: "\(NumberText.format(order.milkMl)) mL")
                        }
                        .accessibilityIdentifier("milkStepper")
                    }
                }
                Section {
                    Stepper(value: $order.sugarTsp, in: 0...6, step: 0.5) {
                        LabeledContent("Sugar", value: order.sugarTsp == 0 ? "None" : "\(NumberText.format(order.sugarTsp)) tsp")
                    }
                } header: { Text("Sugar") } footer: {
                    Text("Level 5 mL teaspoons of white sugar. For a flavoured syrup, scan its barcode or add it from the label as its own food.")
                }
                if let built {
                    Section("This cup") {
                        HStack(spacing: 0) {
                            stat("\(Int(built.macros.kcal.rounded()))", "kcal")
                            stat(NumberText.format((built.macros.protein * 10).rounded() / 10), "protein")
                            stat(NumberText.format((built.macros.carbs * 10).rounded() / 10), "carbs")
                            stat(NumberText.format((built.macros.fat * 10).rounded() / 10), "fat")
                        }
                        ForEach(built.parts, id: \.name) { p in
                            LabeledContent(p.name, value: "\(Int(p.grams.rounded())) g · \(Int(p.macros.kcal.rounded())) kcal")
                                .font(.footnote)
                        }
                    }
                    Section {
                        Text("Values from AUSNUT 2023 (© Food Standards Australia New Zealand, CC BY 4.0): espresso or long black for the coffee, the matching milk, and white sugar. Volumes are converted to grams with each food's published density. Capsule names label your recipe. Coffee nutrition uses AUSNUT’s generic estimate.")
                            .font(.caption2).foregroundStyle(Color.inkMuted)
                    }
                } else {
                    Section { Text("The food database is still loading.").font(.footnote).foregroundStyle(Color.inkMuted) }
                }
            }
            .themedList()
            .navigationTitle("Coffee")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Next") {
                        guard let built else { return }
                        if let data = try? JSONEncoder().encode(order) { lastOrder = String(decoding: data, as: UTF8.self) }
                        onBuilt(built.item)
                    }
                    .fontWeight(.semibold).disabled(built == nil)
                    .accessibilityIdentifier("coffeeNext")
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let o = try? JSONDecoder().decode(CoffeeOrder.self, from: Data(lastOrder.utf8)) { order = o }
            }
        }
    }

    /// A new style resets the amounts to that style's starting point, keeping the milk type.
    private func choose(_ style: CoffeeStyle) {
        let milk = order.milk == .noMilk ? CoffeeMilk.fullCream : order.milk
        order = CoffeeOrder(style: style, capsules: order.capsules, milk: milk, sugarTsp: order.sugarTsp, capsuleName: order.capsuleName)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(Color.ink)
            Text(label).font(.caption).foregroundStyle(Color.inkMuted)
        }
        .frame(maxWidth: .infinity)
    }
}
