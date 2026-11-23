import SwiftUI
import SwiftData
import VisionKit
import PhotosUI
import SteadyCore

// MARK: - Open Food Facts

enum FoodService {
    static func get(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url, timeoutInterval: 12)
        req.setValue(OpenFoodFacts.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if (resp as? HTTPURLResponse)?.statusCode == 404 { throw URLError(.resourceUnavailable) }
        guard let response = resp as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw URLError(.badServerResponse) }
        return data
    }

    static func lookup(barcode: String) async throws -> FoodItem? {
        guard let url = OpenFoodFacts.productURL(barcode: barcode) else { return nil }
        do { return try OpenFoodFacts.parseProduct(try await get(url)) }
        catch let error as URLError where error.code == .resourceUnavailable { return nil }
    }

    static func search(_ query: String, retailer: OpenFoodFacts.Retailer? = nil) async throws -> [FoodItem] {
        guard let url = OpenFoodFacts.searchURL(query, retailer: retailer) else { return [] }
        return try OpenFoodFacts.parseSearch(try await get(url), retailer: retailer)
    }
}

extension Calendar {
    func dayRange(_ date: Date) -> (Date, Date) {
        let start = startOfDay(for: date)
        return (start, self.date(byAdding: .day, value: 1, to: start) ?? start)
    }
}

func totals(_ entries: [FoodEntry]) -> Macros { entries.reduce(Macros()) { $0 + $1.macros } }

// MARK: - Food tab

struct FoodView: View {
    @Environment(\.modelContext) private var context
    @Query private var plans: [NutritionPlan]
    @Query(sort: \FoodEntry.eatenAt) private var entries: [FoodEntry]
    @State private var day = Date.now
    @Environment(FoodDraftNavigation.self) private var foodNavigation
    @State private var addingTo: FoodDraftNavigation.Request?
    @State private var editing: FoodEntry?
    @State private var savingMeal: MealSlot?
    @State private var mealName = ""
    @State private var undo: DiaryUndo?
    @State private var saveError = false

    private enum DiaryUndo {
        case added([FoodEntry])
        case deleted(FoodEntry)
    }

