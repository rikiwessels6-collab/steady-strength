import SwiftUI
import SwiftData

/// Optional wellbeing tools. These support a user's choices; they do not diagnose,
/// prescribe, or replace advice from a qualified health professional.
struct WellnessView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FastingSession.startedAt, order: .reverse) private var fasts: [FastingSession]
    @Query(sort: \SupplementEntry.createdAt, order: .reverse) private var supplements: [SupplementEntry]
    @State private var targetHours = 14
    @State private var showingAdd = false

    private var activeFast: FastingSession? { fasts.first { $0.isActive } }

    private func elapsedLabel(for fast: FastingSession) -> String {
        let totalMinutes = max(0, Int(fast.elapsed / 60))
        return "\(totalMinutes / 60)h \(totalMinutes % 60)m"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                fastingCard
                supplementCard
                evidenceCard
                safetyCard
            }
            .padding()
            .padding(.bottom, 24)
        }
        .background(Color.night.ignoresSafeArea())
        .navigationTitle("Wellness tools")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAdd) { AddSupplementSheet { entry in
            context.insert(entry)
            try? context.save()
        } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("OPTIONAL, NOT REQUIRED").font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(Color.gold)
            Text("Build habits that suit your life").font(.title2.weight(.bold)).foregroundStyle(Color.ink)
            Text("Use fasting or supplements only when they help you stay consistent with training, food and recovery.")
                .font(.subheadline).foregroundStyle(Color.inkMuted)
        }
    }

    private var fastingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Fasting", systemImage: "timer").font(.headline).foregroundStyle(Color.ink)
            if let fast = activeFast {
                let progress = min(fast.elapsed / Double(fast.targetHours * 3600), 1)
                Text(elapsedLabel(for: fast))
                    .font(.system(.largeTitle, design: .rounded).weight(.bold)).foregroundStyle(Color.ink)
                ProgressView(value: progress).tint(Color.emerald)
                Text(progress >= 1 ? "Target reached. Eat when it works for you." : "Target: \(fast.targetHours) hours")
                    .font(.footnote).foregroundStyle(Color.inkMuted)
                Button("End fast") {
                    fast.endedAt = .now
                    try? context.save()
                }
                .buttonStyle(.borderedProminent).tint(Color.emerald)
                .accessibilityIdentifier("endFast")
            } else {
                Picker("Fasting target", selection: $targetHours) {
                    Text("12 hours").tag(12); Text("14 hours").tag(14); Text("16 hours").tag(16)
                }
                .pickerStyle(.segmented)
                Button("Start \(targetHours)-hour fast") {
                    context.insert(FastingSession(targetHours: targetHours))
                    try? context.save()
                }
                .buttonStyle(.borderedProminent).tint(Color.emerald)
                .accessibilityIdentifier("startFast")
                Text("Fasting is optional. Your protein, calories and recovery still matter — especially when gaining strength or muscle.")
                    .font(.footnote).foregroundStyle(Color.inkMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).card()
    }

    private var supplementCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Supplements", systemImage: "capsule.fill").font(.headline).foregroundStyle(Color.ink)
                Spacer()
                Button("Add", systemImage: "plus") { showingAdd = true }.font(.subheadline.weight(.semibold))
            }
            if supplements.isEmpty {
                Text("Track products you choose to take, their timing and why you use them. This is a tracker, not a prescription.")
                    .font(.subheadline).foregroundStyle(Color.inkMuted)
            } else {
                ForEach(supplements) { supplement in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.emerald)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(supplement.name).font(.subheadline.weight(.semibold)).foregroundStyle(Color.ink)
                            Text("\(supplement.amount) · \(supplement.timing)").font(.footnote).foregroundStyle(Color.inkMuted)
                            EvidencePill(level: supplement.evidenceRaw)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(get: { supplement.isActive }, set: { supplement.isActive = $0; try? context.save() }))
                            .labelsHidden()
                    }
                    .accessibilityIdentifier("supplement-\(supplement.name)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).card()
    }

    private var evidenceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("What guides Steady Strength", systemImage: "books.vertical.fill").font(.headline).foregroundStyle(Color.ink)
            Text("Training recommendations are reviewed against systematic reviews, major position stands and well-designed trials. Coaches such as Jeff Nippard and Aaron Straker inform the practical presentation, not the evidence threshold.")
                .font(.subheadline).foregroundStyle(Color.inkMuted)
            Divider()
            Text("Research updates are reviewed before they change a plan. You will see what changed, why it changed and how strong the evidence is.")
                .font(.footnote).foregroundStyle(Color.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading).card()
    }

    private var safetyCard: some View {
        Text("Talk with a GP, pharmacist or dietitian before fasting or using supplements if you are pregnant or breastfeeding, under 18, have an eating-disorder history, take medication, or have a medical condition. Do not use this app to treat a deficiency or condition.")
            .font(.footnote).foregroundStyle(Color.inkMuted)
            .frame(maxWidth: .infinity, alignment: .leading).card()
    }
}

private struct EvidencePill: View {
    let level: String
    var body: some View {
        Text(level).font(.caption2.weight(.semibold)).foregroundStyle(Color.gold)
    }
}

private struct AddSupplementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var amount = ""
    @State private var timing = "With breakfast"
    @State private var evidence = "Evidence to review"
    let save: (SupplementEntry) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Your supplement") {
                    TextField("Name", text: $name)
                    TextField("Amount (for example, 3 g)", text: $amount)
                    TextField("When do you take it?", text: $timing)
                    Picker("Evidence", selection: $evidence) {
                        Text("Strong evidence in specific contexts").tag("Strong evidence in specific contexts")
                        Text("Evidence to review").tag("Evidence to review")
                        Text("Personal preference").tag("Personal preference")
                    }
                }
                Section {
                    Text("Record only products you have chosen. Follow the product label and seek individual clinical advice for deficiencies, medications or conditions.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Add supplement")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(SupplementEntry(name: name.trimmingCharacters(in: .whitespaces), amount: amount, timing: timing, evidenceRaw: evidence)); dismiss() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
