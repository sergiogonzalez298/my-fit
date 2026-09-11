import SwiftUI

struct ReportDetailView: View {
    let snapshot: ReportSnapshot

    @State private var showingRegenerateConfirm = false
    @State private var showingEditSheet = false
    @State private var showingFallbackShare = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(snapshot.reportText)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)

                Text("Generado el \(snapshot.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Reporte")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        WhatsAppSender.send(snapshot.reportText) {
                            showingFallbackShare = true
                        }
                    } label: {
                        Label("Reenviar", systemImage: "paperplane")
                    }
                    Button {
                        showingRegenerateConfirm = true
                    } label: {
                        Label("Editar y regenerar", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("¿Regenerar este reporte?",
                            isPresented: $showingRegenerateConfirm,
                            titleVisibility: .visible) {
            Button("Editar y regenerar") { showingEditSheet = true }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se recalculará con los datos actuales y sustituirá el texto de este reporte.")
        }
        .sheet(isPresented: $showingEditSheet) {
            NewReportView(existingSnapshot: snapshot)
        }
        .sheet(isPresented: $showingFallbackShare) {
            ActivityShareSheet(items: [snapshot.reportText])
        }
    }
}
