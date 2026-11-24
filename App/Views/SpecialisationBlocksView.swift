import SwiftUI
import SwiftData
import SteadyCore

/// Optional six-week focus sessions. They log as open workouts, so the user's
/// selected program and its next session remain unchanged.
struct SpecialisationBlocksView: View {
    @Environment(ContentStore.self) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Specialisation?
    @State private var sessionIndex = 0
    @State private var workout: WorkoutLog?

    var body: some View {
        List {
            Section {
                Text("Run one of these twice a week for up to six weeks alongside your current program. Start with the first session, then alternate A and B. The work is logged separately and does not move your main program forward.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(SpecialisationCatalogue.all) { block in
                Button { selected = block; sessionIndex = 0 } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(block.name).foregroundStyle(.primary).font(.headline)
                        Text("6 weeks · 2 sessions each week · (block.targetMuscles.map(VolumeReport.prettyName).joined(separator: ", "))")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("focus-\(block.id)")
            }
        }
        .themedList()
        .navigationTitle("Focus blocks")
        .sheet(item: $selected) { block in
            NavigationStack {
                List {
                    Section("Choose today’s session") {
                        ForEach(block.sessions.indices, id: \.self) { i in
                            Button { sessionIndex = i } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text("Session \(i == 0 ? "A" : "B")").foregroundStyle(.primary)
                                        Text(block.sessions[i].compactMap { store.content?.library[$0.exerciseId]?.name }.joined(separator: " · "))
                                            .font(.footnote).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if i == sessionIndex { Image(systemName: "checkmark").foregroundStyle(.tint) }
                                }
                            }
                        }
                    }
                    Section {
                        Button("Start focus workout") {
                            let session = block.sessions[sessionIndex]
                            workout = FreeWorkout.start(name: "\(block.name) focus · \(sessionIndex == 0 ? "A" : "B")", module: session, in: context)
                            selected = nil
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
                .navigationTitle(block.name)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { selected = nil } } }
            }
        }
        .fullScreenCover(item: $workout) { FreeWorkoutView(log: $0) }
    }
}