    private var dayEntries: [FoodEntry] {
        let (s, e) = Calendar.current.dayRange(day)
        return entries.filter { $0.eatenAt >= s && $0.eatenAt < e }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    dayHeader
                    if dayEntries.isEmpty, let prev = previousDay { copyDayButton(prev) }
                    if let plan = plans.first { FoodCard(plan: plan, totals: totals(dayEntries), day: day) }
                    NutritionDetailCard(totals: totals(dayEntries))
                    ForEach(MealSlot.allCases) { meal in mealCard(meal) }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color.night.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let undo {
                    let actions = HStack {
                        Button("Undo") { undoChange(undo) }
                            .fontWeight(.semibold).frame(minHeight: 44)
                            .accessibilityIdentifier("undoFoodChange")
                        Button { self.undo = nil } label: {
                            Image(systemName: "xmark").frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityLabel("Dismiss undo")
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            Text(undoMessage(undo))
                            Spacer()
                            actions
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(undoMessage(undo))
                            actions
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.subheadline)
                    .padding()
                    .background(.regularMaterial)
                }
            }
            .sheet(item: $addingTo) { request in
                AddFoodSheet(destination: request.meal,
                             draft: foodNavigation.draft(for: request.meal, in: context), scanOnOpen: request.scan) {
                    undo = .added($0)
                }
            }
            .onAppear {
                openFromNotification()
                openFromToday()
            }
            .onChange(of: foodNavigation.request?.id) { _, _ in openFromToday() }
            .onChange(of: NotificationRouter.shared.openMeal) { _, _ in openFromNotification() }
            .onChange(of: entries.count) { _, _ in Task { await MealReminderService.refresh(context) } }
            .sheet(item: $editing) { entry in
                EditEntrySheet(entry: entry,
                               food: (try? FoodDiary.savedFood(entry.foodId, in: context))?.item,
                               onSave: { try FoodDiary.commit(in: context) }, onDelete: {
                    try deleteEntry(entry)
                })
            }
            .alert("Couldn’t update the diary", isPresented: $saveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your diary was left as it was. Try again.")
            }
            .alert("Save as a meal", isPresented: Binding(get: { savingMeal != nil }, set: { if !$0 { savingMeal = nil } })) {
                TextField("Name, for example Usual breakfast", text: $mealName)
                Button("Save") { saveMeal() }
                Button("Cancel", role: .cancel) { savingMeal = nil }
            } message: {
                Text("Keeps these foods and amounts together so you can add them all in one tap from Add, then Meals.")
            }
        }
    }

    private func undoMessage(_ action: DiaryUndo) -> String {
        switch action {
        case .added(let entries): entries.count == 1 ? "Food added" : "\(entries.count) foods added"
        case .deleted: "Food deleted"
        }
    }

    private func undoChange(_ action: DiaryUndo) {
        do {
            switch action {
            case .added(let entries): try FoodDiary.delete(entries, in: context)
            case .deleted(let snapshot): try FoodDiary.restore(snapshot, in: context)
            }
            undo = nil
        } catch { saveError = true }
    }

    private func deleteEntry(_ entry: FoodEntry) throws {
        let snapshot = FoodDiary.copyForUndo(entry)
        try FoodDiary.delete([entry], in: context)
        undo = .deleted(snapshot)
    }

    private func addEntries(_ entries: [FoodEntry]) {
        do { undo = .added(try FoodDiary.save(entries.map { FoodDiaryDraft(entry: $0) }, in: context)) }
        catch { saveError = true }
    }

    /// A tapped "Log lunch?" nudge: show today and open Add for that meal.
    private func openFromNotification() {
        guard let meal = NotificationRouter.shared.openMeal else { return }
        NotificationRouter.shared.openMeal = nil
        day = .now
        editing = nil
        addingTo = .init(meal: .init(slot: meal))
    }

    private func openFromToday() {
        guard let request = foodNavigation.request else { return }
        foodNavigation.request = nil
        day = request.meal.day
        editing = nil
        addingTo = request
    }

    private func saveMeal() {
        guard let meal = savingMeal else { return }
        let items = dayEntries.filter { $0.meal == meal }.map { MealItem($0) }
        let name = mealName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !items.isEmpty else { return }
        context.insert(SavedMeal(name: name.isEmpty ? meal.label : name, items: items))
        try? context.save()
        savingMeal = nil
        mealName = ""
    }

    private var dayHeader: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Calendar.current.isDateInToday(day) ? "TODAY" : day.formatted(.dateTime.weekday(.wide)).uppercased())
                    .font(.caption.weight(.semibold)).tracking(1.6).foregroundStyle(Color.gold)
                Text(day.formatted(.dateTime.day().month(.wide))).font(.largeTitle.weight(.bold)).foregroundStyle(Color.ink)
            }
            Spacer()
            HStack(spacing: 8) {
                dayButton("chevron.left", -1)
                dayButton("chevron.right", 1).disabled(Calendar.current.isDateInToday(day))
            }
        }
        .padding(.top, 8)
    }

    private func dayButton(_ icon: String, _ step: Int) -> some View {
        Button {
            day = Calendar.current.date(byAdding: .day, value: step, to: day) ?? day
        } label: {
            Image(systemName: icon).font(.headline).frame(width: 40, height: 40)
                .background(Color.surface, in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.ink)
        .accessibilityLabel(step < 0 ? "Previous day" : "Next day")
    }

    /// The most recent earlier day that has something logged for this meal.
    private func previousMeal(_ meal: MealSlot) -> (date: Date, items: [FoodEntry])? {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: day)
        let earlier = entries.filter { $0.meal == meal && $0.eatenAt < startOfDay }
        guard let latest = earlier.map(\.eatenAt).max() else { return nil }
        let (s, e) = cal.dayRange(latest)
        return (s, earlier.filter { $0.eatenAt >= s && $0.eatenAt < e })
    }

    /// Copies a past meal onto the day being viewed, at the same times of day (never in the future).
    private func repeatMeal(_ meal: MealSlot) {
        guard let prev = previousMeal(meal) else { return }
        addEntries(prev.items.map {
            FoodEntry(copying: $0, eatenAt: FoodRepeat.time(of: $0.eatenAt, on: day), meal: meal)
        })
    }

    /// The most recent earlier day with anything logged, to copy a whole day in one tap.
    private var previousDay: (date: Date, items: [FoodEntry])? {
        guard let start = FoodRepeat.previousDay(entries.map(\.eatenAt), before: day) else { return nil }
        let (s, e) = Calendar.current.dayRange(start)
        return (s, entries.filter { $0.eatenAt >= s && $0.eatenAt < e })
    }

    /// Copies every food from that day onto the day being viewed, in the same meals and at the same times.
    private func repeatDay() {
        guard let prev = previousDay else { return }
        addEntries(prev.items.map {
            FoodEntry(copying: $0, eatenAt: FoodRepeat.time(of: $0.eatenAt, on: day), meal: $0.meal)
        })
    }

    private func copyDayButton(_ prev: (date: Date, items: [FoodEntry])) -> some View {
        Button { repeatDay() } label: {
            Label("Copy all of \(repeatLabel(prev.date, prev.items))", systemImage: "doc.on.doc")
                .font(.subheadline.weight(.semibold)).multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered).tint(Color.gold)
        .accessibilityIdentifier("copyDay")
    }

    /// "7:30 am · 150 g · P 20 C 30 F 5". Quick adds have no real weight, so the grams are left out.
    private func detail(_ e: FoodEntry) -> String {
        let time = e.eatenAt.formatted(date: .omitted, time: .shortened)
        let grams: String
        if e.foodId.hasPrefix("quick-") {
            grams = ""
        } else if e.foodId.hasPrefix(FoodItem.perServePrefix) {
            let serves = NumberText.format(e.grams / 100)
            grams = " · \(serves) serve\(e.grams == 100 ? "" : "s")"
        } else {
            grams = " · \(Int(e.grams.rounded())) \(e.portionUnit)"
        }
        return "\(time)\(grams) · P \(Int(e.protein.rounded())) C \(Int(e.carbs.rounded())) F \(Int(e.fat.rounded()))"
    }

    /// Foods usually eaten at this meal over the last 30 days that aren't logged in it yet.
    private func usualFoods(_ meal: MealSlot, logged: [FoodEntry]) -> [UsualFood] {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: day)
        let since = cal.date(byAdding: .day, value: -30, to: startOfDay) ?? startOfDay
        let history = entries.filter { $0.meal == meal && $0.eatenAt >= since && $0.eatenAt < startOfDay && !$0.foodId.hasPrefix("quick-") }
            .map { FoodHabits.Eaten(foodId: $0.foodId, name: $0.name, grams: $0.grams, date: $0.eatenAt) }
        return FoodHabits.usual(history, excluding: Set(logged.map(\.foodId)))
    }

    /// Logs a usual food with the amount used last time.
    private func logUsual(_ u: UsualFood, meal: MealSlot) {
        guard let source = entries.last(where: { $0.foodId == u.foodId && $0.meal == meal }) else { return }
        addEntries([FoodEntry(copying: source, eatenAt: FoodTiming.defaultEatenAt(for: day), meal: meal)])
    }

    private func repeatLabel(_ date: Date, _ items: [FoodEntry]) -> String {
        let when = Calendar.current.isDateInYesterday(date)
            ? "yesterday" : date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        let kcal = Int(items.reduce(0.0) { $0 + $1.kcal }.rounded())
        let count = items.count == 1 ? "1 food" : "\(items.count) foods"
        return "\(when) (\(count), \(kcal) kcal)"
    }

    private func mealCard(_ meal: MealSlot) -> some View {
        let items = dayEntries.filter { $0.meal == meal }
        let kcal = items.reduce(0) { $0 + $1.kcal }
        let prev = previousMeal(meal)
        let prevLabel = prev.map { repeatLabel($0.date, $0.items) }
        let usual = usualFoods(meal, logged: items)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(meal.label.uppercased()).font(.caption.weight(.semibold)).tracking(1.6).foregroundStyle(Color.gold)
                Spacer()
                if kcal > 0 { Text("\(Int(kcal.rounded())) kcal").font(.subheadline.monospacedDigit()).foregroundStyle(Color.inkMuted) }
                if items.count >= 2 {
                    Button { mealName = ""; savingMeal = meal } label: {
                        Image(systemName: "bookmark").font(.subheadline.weight(.semibold)).foregroundStyle(Color.gold)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Save \(meal.label) as a meal")
                    .accessibilityIdentifier("saveMeal-\(meal.rawValue)")
                }
                Button { addingTo = .init(meal: .init(slot: meal, day: day)) } label: {
                    Image(systemName: "plus").font(.subheadline.weight(.bold)).foregroundStyle(Color.night)
                        .frame(width: 30, height: 30).background(LinearGradient.brand, in: Circle())
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add to \(meal.label)")
                .accessibilityIdentifier("add-\(meal.rawValue)")
            }
            if items.isEmpty {
                Text("Nothing logged").font(.subheadline).foregroundStyle(Color.inkMuted.opacity(0.7))
                if let prevLabel {
                    Button { repeatMeal(meal) } label: {
                        Label("Repeat \(prevLabel)", systemImage: "arrow.counterclockwise")
                            .font(.footnote.weight(.semibold)).multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.bordered).tint(Color.gold)
                    .accessibilityIdentifier("repeat-\(meal.rawValue)")
                }
            }
            if !usual.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("YOUR USUAL · ONE TAP TO ADD").font(.caption2.weight(.semibold)).tracking(1.2)
                        .foregroundStyle(Color.inkMuted.opacity(0.8))
                    ForEach(usual) { u in
                        Button { logUsual(u, meal: meal) } label: {
                            Label("\(u.name) · \(Int(u.grams.rounded())) g", systemImage: "plus.circle.fill")
                                .font(.footnote.weight(.semibold)).lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered).tint(Color.gold)
                        .accessibilityIdentifier("usual-\(meal.rawValue)-\(u.foodId)")
                    }
                }
            }
            ForEach(items) { e in
                Button { editing = e } label: {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.name).font(.body.weight(.medium)).foregroundStyle(Color.ink).lineLimit(1)
                            Text(detail(e))
                                .font(.caption.monospacedDigit()).foregroundStyle(Color.inkMuted)
                        }
                        Spacer()
                        Text("\(Int(e.kcal.rounded()))").font(.body.weight(.semibold).monospacedDigit()).foregroundStyle(Color.ink)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .card()
    }
}

