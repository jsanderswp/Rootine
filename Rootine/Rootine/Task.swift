//
//  Item.swift
//  Rootine
//
//  Created by Jackson Sanders on 4/3/26.
//

import Foundation
import SwiftData

let HEAVY_USAGE: Float = 1.0 //kWh
let CLEAN_THRESHOLD: Int = 50

@Model
final class UserTask {
    var name: String
    var energyUsage: Float
    var taskLength: String
    var timestamp: Date
    var isHighImpact: Bool
    
    init(name: String, energyUsage: Float, taskLength: String, timestamp: Date) {
        self.name = name
        self.energyUsage = energyUsage
        self.taskLength = taskLength
        self.timestamp = timestamp
        isHighImpact = energyUsage >= HEAVY_USAGE
    }
}

extension UserTask: Comparable {
    static func == (lhs: UserTask, rhs: UserTask) -> Bool {
        lhs.energyUsage == rhs.energyUsage
    }

    static func < (lhs: UserTask, rhs: UserTask) -> Bool {
        lhs.energyUsage < rhs.energyUsage
    }
}
