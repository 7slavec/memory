//
//  ContentView.swift
//  Memory
//
//  Created by Вячеслав Храмышкин on 15.09.2026.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Item.timestamp, order: .reverse) private var items: [Item]

    @State private var draft = ""
    @State private var errorMessage: String?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                captureBar

                if items.isEmpty {
                    ContentUnavailableView(
                        "Пока пусто",
                        systemImage: "checklist",
                        description: Text("Добавьте первую задачу выше")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(items) { item in
                            itemRow(item)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        delete(item)
                                    } label: {
                                        Label("Удалить", systemImage: "trash")
                                    }
                                }
                        }
                        .onDelete(perform: deleteItems)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Memory")
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
#endif
            }
            .alert("Не удалось сохранить", isPresented: isShowingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Неизвестная ошибка")
            }
        }
    }

    private var captureBar: some View {
        HStack(spacing: 12) {
            TextField("Что нужно запомнить?", text: $draft)
                .textFieldStyle(.roundedBorder)
                .focused($isInputFocused)
                .onSubmit(addItem)

            Button(action: addItem) {
                Image(systemName: "plus")
                    .font(.headline)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderedProminent)
            .disabled(trimmedDraft.isEmpty)
            .accessibilityLabel("Добавить задачу")
        }
        .padding()
    }

    private func itemRow(_ item: Item) -> some View {
        HStack(spacing: 12) {
            Button {
                toggleCompleted(item)
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.isCompleted ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isCompleted ? "Отметить невыполненной" : "Отметить выполненной")

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title.isEmpty ? "Без названия" : item.title)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)

                Text(item.timestamp, format: .dateTime.day().month().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func addItem() {
        let title = trimmedDraft
        guard !title.isEmpty else { return }

        withAnimation {
            modelContext.insert(Item(title: title))
            draft = ""
            saveChanges()
        }

        isInputFocused = true
    }

    private func toggleCompleted(_ item: Item) {
        withAnimation {
            item.isCompleted.toggle()
            saveChanges()
        }
    }

    private func deleteItems(offsets: IndexSet) {
        let itemsToDelete = offsets.map { items[$0] }

        withAnimation {
            itemsToDelete.forEach(modelContext.delete)
            saveChanges()
        }
    }

    private func delete(_ item: Item) {
        withAnimation {
            modelContext.delete(item)
            saveChanges()
        }
    }

    private func saveChanges() {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