// MARK: - Adding food

struct AddFoodSheet: View {
    let destination: FoodDraftNavigation.Meal
    private var meal: MealSlot { destination.slot }
    private var day: Date { destination.day }
    @Binding var draft: [FoodDiaryDraft]
    var scanOnOpen = false
    let onSaved: ([FoodEntry]) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedFood.lastUsed, order: .reverse) private var saved: [SavedFood]
    @Query(sort: \SavedMeal.lastUsed, order: .reverse) private var meals: [SavedMeal]
    @Query(sort: \Recipe.lastUsed, order: .reverse) private var recipes: [Recipe]
    @State private var newRecipe = false
    @State private var loggingRecipe: Recipe?
    @State private var quickAdding = false
    @State private var browsingRestaurants = false
    @State private var makingCoffee = false
    @Environment(ContentStore.self) private var store
    @Environment(FoodDraftNavigation.self) private var foodNavigation
    @State private var query = ""
    @State private var results: [FoodItem] = []
    @State private var searching = false
    @State private var message: String?
    @State private var scanning = false
    @State private var scannedCode: String?
    @State private var lookingUp = false
    @State private var retailer: OpenFoodFacts.Retailer?
    @State private var picked: (item: FoodItem, source: FoodSource)?
    @State private var creating = false
    @State private var newBarcode: String?
    @State private var reviewItem: FoodItem?
    @State private var reviewNote: String?
    @State private var reviewedFood: FoodItem?
    @State private var plate = false
    @State private var typingMeal = false
    @State private var tab = 0
    @State private var opened = false
    @State private var editingLine: FoodDiaryDraft?
    @State private var confirmDiscard = false
    @State private var saveError = false

    var body: some View {
        NavigationStack {
            foodList
        }
        .interactiveDismissDisabled(!draft.isEmpty)
        .task {
            guard scanOnOpen, !opened else { return }
            opened = true
            scanning = true
        }
    }

    private var foodList: AnyView {
        AnyView(presentationLayer)
    }

    private var contentLayer: AnyView {
        AnyView(
        List {
            listRows
        }
        .themedList()
        .overlay { if searching || lookingUp { ProgressView().controlSize(.large) } }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search foods")
        .onSubmit(of: .search) { Task { await runSearch() } }
        .onChange(of: query) { _, q in
            message = nil
            results = []
            guard retailer == nil else { return }
            // Your own foods match as you type; Search adds the wider database.
            let text = q.trimmingCharacters(in: .whitespaces)
            if text.count >= 2 {
                let mine = saved.compactMap(\.item).filter { $0.name.localizedCaseInsensitiveContains(text) }
                let menus = (store.restaurants?.search(text) ?? []).map { $0.item.food(chain: $0.chain) }
                let generic = store.genericFoods?.search(text) ?? []
                let catalogue = store.nutritionCatalogue?.search(text) ?? []
                let others = (menus + catalogue + generic).filter { m in !mine.contains { $0.id == m.id } }
                results = FoodRanking.rank(mine, query: text) + FoodRanking.rank(others, query: text)
            }
        }
        .task { await store.refreshNutritionCatalogue() }
        .onChange(of: retailer) { _, _ in
            results = []
            message = nil
        }
        )
    }

    private var navigationLayer: AnyView {
        AnyView(
        contentLayer
        .navigationTitle("Add to \(meal.label)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    if draft.isEmpty { dismiss() } else { confirmDiscard = true }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if !draft.isEmpty && !textSize.isAccessibilitySize {
                    Button("Save meal", action: saveDraft)
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("saveDiaryMeal")
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if textSize.isAccessibilitySize && !draft.isEmpty {
                Button(action: saveDraft) {
                    Text("Save meal").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("saveDiaryMeal")
                .padding()
                .background(.regularMaterial)
            }
        }
        .confirmationDialog("Leave this meal?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Continue later") {
                do { try foodNavigation.close(destination, in: context); dismiss() }
                catch { foodNavigation.storageError = true }
            }
            Button("Discard", role: .destructive) {
                do { try foodNavigation.discard(destination, in: context); dismiss() }
                catch { foodNavigation.storageError = true }
            }
            Button("Keep editing", role: .cancel) {}
        }
        .alert("Couldn’t keep the meal draft", isPresented: Binding(
            get: { foodNavigation.storageError },
            set: { foodNavigation.storageError = $0 }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Keep the app open and try again. You can still save the meal to your diary.")
        }
        .alert("Couldn’t save the meal", isPresented: $saveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your meal is still here. Try saving again.")
        }
        )
    }

    private var presentationLayer: AnyView {
        AnyView(
        navigationLayer
        .sheet(item: $editingLine) { line in
            EditEntrySheet(entry: line.entry, food: line.food, onSave: {
                if let index = draft.firstIndex(where: { $0.id == line.id }) { draft[index] = line }
            }, onDelete: {
                draft.removeAll { $0.id == line.id }
            })
        }
        .fullScreenCover(isPresented: $scanning, onDismiss: {
            guard let code = scannedCode else { return }
            scannedCode = nil
            Task { await lookup(code) }
        }) {
            BarcodeScanner { code in
                scannedCode = code
                scanning = false
            } onCancel: { scanning = false }
        }
        .sheet(isPresented: Binding(get: { picked != nil }, set: { if !$0 { picked = nil } })) {
            if let p = picked {
                PortionSheet(item: p.item, source: p.source, meal: meal, day: day,
                             provenance: store.nutritionCatalogue?.entries.first { $0.item.id == p.item.id }) { line in
                    draft.append(line)
                }
            }
        }
        .sheet(isPresented: $typingMeal) {
            MealTextReviewSheet(meal: meal, day: day) { draft.append(contentsOf: $0) }
        }
        .sheet(isPresented: $plate) { PlateFlow(meal: meal, day: day) { draft.append(contentsOf: $0) } }
        .sheet(isPresented: $quickAdding) { QuickAddSheet(meal: meal, day: day) { draft.append($0) } }
        .sheet(isPresented: $browsingRestaurants) {
            RestaurantBrowser { item in
                browsingRestaurants = false
                picked = (item, .search)
            }
        }
        .sheet(isPresented: $makingCoffee) {
            CoffeeBuilderView { item in
                makingCoffee = false
                picked = (item, .manual)
            }
        }
        .sheet(isPresented: $newRecipe) { RecipeEditor() }
        .sheet(item: $loggingRecipe) { r in RecipePortionSheet(recipe: r, meal: meal, day: day) { draft.append($0) } }
        .sheet(isPresented: $creating, onDismiss: {
            guard let item = reviewedFood else { return }
            reviewedFood = nil
            picked = (item, item.barcode == nil ? .manual : .barcode)
        }) {
            CustomFoodForm(barcode: newBarcode, item: reviewItem, initialNote: reviewNote) { item in
                reviewedFood = try saveReviewedFood(item)
                creating = false
            }
        }
        )
    }

    private var listRows: AnyView {
        AnyView(Group {
            if !draft.isEmpty { draftSection }
            captureActions
            foodOptions
            searchOrLibrary
            dataAttribution
        })
    }

    private var captureActions: some View {
        Section {
            let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
            layout {
                actionButton("Scan barcode", "barcode.viewfinder") { scannedCode = nil; scanning = true }
                    .accessibilityIdentifier("scanBarcode")
                    .disabled(lookingUp)
                actionButton("Plate photo", "camera.viewfinder") { plate = true }
                    .accessibilityIdentifier("platePhoto")
                actionButton("Create food", "square.and.pencil") { startReview() }
                    .accessibilityIdentifier("createFood")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    private var foodOptions: some View {
        Section {
            Button { typingMeal = true } label: { Label("Type a meal", systemImage: "text.cursor") }
                .accessibilityIdentifier("typeMeal")
            Menu {
                Picker("Retailer", selection: $retailer) {
                    Text("All foods").tag(nil as OpenFoodFacts.Retailer?)
                    ForEach(OpenFoodFacts.Retailer.allCases) { store in
                        Text(store.rawValue).tag(Optional(store))
                    }
                }
            } label: {
                Label(retailer?.rawValue ?? "Filter by supermarket", systemImage: "cart")
            }
            .accessibilityIdentifier("supermarketFilter")
            if retailer != nil {
                Text("Enter a product name and tap Search. Store tags come from Open Food Facts and may be incomplete.")
                    .font(.footnote).foregroundStyle(Color.inkMuted)
            }
            Button { quickAdding = true } label: { Label("Quick add calories", systemImage: "bolt") }
                .accessibilityIdentifier("quickAdd")
            Button { browsingRestaurants = true } label: { Label("Restaurants and takeaway", systemImage: "takeoutbag.and.cup.and.straw") }
                .accessibilityIdentifier("restaurants")
            Button { makingCoffee = true } label: { Label("Coffee at home", systemImage: "cup.and.saucer") }
                .accessibilityIdentifier("coffee")
        }
    }

    @ViewBuilder private var searchOrLibrary: some View {
        if let message { Section { Text(message).font(.footnote).foregroundStyle(Color.inkMuted) } }
        if !results.isEmpty {
            Section("Results") { ForEach(results) { row($0, source: .search) } }
        } else {
            librarySection
        }
    }

    private var dataAttribution: some View {
        Section {
            Text("Product data from Open Food Facts (openfoodfacts.org), licensed under the ODbL. Generic foods from AUSNUT 2023, © Food Standards Australia New Zealand, used under Creative Commons Attribution 4.0.")
                .font(.caption2).foregroundStyle(Color.inkMuted)
        }
    }

    private var librarySection: some View {
        Section {
            Picker("Show", selection: $tab) {
                Text("Recent").tag(0); Text("Favourites").tag(1); Text("My foods").tag(2); Text("Meals").tag(3)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            if tab == 3 { savedMealsAndRecipes } else { savedFoods }
        }
    }

    @ViewBuilder private var savedMealsAndRecipes: some View {
        ForEach(meals) { m in
            Button { add(m) } label: { savedMealRow(m) }
                .accessibilityIdentifier("meal-\(m.name)")
        }
        .onDelete { offsets in
            for i in offsets { context.delete(meals[i]) }
            try? context.save()
        }
        if meals.isEmpty {
            Text("Log two or more foods in a meal, then tap the bookmark on that meal to save it here.")
                .font(.footnote).foregroundStyle(Color.inkMuted)
        }
        Text("RECIPES").font(.caption2.weight(.semibold)).tracking(1.2).foregroundStyle(Color.inkMuted)
            .listRowBackground(Color.clear)
        ForEach(recipes) { recipe in
            Button { loggingRecipe = recipe } label: { recipeRow(recipe) }
                .accessibilityIdentifier("recipe-\(recipe.name)")
        }
        .onDelete { offsets in
            for i in offsets { context.delete(recipes[i]) }
            try? context.save()
        }
        Button { newRecipe = true } label: { Label("New recipe", systemImage: "frying.pan") }
            .accessibilityIdentifier("newRecipe")
    }

    @ViewBuilder private var savedFoods: some View {
        ForEach(list) { savedFood in
            if let item = savedFood.item { row(item, source: savedFood.isCustom ? .saved : .recent) }
        }
        if list.isEmpty {
            Text(tab == 0 ? "Foods you log appear here." : tab == 1 ? "Tap the star on a food to keep it here." : "Foods you create appear here.")
                .font(.footnote).foregroundStyle(Color.inkMuted)
        }
    }

    private func savedMealRow(_ meal: SavedMeal) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.name).foregroundStyle(Color.ink).lineLimit(2)
                Text(meal.items.map(\.name).joined(separator: ", "))
                    .font(.caption).foregroundStyle(Color.inkMuted).lineLimit(2)
            }
            Spacer()
            Text("\(Int(meal.kcal.rounded())) kcal").font(.caption.monospacedDigit()).foregroundStyle(Color.inkMuted)
        }
    }

    private func recipeRow(_ recipe: Recipe) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.name).foregroundStyle(Color.ink).lineLimit(2)
                Text("Makes \(NumberText.format(recipe.servings)) · \(recipe.ingredients.count) ingredients")
                    .font(.caption).foregroundStyle(Color.inkMuted)
            }
            Spacer()
            Text("\(Int(recipe.kcalPerServing.rounded())) kcal/serve").font(.caption.monospacedDigit()).foregroundStyle(Color.inkMuted)
        }
    }

    private var draftSection: some View {
        let total = totals(draft.map(\.entry))
        return Section("This meal") {
            ForEach(draft) { line in
                Button { editingLine = line } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(line.entry.name)
                            if let detail = draftAmount(line.entry) {
                                Text(detail).font(.footnote).foregroundStyle(Color.inkMuted)
                            }
                        }
                        Spacer()
                        Text("\(Int(line.entry.kcal.rounded())) kcal").foregroundStyle(Color.inkMuted)
                    }
                }
            }
            .onDelete { draft.remove(atOffsets: $0) }
            LabeledContent("Total", value: "\(Int(total.kcal.rounded())) kcal")
                .fontWeight(.semibold)
            Text("Protein \(Int(total.protein.rounded())) g · Carbs \(Int(total.carbs.rounded())) g · Fat \(Int(total.fat.rounded())) g")
                .font(.footnote).foregroundStyle(Color.inkMuted)
        }
    }

    private func draftAmount(_ entry: FoodEntry) -> String? {
        guard entry.grams > 0, !entry.foodId.hasPrefix("quick-") else { return nil }
        if entry.foodId.hasPrefix(FoodItem.perServePrefix) {
            return "\(NumberText.format(entry.grams / 100)) \(entry.grams == 100 ? "serve" : "serves")"
        }
        return "\(NumberText.format(entry.grams)) \(entry.portionUnit)"
    }

    private func saveDraft() {
        guard !draft.isEmpty else { return }
        do {
            let entries = try foodNavigation.commit(destination, in: context)
            onSaved(entries)
            dismiss()
        } catch { saveError = true }
    }

    private func startReview(code: String? = nil, item: FoodItem? = nil, note: String? = nil) {
        newBarcode = code
        reviewItem = item
        reviewNote = note
        creating = true
    }

    private func savedBarcode(_ code: String) -> SavedFood? {
        let key = OpenFoodFacts.barcodeKey(code)
        return saved.first { record in
            guard let item = record.item else { return false }
            let barcode = item.barcode ?? record.foodId
            return barcode == code || (key != nil && OpenFoodFacts.barcodeKey(barcode) == key)
        }
    }

    private func saveReviewedFood(_ item: FoodItem) throws -> FoodItem {
        if let existing = item.barcode.flatMap(savedBarcode) {
            let oldData = existing.itemData
            let wasCustom = existing.isCustom
            var updated = item
            updated.id = existing.foodId
            existing.itemData = try JSONEncoder().encode(updated)
            existing.isCustom = true
            do { try context.save() }
            catch {
                existing.itemData = oldData
                existing.isCustom = wasCustom
                throw error
            }
            return updated
        } else {
            let record = SavedFood(item: item, isCustom: true)
            context.insert(record)
            do { try context.save() }
            catch {
                context.delete(record)
                throw error
            }
            return item
        }
    }

    /// Adds every food in a saved meal to this meal, now if the day is today, otherwise at midday.
    private func add(_ m: SavedMeal) {
        let when = FoodTiming.defaultEatenAt(for: day)
        draft.append(contentsOf: m.items.map {
            FoodDiaryDraft(entry: FoodEntry(mealItem: $0, eatenAt: when, meal: meal), savedMeal: m)
        })
    }

    private var list: [SavedFood] {
        switch tab {
        case 1: return saved.filter(\.isFavourite)
        case 2: return saved.filter(\.isCustom)
        default: return Array(saved.filter { $0.useCount > 0 }.prefix(25))
        }
    }

    private func actionButton(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.title2)
                Text(title).font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Color.ink)
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.hairline))
        }
        .buttonStyle(.plain)
    }

    private func row(_ item: FoodItem, source: FoodSource) -> some View {
        Button { picked = (item, source) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).foregroundStyle(Color.ink).lineLimit(2)
                    Text([item.brand, item.serveText].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(Color.inkMuted)
                }
                Spacer()
                Text(item.energyLabel).font(.caption.monospacedDigit()).foregroundStyle(Color.inkMuted)
            }
        }
    }

    private func runSearch() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, !searching else { return }
        let selectedRetailer = retailer
        let mine = saved.compactMap(\.item).filter { $0.name.localizedCaseInsensitiveContains(q) }
        let catalogue = store.nutritionCatalogue?.search(q) ?? []
        let others = (catalogue + (store.restaurants?.search(q) ?? []).map { $0.item.food(chain: $0.chain) } + (store.genericFoods?.search(q) ?? []))
            .filter { o in !mine.contains { $0.id == o.id } }
        let local = selectedRetailer == nil ? FoodRanking.rank(mine, query: q) + FoodRanking.rank(others, query: q) : []
        searching = true; message = nil
        defer { searching = false }
        do {
            let remote = try await FoodService.search(q, retailer: selectedRetailer)
            guard query.trimmingCharacters(in: .whitespaces) == q, selectedRetailer == retailer else { return }
            results = local + remote.filter { r in !local.contains { $0.id == r.id } }
            if results.isEmpty { message = "No matches. Try fewer words, or create the food." }
        } catch {
            guard query.trimmingCharacters(in: .whitespaces) == q, selectedRetailer == retailer else { return }
            results = local
            message = selectedRetailer == nil
                ? "Couldn't reach Open Food Facts. Showing matches stored on this phone."
                : "Couldn't reach Open Food Facts. Clear the supermarket filter to search offline."
        }
    }

    private func lookup(_ code: String) async {
        guard !lookingUp else { return }
        if let hit = savedBarcode(code)?.item { picked = (hit, .barcode); return }
        lookingUp = true
        defer { lookingUp = false }
        do {
            if let item = try await FoodService.lookup(barcode: code) {
                startReview(code: code, item: item, note: "Found in Open Food Facts. Check the values against the pack before saving.")
            } else {
                startReview(code: code, note: "No complete match. Take a photo of the nutrition panel or enter the values from the pack.")
            }
        } catch {
            startReview(code: code, note: "Lookup is unavailable. You can still use the nutrition panel and save this product offline.")
        }
    }

}

