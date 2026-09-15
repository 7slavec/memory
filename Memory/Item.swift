//
//  Item.swift
//  Memory
//
//  Created by Вячеслав Храмышкин on 15.09.2026.
//

import Foundation
import SwiftData

@Model
final class Item {
    var title: String = ""
    var timestamp: Date = Date.now
    var isCompleted: Bool = false

    init(
        title: String,
        timestamp: Date = .now,
        isCompleted: Bool = false
    ) {
        self.title = title
        self.timestamp = timestamp
        self.isCompleted = isCompleted
    }
}
