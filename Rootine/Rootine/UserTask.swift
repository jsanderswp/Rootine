//
//  UserTask.swift
//  Rootine
//
//  Created by Jackson Sanders on 4/3/26.
//

import Foundation
import SwiftData

let HEAVY_USAGE: Double = 1.0 //kWh
let CLEAN_THRESHOLD: Int = 50

@Model
final class UserTask {
    var name: String
    var energyUsage: Double
    var taskLength: String
    var timestamp: Date
    var originalTimestamp: Date?  // Track original time before optimization
    var isHighImpact: Bool
    
    init(name: String, energyUsage: Double, taskLength: String, timestamp: Date) {
        self.name = name
        self.energyUsage = energyUsage
        self.taskLength = taskLength
        self.timestamp = timestamp
        self.originalTimestamp = timestamp  // Store original time
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