struct PortionSheet: View {
    let item: FoodItem
    let source: FoodSource
    let meal: MealSlot
    let day: Date
    var provenance: NutritionCatalogue.Entry? = nil
    let onDone: (FoodDiaryDraft) -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Query private var saved: [SavedFood]
    @State private var portion: FoodMeasure?
    @State private var quantity = "1"
    @State private var measuredAmount = ""
    @State private var favourite = false
    @State private var loaded = false
    @State private var remembered = false

    private var grams: Double? {
        let input = portion == nil ? measuredAmount : quantity
        let parts = input.components(separatedBy: locale.decimalSeparator ?? ".")
        guard parts.count <= 2, parts.allSatisfy({ $0.allSatisfy(\.isWholeNumber) }),
              let value = try? Double(input, format: .number.locale(locale), lenient: false) else { return nil }
        let amount = portion == nil ? value : portion?.amount(for: value)
        guard let amount, (0...100_000).contains(amount), amount > 0 else { return nil }
        return amount
    }

    var body: some View {
        let m = item.macros(grams: grams ?? 0)
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name).font(.title3.weight(.semibold)).foregroundStyle(Color.ink)
                        if let b = item.brand { Text(b).font(.subheadline).foregroundStyle(Color.inkMuted) }
                    }
                    HStack(spacing: 0) {
                        stat("\(Int(m.kcal.rounded()))", "kcal")
                        stat("\(Int(m.protein.rounded()))", "protein")
                        stat("\(Int(m.carbs.rounded()))", "carbs")
                        stat("\(Int(m.fat.rounded()))", "fat")
                    }
                }
                amountSection
                if let provenance {
                    Section("Nutrition source") {
                        Link("Open original source", destination: provenance.sourceURL)
                        Text("Checked \(provenance.checkedOn) · \(provenance.licence)")
                            .font(.footnote).foregroundStyle(Color.inkMuted)
                    }
                }
                Section { Toggle("Favourite", isOn: $favourite) }
            }
            .themedList()
            .navigationTitle("Add food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }.fontWeight(.semibold).disabled(grams == nil)
                        .accessibilityIdentifier("addFoodConfirm")
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            let format = FloatingPointFormatStyle<Double>.number.grouping(.never).precision(.fractionLength(0...8)).locale(locale)
            if let last = try? FoodDiary.lastAmount(for: item, in: context) {
                remembered = true
                portion = item.measure(forLoggedAmount: last)
                if let portion { quantity = (last / portion.grams).formatted(format) }
                measuredAmount = last.formatted(format)
            } else {
                portion = item.defaultQuantityMeasure
                measuredAmount = (portion?.grams ?? item.defaultGrams).formatted(format)
            }
            favourite = saved.first { $0.foodId == item.id }?.isFavourite ?? false
        }
    }

    private var amountSection: some View {
        Section("Amount") {
            if remembered {
                Text("Starts with your last logged amount")
                    .font(.footnote).foregroundStyle(Color.inkMuted)
            }
            if !item.isPerServe && !item.quantityMeasures.isEmpty {
                Picker("Portion", selection: $portion) {
                    ForEach(item.quantityMeasures, id: \.self) { measure in
                        Text("\(measure.label) (\(NumberText.format(measure.grams)) \(item.portionUnit))")
                            .tag(Optional(measure))
                    }
                    Text(item.portionUnit == "mL" ? "Enter millilitres" : "Enter grams")
                        .tag(nil as FoodMeasure?)
                }
            }
            if portion != nil {
                HStack {
                    Text("Quantity")
                    TextField("Quantity", text: $quantity)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.title2.weight(.semibold)).monospacedDigit()
                        .accessibilityIdentifier("foodPortionQuantity")
                }
                if item.isPerServe {
                    Text(portion?.label ?? "1 serve").font(.footnote).foregroundStyle(Color.inkMuted)
                } else if let grams {
                    Text("Total \(NumberText.format(grams)) \(item.portionUnit)")
                        .font(.footnote).foregroundStyle(Color.inkMuted)
                        .accessibilityIdentifier("foodPortionTotal")
                }
            } else {
                HStack {
                    TextField(item.portionUnit == "mL" ? "Millilitres" : "Grams", text: $measuredAmount)
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.semibold)).monospacedDigit()
                    Text(item.portionUnit).foregroundStyle(Color.inkMuted)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach([50, 100, 150, 200], id: \.self) { amount in
                            chip("\(amount) \(item.portionUnit)") { measuredAmount = String(amount) }
                        }
                    }
                }
            }
        }
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(Color.ink)
            Text(l).font(.caption2).foregroundStyle(Color.inkMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private func chip(_ t: String, _ a: @escaping () -> Void) -> some View {
        Button(t, action: a).font(.footnote.weight(.semibold)).buttonStyle(.bordered).tint(Color.gold)
    }

    private func save() {
        guard let grams else { return }
        let entry = FoodEntry(item: item, grams: grams, meal: meal, source: source,
                              eatenAt: FoodTiming.defaultEatenAt(for: day))
        onDone(FoodDiaryDraft(entry: entry, food: item, favourite: favourite))
        dismiss()
    }
}

