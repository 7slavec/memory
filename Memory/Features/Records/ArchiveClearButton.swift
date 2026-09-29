import SwiftUI

struct ArchiveClearButton: View {
    let itemIDs: [UUID]
    let onClear: (Set<UUID>) -> Void
    @State private var pendingIDs: Set<UUID> = []
    @State private var showsConfirmation = false

    var body: some View {
        Button {
            pendingIDs = Set(itemIDs)
            showsConfirmation = true
        } label: { Label("Очистить архив", systemImage: "trash") }
            .buttonStyle(MemoryActionStyle())
            .disabled(itemIDs.isEmpty)
            .confirmationDialog("Удалить записи из архива?", isPresented: $showsConfirmation, titleVisibility: .visible) {
                Button("Удалить все (\(pendingIDs.count))", role: .destructive) { onClear(pendingIDs) }
                Button("Отмена", role: .cancel) { pendingIDs = [] }
            } message: {
                Text("Будут удалены все \(pendingIDs.count) записей архива, независимо от поиска. Активные записи останутся. Удаление синхронизируется между устройствами; отмены в приложении нет.")
            }
    }
}
