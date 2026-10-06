import Foundation
import SwiftData

@Model
public final class CategoryItem {
    public var id: UUID
    public var name: String
    public var iconName: String
    public var colorHex: String
    
    @Relationship(inverse: \TransactionItem.category)
    public var transactions: [TransactionItem]?
    
    public init(id: UUID = UUID(), name: String, iconName: String = "tag.fill", colorHex: String = "#007AFF") {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.colorHex = colorHex
    }
    
    public static let defaultCategories: [(name: String, icon: String, color: String)] = [
        ("Dining", "fork.knife", "#FF9500"),
        ("Transport", "tram.fill", "#007AFF"),
        ("Groceries", "cart.fill", "#34C759"),
        ("Shopping", "bag.fill", "#AF52DE"),
        ("Bills & Utilities", "bolt.fill", "#5856D6"),
        ("Entertainment", "tv.fill", "#FF2D55"),
        ("Health & Fitness", "heart.fill", "#FF3B30"),
        ("Other", "ellipsis.circle.fill", "#8E8E93")
    ]
}