/// Fibre, sugars, saturated fat and sodium for the day, from the foods that list them.
struct NutritionDetailCard: View {
    let totals: Macros

    var body: some View {
        if totals.kcal > 0 {
            VStack(alignment: .leading, spacing: 10) {
                Text("MORE DETAIL").font(.caption.weight(.semibold)).tracking(1.6).foregroundStyle(Color.gold)
                HStack(spacing: 0) {
                    item(NumberText.format(totals.fibre.rounded()) + " g", "fibre")
                    item(totals.sugar.map { NumberText.format($0.rounded()) + " g" } ?? "-", "sugars")
                    item(totals.satFat.map { NumberText.format($0.rounded()) + " g" } ?? "-", "sat. fat")
                    item(totals.sodium.map { Int($0.rounded()).formatted() + " mg" } ?? "-", "sodium")
                }
                Text("From the foods that list these. Many home and quick-added foods don't, so treat them as a minimum.")
                    .font(.caption2).foregroundStyle(Color.inkMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            .accessibilityIdentifier("nutritionDetail")
        }
    }

    private func item(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(Color.ink)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(Color.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

enum FoodTiming {
    /// Now for today; midday for another day.
    static func defaultEatenAt(for day: Date, now: Date = .now, calendar: Calendar = .current) -> Date {
        if calendar.isDate(day, inSameDayAs: now) { return now }
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
    }
}

/// Log calories (and macros if you know them) without choosing a food.
struct QuickAddSheet: View {
    let meal: MealSlot
    let day: Date
    let onDone: (FoodDiaryDraft) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kcal: Double?
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    field("Calories (kcal)", $kcal)
                        .accessibilityIdentifier("quickKcal")
                    TextField("What was it? (optional)", text: $name)
                }
                Section {
                    field("Protein (g)", $protein); field("Carbohydrate (g)", $carbs); field("Fat (g)", $fat)
                } header: { Text("Macros, if you know them") } footer: {
                    Text("Left blank, they count as zero towards today's protein, carbs and fat.")
                }
            }
            .themedList()
            .navigationTitle("Quick add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }.disabled((kcal ?? 0) <= 0)
                        .accessibilityIdentifier("quickSave")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Stored as a 100 g portion so the numbers come out exactly as typed.
        let item = FoodItem(id: "quick-" + UUID().uuidString, name: label.isEmpty ? "Quick add" : label, brand: nil, barcode: nil,
                            per100: Per100(kcal: kcal ?? 0, protein: protein ?? 0, carbs: carbs ?? 0, fat: fat ?? 0),
                            servingGrams: nil, servingLabel: nil)
        let entry = FoodEntry(item: item, grams: 100, meal: meal, source: .manual,
                              eatenAt: FoodTiming.defaultEatenAt(for: day))
        onDone(FoodDiaryDraft(entry: entry))
        dismiss()
    }

    private func field(_ label: String, _ v: Binding<Double?>) -> some View {
        HStack {
            Text(label)
            TextField("0", value: v, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
        }
    }
}

struct EditEntrySheet: View {
    let entry: FoodEntry
    var food: FoodItem? = nil
    let onSave: () throws -> Void
    let onDelete: () throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var amount = 0.0
    @State private var measure: FoodMeasure?
    @State private var slot: MealSlot = .snacks
    @State private var eatenAt = Date.now
    @State private var saveError = false

    private var canEditAmount: Bool { entry.grams > 0 && !entry.foodId.hasPrefix("quick-") }
    private var amountLabel: String {
        if let measure { return measure.label == "1 serve" ? "Serves" : "Quantity" }
        return entry.portionUnit == "mL" ? "Millilitres" : "Grams"
    }
    private var updatedAmount: Double { amount * (measure?.grams ?? 1) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(entry.name).font(.title3.weight(.semibold))
                    if canEditAmount {
                        if let measure, amountLabel == "Quantity" {
                            LabeledContent("Portion", value: measure.label)
                        }
                        LabeledContent(amountLabel) {
                            TextField(amountLabel, value: $amount, format: .number)
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        }
                    }
                    Picker("Meal", selection: $slot) {
                        ForEach(MealSlot.allCases) { Text($0.label).tag($0) }
                    }
                    DatePicker("Eaten at", selection: $eatenAt)
                }
                Section {
                    LabeledContent("Logged", value: entry.loggedAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Source", value: entry.source.rawValue.capitalized)
                }
                Section {
                    Button("Delete", role: .destructive) {
                        do { try onDelete(); dismiss() }
                        catch { saveError = true }
                    }
                    .accessibilityIdentifier("deleteDiaryFood")
                }
            }
            .themedList()
            .navigationTitle("Edit food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if canEditAmount { entry.updatePortion(updatedAmount) }
                        entry.mealRaw = slot.rawValue
                        entry.eatenAt = eatenAt
                        do { try onSave(); dismiss() }
                        catch { saveError = true }
                    }
                    .disabled(canEditAmount && (!(0...100_000).contains(updatedAmount) || updatedAmount <= 0))
                }
            }
            .alert("Couldn’t update the food", isPresented: $saveError) {
                Button("OK", role: .cancel) {}
            }
            .onAppear {
                if entry.foodId.hasPrefix(FoodItem.perServePrefix) {
                    measure = FoodMeasure(label: "1 serve", grams: 100)
                } else if food?.portionUnit == entry.portionUnit {
                    measure = food?.measure(forLoggedAmount: entry.grams)
                }
                amount = entry.grams / (measure?.grams ?? 1)
                slot = entry.meal
                eatenAt = entry.eatenAt
            }
        }
    }
}

