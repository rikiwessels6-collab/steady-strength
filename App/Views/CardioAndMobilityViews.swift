import SwiftUI
import SwiftData
import SteadyCore

/// Log a cardio or conditioning session: what, how long, and optionally distance and calories from the machine.
struct CardioLogSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var appSettings: [AppSettings]
    @State private var kind: CardioKind = .run
    @State private var minutes = 20
    @State private var distance: Double?
    @State private var kcal: Int?
    @State private var finished = Date.now
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("What") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                        ForEach(CardioKind.allCases) { k in
                            Button { kind = k } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: k.symbol).font(.title3)
                                    Text(k.label).font(.caption2).multilineTextAlignment(.center).lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, minHeight: 64)
                                .foregroundStyle(kind == k ? Color.night : Color.ink)
                                .background(kind == k ? Color.emerald : Color.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(kind == k ? .isSelected : [])
                            .accessibilityIdentifier("cardio-\(k.rawValue)")
                        }
                    }
                    .listRowBackground(Color.clear)
                }
                Section {
                    Stepper(value: $minutes, in: 1...300, step: minutes < 10 ? 1 : 5) {
                        LabeledContent("Time", value: "\(minutes) min")
                    }
                    if kind.hasDistance {
                        HStack {
                            Text("Distance (km, optional)")
                            TextField("0", value: $distance, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        }
                    }
                    HStack {
                        Text("Calories (from the machine, optional)")
                        TextField("0", value: $kcal, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                    DatePicker("Finished", selection: $finished, in: ...Date.now)
                    TextField("Notes (optional)", text: $notes, axis: .vertical).lineLimit(1...3)
                }
            }
            .themedList()
            .navigationTitle("Log cardio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let s = CardioSession(date: finished, kind: kind, minutes: minutes,
                                              distanceKm: kind.hasDistance ? distance : nil, kcal: kcal,
                                              notes: notes.trimmingCharacters(in: .whitespacesAndNewlines))
                        context.insert(s)
                        try? context.save()
                        HealthSync.saveIfWanted(s, settings: appSettings.first, context: context)
                        dismiss()
                    }
                    .accessibilityIdentifier("saveCardio")
                }
            }
        }
    }
}

/// One line for a logged cardio session.
struct CardioRow: View {
    let session: CardioSession
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: session.kind.symbol).foregroundStyle(Color.emerald).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.kind.label).foregroundStyle(Color.ink)
                Text(session.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(Color.inkMuted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(session.minutes) min").font(.subheadline.monospacedDigit())
                if let d = session.distanceKm, d > 0 {
                    Text("\(NumberText.format((d * 10).rounded() / 10)) km").font(.caption.monospacedDigit()).foregroundStyle(Color.inkMuted)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The guided routines, listed on the Train tab.
struct MobilitySection: View {
    var body: some View {
        Section {
            ForEach(Mobility.routines) { r in
                NavigationLink { MobilityPlayerView(routine: r) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.name)
                        Text("\(r.minutes) min · \(r.summary)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("mobility-\(r.id)")
            }
        } header: { Text("Mobility and stretching") } footer: {
            Text("Guided and timed. Move gently, breathe slowly, and stop anything that hurts.")
        }
    }
}

/// Plays a routine: one step at a time with a countdown, moving on by itself.
struct MobilityPlayerView: View {
    let routine: MobilityRoutine
    @State private var index = 0
    @State private var endsAt: Date?
    @State private var remaining: Int = 0
    @State private var finished = false

    private var step: MobilityStep { routine.steps[min(index, routine.steps.count - 1)] }

    var body: some View {
        VStack(spacing: 24) {
            BrandProgress(value: Double(index) / Double(max(routine.steps.count, 1)))
            Text("STEP \(index + 1) OF \(routine.steps.count)").font(.caption.weight(.semibold)).tracking(1.6).foregroundStyle(Color.gold)
            if finished {
                Spacer()
                Image(systemName: "checkmark.seal.fill").font(.system(size: 64)).foregroundStyle(LinearGradient.brand)
                Text("Routine done").font(.largeTitle.weight(.bold)).foregroundStyle(Color.ink)
                Text("\(routine.minutes) minutes of \(routine.name.lowercased()).").foregroundStyle(Color.inkMuted)
                Spacer()
            } else {
                VStack(spacing: 8) {
                    Text(step.name).font(.title.weight(.bold)).foregroundStyle(Color.ink).multilineTextAlignment(.center)
                    if let side = step.side {
                        Text(side.uppercased() + " SIDE").font(.headline).foregroundStyle(Color.emerald)
                    }
                }
                Text(step.cue).font(.body).foregroundStyle(Color.inkMuted).multilineTextAlignment(.center)
                Spacer()
                TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
                    let left = endsAt.map { max(0, Int($0.timeIntervalSince(ctx.date).rounded(.up))) } ?? remaining
                    Text("\(left)")
                        .font(.system(size: 96, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.ink)
                        .onChange(of: left) { _, value in if value == 0 && endsAt != nil { advance() } }
                }
                Spacer()
                HStack(spacing: 16) {
                    control("backward.fill", "Previous step") { go(to: max(0, index - 1)) }
                    control(endsAt == nil ? "play.fill" : "pause.fill", endsAt == nil ? "Start" : "Pause") { toggle() }
                        .accessibilityIdentifier("mobilityPlay")
                    control("forward.fill", "Next step") { advance() }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.night.ignoresSafeArea())
        .navigationTitle(routine.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            remaining = step.seconds
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private func control(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.title2.weight(.semibold)).foregroundStyle(Color.night)
                .frame(width: 64, height: 64).background(LinearGradient.brand, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func toggle() {
        if let end = endsAt {
            remaining = max(0, Int(end.timeIntervalSinceNow.rounded(.up)))
            endsAt = nil
        } else {
            endsAt = Date.now.addingTimeInterval(TimeInterval(max(remaining, 1)))
        }
    }

    private func go(to i: Int) {
        let running = endsAt != nil
        index = i
        remaining = routine.steps[i].seconds
        endsAt = running ? Date.now.addingTimeInterval(TimeInterval(remaining)) : nil
    }

    private func advance() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if index + 1 < routine.steps.count {
            go(to: index + 1)
        } else {
            endsAt = nil
            finished = true
        }
    }
}
