import SwiftUI
import SwiftData

public struct CategoryManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CategoryItem.name) private var categories: [CategoryItem]
    
    @State private var showingAddCategory = false
    @State private var categoryToEdit: CategoryItem? = nil
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(categories) { category in
                        Button {
                            categoryToEdit = category
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: category.iconName)
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(width: 36, height: 36)
                                    .background(Color(hex: category.colorHex))
                                    .clipShape(Circle())
                                
                                Text(category.name)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteCategory(category)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete(perform: deleteOffsets)
                } header: {
                    Text("Categories (\(categories.count))")
                        .lineLimit(1)
                } footer: {
                    Text("Tap a category to edit its name, icon, or color.")
                        .lineLimit(1)
                }
            }
            .navigationTitle("Manage Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .lineLimit(1)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddCategory = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .lineLimit(1)
                }
            }
            .sheet(isPresented: $showingAddCategory) {
                CategoryEditSheet(category: nil)
            }
            .sheet(item: $categoryToEdit) { category in
                CategoryEditSheet(category: category)
            }
        }
    }
    
    private func deleteCategory(_ category: CategoryItem) {
        withAnimation {
            modelContext.delete(category)
            try? modelContext.save()
        }
    }
    
    private func deleteOffsets(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(categories[index])
            }
            try? modelContext.save()
        }
    }
}

public struct CategoryEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let category: CategoryItem?
    
    @State private var name: String = ""
    @State private var selectedIcon: String = "tag.fill"
    @State private var selectedColorHex: String = "#007AFF"
    
    public static let availableIcons = [
        "fork.knife", "cup.and.saucer.fill", "tram.fill", "car.fill",
        "cart.fill", "bag.fill", "bolt.fill", "tv.fill",
        "heart.fill", "airplane", "house.fill", "cross.case.fill",
        "graduationcap.fill", "gift.fill", "gamecontroller.fill", "tag.fill",
        "pawprint.fill", "briefcase.fill", "film.fill", "creditcard.fill"
    ]
    
    public static let availableColors = [
        "#007AFF", "#34C759", "#FF9500", "#FF2D55",
        "#AF52DE", "#5856D6", "#FF3B30", "#5AC8FA",
        "#00C7BE", "#FFCC00", "#8E8E93", "#30B0C7"
    ]
    
    public init(category: CategoryItem?) {
        self.category = category
        _name = State(initialValue: category?.name ?? "")
        _selectedIcon = State(initialValue: category?.iconName ?? "tag.fill")
        _selectedColorHex = State(initialValue: category?.colorHex ?? "#007AFF")
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                Section("Category Name") {
                    TextField("Name (e.g. Coffee, Pets, Rent)", text: $name)
                        .lineLimit(1)
                }
                
                Section("Preview") {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: selectedIcon)
                                .font(.title)
                                .foregroundStyle(.white)
                                .frame(width: 60, height: 60)
                                .background(Color(hex: selectedColorHex))
                                .clipShape(Circle())
                            
                            Text(name.isEmpty ? "Category Name" : name)
                                .font(.headline)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                
                Section("Choose Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 14) {
                        ForEach(Self.availableIcons, id: \.self) { icon in
                            Button {
                                selectedIcon = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.title2)
                                    .frame(width: 44, height: 44)
                                    .background(selectedIcon == icon ? Color(hex: selectedColorHex).opacity(0.2) : Color(.tertiarySystemFill))
                                    .foregroundStyle(selectedIcon == icon ? Color(hex: selectedColorHex) : .primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(selectedIcon == icon ? Color(hex: selectedColorHex) : Color.clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Section("Choose Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 14) {
                        ForEach(Self.availableColors, id: \.self) { hex in
                            Button {
                                selectedColorHex = hex
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.primary, lineWidth: selectedColorHex == hex ? 3 : 0)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(category == nil ? "New Category" : "Edit Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .lineLimit(1)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveCategory()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .lineLimit(1)
                }
            }
        }
    }
    
    private func saveCategory() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = category {
            existing.name = trimmedName
            existing.iconName = selectedIcon
            existing.colorHex = selectedColorHex
        } else {
            let newCat = CategoryItem(name: trimmedName, iconName: selectedIcon, colorHex: selectedColorHex)
            modelContext.insert(newCat)
        }
        try? modelContext.save()
    }
}