struct CustomFoodForm: View {
    let onSave: (FoodItem) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var brand = ""
    @State private var barcode: String
    @State private var kcal: Double?
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?
    @State private var fibre: Double?
    @State private var sugar: Double?
    @State private var satFat: Double?
    @State private var sodium: Double?
    @State private var serving: Double?
    @State private var unit = "g"
    @State private var scannedPanel = false
    @State private var confirmedPanel = false
    @State private var saveError = false
    @State private var scanningBarcode = false
    @State private var reading = false
    @State private var note: String?

    init(barcode: String? = nil, item: FoodItem? = nil, initialName: String? = nil, initialNote: String? = nil,
         onSave: @escaping (FoodItem) throws -> Void) {
        self.onSave = onSave
        _barcode = State(initialValue: barcode ?? item?.barcode ?? "")
        _name = State(initialValue: item?.name ?? initialName ?? "")
        _brand = State(initialValue: item?.brand ?? "")
        _kcal = State(initialValue: item?.per100.kcal)
        _protein = State(initialValue: item?.per100.protein)
        _carbs = State(initialValue: item?.per100.carbs)
        _fat = State(initialValue: item?.per100.fat)
        _fibre = State(initialValue: item?.per100.fibre)
        _sugar = State(initialValue: item?.per100.sugar)
        _satFat = State(initialValue: item?.per100.satFat)
        _sodium = State(initialValue: item?.per100.sodium)
        _serving = State(initialValue: item?.servingGrams)
        _unit = State(initialValue: item?.portionUnit ?? "g")
        _note = State(initialValue: initialNote)
        _scannedPanel = State(initialValue: item != nil)
    }

