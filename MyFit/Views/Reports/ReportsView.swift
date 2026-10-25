import SwiftUI
import SwiftData

struct ReportsView: View {
    @Query(sort: \ReportSnapshot.createdAt, order: .reverse) private var snapshots: [ReportSnapshot]
    @State private var showingNewReport = false

    private static let rangeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        formatter.locale = Locale(identifier: "es_ES")
        return formatter
    }()

    var body: some View {
        NavigationStack {
            Group {
                if snapshots.isEmpty {
                    ContentUnavailableView("Sin reportes",
                                           systemImage: "square.and.arrow.up.on.square",
                                           description: Text("Pulsa + para generar tu primer reporte."))
                } else {
                    List {
                        ForEach(snapshots) { snapshot in
                            NavigationLink {
                                ReportDetailView(snapshot: snapshot)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(rangeLabel(snapshot))
                                        .fontWeight(.semibold)
                                    Text("Generado el \(snapshot.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Reportes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingNewReport = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewReport) {
                NewReportView()
            }
        }
    }

    private func rangeLabel(_ snapshot: ReportSnapshot) -> String {
        "\(Self.rangeFormatter.string(from: snapshot.rangeStart)) - \(Self.rangeFormatter.string(from: snapshot.rangeEnd))"
    }
}

#Preview {
    ReportsView()
        .modelContainer(for: [Workout.self, Exercise.self, WeightEntry.self, Meal.self,
                              Recipe.self, PlannedMeal.self, ReportSnapshot.self],
                        inMemory: true)
}