    private var requiresReview: Bool {
        scannedPanel || !barcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSave: Bool {
        guard !reading, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let kcal,
              (0...950).contains(kcal) else { return false }
        let nutrients = [protein, carbs, fat, fibre, sugar, satFat]
        let validNutrients = nutrients.compactMap { $0 }.allSatisfy { (0...100).contains($0) }
        return validNutrients && (0...40_000).contains(sodium ?? 0)
            && (0.001...10_000).contains(serving ?? 100)
            && (!requiresReview || (confirmedPanel && protein != nil && carbs != nil && fat != nil))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PackPhotoButton(title: "Photo of the barcode", systemImage: "barcode.viewfinder") { image in
                        Task { await readBarcode(image) }
                    }
                    PackPhotoButton(title: "Photo of the nutrition panel", systemImage: "text.viewfinder") { image in
                        Task { await readPanel(image) }
                    }
                    .accessibilityIdentifier("panelPhoto")
                    if reading { HStack { ProgressView(); Text("Reading the photo").foregroundStyle(.secondary) } }
                    if let note { Text(note).font(.footnote).foregroundStyle(Color.gold) }
                } header: { Text("Fill it in from the pack") } footer: {
                    Text("The photo is read on your phone and not kept. Always check the numbers against the label before saving.")
                }
                Section { TextField("Name", text: $name); TextField("Brand (optional)", text: $brand) }
                Section {
                    HStack {
                        TextField("Barcode (optional)", text: $barcode).keyboardType(.numberPad)
                            .accessibilityIdentifier("foodBarcode")
                        Button("Scan") { scanningBarcode = true }.buttonStyle(.bordered)
                    }
                } footer: {
                    Text("With a barcode saved, scanning this product again finds it straight away.")
                }
                Section("Nutrition per 100 \(unit)") {
                    Picker("Label unit", selection: $unit) {
                        Text("Grams").tag("g")
                        Text("Millilitres").tag("mL")
                    }
                    field("Energy (kcal)", $kcal); field("Protein (g)", $protein)
                    field("Carbohydrate (g)", $carbs); field("Fat (g)", $fat); field("Fibre (g, optional)", $fibre)
                    field("Sugars (g, optional)", $sugar); field("Saturated fat (g, optional)", $satFat)
                    field("Sodium (mg, optional)", $sodium)
                }
                Section { field("Serving size (\(unit), optional)", $serving) } footer: {
                    Text("To convert kJ to kcal, divide by 4.184.")
                }
                if requiresReview {
                    Section {
                        Toggle("I checked the values and units against the pack", isOn: $confirmedPanel)
                            .accessibilityIdentifier("confirmFoodValues")
                    } footer: {
                        Text("Enter energy, protein, carbohydrate and fat, including any zeros shown on the label.")
                    }
                }
            }
            .themedList()
            .navigationTitle(requiresReview ? "Review food" : "Create food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let code = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
                        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let item = FoodItem(id: code.isEmpty ? "custom-" + UUID().uuidString : code,
                                            name: cleanName, brand: brand.isEmpty ? nil : brand,
                                            barcode: code.isEmpty ? nil : code,
                                            per100: Per100(kcal: kcal ?? 0, protein: protein ?? 0, carbs: carbs ?? 0,
                                                           fat: fat ?? 0, fibre: fibre ?? 0, sugar: sugar, satFat: satFat, sodium: sodium),
                                            servingGrams: serving, servingLabel: nil, amountUnit: unit == "mL" ? unit : nil)
                        do { try onSave(item) }
                        catch { saveError = true }
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("saveFood")
                }
            }
            .alert("Couldn’t save the food", isPresented: $saveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your edits are still here. Try saving again.")
            }
            .fullScreenCover(isPresented: $scanningBarcode) {
                BarcodeScanner { code in barcode = code; scanningBarcode = false } onCancel: { scanningBarcode = false }
            }
        }
    }

    private func readBarcode(_ image: UIImage) async {
        guard !reading else { return }
        reading = true
        defer { reading = false }
        if let code = await PanelScanner.barcodes(in: image).first {
            barcode = code
            note = "Barcode \(code) read."
        } else {
            note = "Couldn't find a barcode in that photo. Try again closer and in good light, or tap Scan."
        }
    }

    private func readPanel(_ image: UIImage) async {
        guard !reading else { return }
        reading = true
        defer { reading = false }
        let r = NutritionPanel.parse(await PanelScanner.rows(in: image))
        guard r.foundAnything else {
            note = "Couldn't read the numbers. Lay the panel flat in good light and try again, or type them in."
            return
        }
        scannedPanel = true
        confirmedPanel = false
        if let amountUnit = r.amountUnit { unit = amountUnit }
        kcal = r.kcal
        protein = r.protein
        carbs = r.carbs
        fat = r.fat
        fibre = r.fibre
        sugar = r.sugar
        satFat = r.satFat
        sodium = r.sodium
        serving = r.servingGrams
        let missing = [("energy", r.kcal), ("protein", r.protein), ("carbohydrate", r.carbs), ("fat", r.fat),
                       ("sugars", r.sugar), ("fibre", r.fibre), ("sodium", r.sodium)].filter { $0.1 == nil }.map(\.0)
        var text = "Check each value against the nutrition panel before saving."
        if !r.hasConfirmedBasis { text += " Check that the values are per 100 g or per 100 mL." }
        if !missing.isEmpty { text += " Blank: \(missing.joined(separator: ", "))." }
        note = text
    }

    private func field(_ label: String, _ v: Binding<Double?>) -> some View {
        HStack {
            Text(label)
            TextField("0", value: v, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
        }
    }
}

/// A button that offers the camera or the photo library and hands back the picture.
struct PackPhotoButton: View {
    let title: String
    let systemImage: String
    let onImage: (UIImage) -> Void
    @State private var asking = false
    @State private var camera = false
    @State private var library = false
    @State private var item: PhotosPickerItem?
    @State private var image: UIImage?

    var body: some View {
        Button { asking = true } label: { Label(title, systemImage: systemImage) }
            .confirmationDialog(title, isPresented: $asking, titleVisibility: .visible) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) { Button("Take a photo") { camera = true } }
                Button("Choose from photos") { library = true }
            }
            .fullScreenCover(isPresented: $camera) { CameraPicker(image: $image).ignoresSafeArea() }
            .photosPicker(isPresented: $library, selection: $item, matching: .images)
            .onChange(of: image) { _, new in if let new { onImage(new); image = nil } }
            .onChange(of: item) { _, new in
                guard let new else { return }
                Task {
                    if let data = try? await new.loadTransferable(type: Data.self), let img = UIImage(data: data) { onImage(img) }
                    item = nil
                }
            }
    }
}

// MARK: - Barcode scanner (VisionKit live text, on-device)

struct BarcodeScanner: View {
    let onCode: (String) -> Void
    let onCancel: () -> Void
    @State private var enteringCode = false
    @State private var typedCode = ""

    var body: some View {
        ZStack(alignment: .top) {
            if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                ScannerRepresentable(onCode: onCode).ignoresSafeArea()
            } else {
                Color.night.ignoresSafeArea()
                ContentUnavailableView("Scanner unavailable", systemImage: "barcode.viewfinder",
                                       description: Text("Allow camera access in Settings or enter the digits printed under the barcode."))
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Point at a barcode").font(.headline).foregroundStyle(.white)
                    Spacer()
                    Button("Cancel", action: onCancel).font(.headline).foregroundStyle(Color.gold)
                }
                Button("Enter barcode") { enteringCode = true }
                    .foregroundStyle(Color.gold)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .alert("Enter barcode", isPresented: $enteringCode) {
            TextField("Barcode", text: $typedCode).keyboardType(.numberPad)
            Button("Continue") {
                onCode(typedCode.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            .disabled(OpenFoodFacts.barcodeKey(typedCode) == nil)
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct ScannerRepresentable: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
                                           qualityLevel: .balanced, isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        var done = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in items {
                if case .barcode(let b) = item, let code = b.payloadStringValue {
                    done = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    scanner.stopScanning()
                    onCode(code)
                    return
                }
            }
        }
    }
}


/// Browse restaurant and takeaway menus by chain and category, with search.
struct RestaurantBrowser: View {
    let onPick: (FoodItem) -> Void
    @Environment(ContentStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                if let menus = store.restaurants {
                    let q = query.trimmingCharacters(in: .whitespaces)
                    if q.isEmpty {
                        ForEach(menus.chains) { chain in
                            NavigationLink {
                                ChainMenuView(chain: chain, onPick: onPick)
                            } label: {
                                LabeledContent(chain.name, value: "\(chain.items.count) items")
                            }
                        }
                        Section {
                            Text("Values come from each chain's own Australian nutrition guide. Menus change, so a recent item may be missing; use Quick add or Plate photo for those.")
                                .font(.footnote).foregroundStyle(Color.inkMuted)
                        }
                    } else {
                        let hits = menus.search(q)
                        if hits.isEmpty { Text("No matching menu items.").foregroundStyle(Color.inkMuted) }
                        ForEach(hits, id: \.item.id) { hit in
                            RestaurantItemRow(chain: hit.chain, item: hit.item, showChain: true) { onPick(hit.item.food(chain: hit.chain)) }
                        }
                    }
                } else {
                    Text("Restaurant menus couldn't be loaded.").foregroundStyle(Color.inkMuted)
                }
            }
            .themedList()
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search menus, e.g. latte")
            .navigationTitle("Restaurants")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}

struct ChainMenuView: View {
    let chain: RestaurantChain
    let onPick: (FoodItem) -> Void

    var body: some View {
        List {
            ForEach(chain.categories, id: \.self) { category in
                Section(category) {
                    ForEach(chain.items.filter { $0.category == category }) { item in
                        RestaurantItemRow(chain: chain, item: item, showChain: false) { onPick(item.food(chain: chain)) }
                    }
                }
            }
            Section("Where these numbers come from") {
                ForEach(chain.sources, id: \.self) { Text($0).font(.footnote).foregroundStyle(Color.inkMuted) }
            }
        }
        .themedList()
        .navigationTitle(chain.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct RestaurantItemRow: View {
    let chain: RestaurantChain
    let item: RestaurantItem
    let showChain: Bool
    let onTap: () -> Void

    private var macroText: String {
        guard !item.isEnergyOnly, let p = item.protein, let c = item.carbs, let f = item.fat else { return "Calories only" }
        return "P \(NumberText.format(p)) C \(NumberText.format(c)) F \(NumberText.format(f))"
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).foregroundStyle(Color.ink).lineLimit(2)
                    Text((showChain ? chain.name + " · " : "") + macroText)
                        .font(.caption).foregroundStyle(Color.inkMuted)
                    if let note = item.note { Text(note).font(.caption2).foregroundStyle(Color.gold) }
                }
                Spacer()
                Text("\(Int(item.kcal.rounded())) kcal").font(.caption.monospacedDigit()).foregroundStyle(Color.inkMuted)
            }
        }
        .accessibilityIdentifier("menu-\(item.id)")
    }
}
