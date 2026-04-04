//
//  DataController.swift
//  Rootine
//
//  Created by Jackson Sanders on 4/3/26.
//

import Foundation
import SwiftData

@MainActor
@Observable
class DataController {
    var text: String?
    var activityImpacts: [ActivityImpact]?
    
    private let geminiService = GeminiService()
    private let energyService = EnergyService()
    private let costService = CostService()
    
    var currentTask: Task?
    
    func scheduleActivities(
        impacts: [ActivityImpact],
        prices: [HourlyPrice],
        baseDate: Date
    ) -> [ScheduledActivity] {
        
        var scheduled: [ScheduledActivity] = []
        let calendar = Calendar.current
        var occupiedHours: Set<Int> = []
        
        for impact in impacts {
            let activity = impact.activity
            
            var bestScore = Double.infinity
            var bestStartHour = 0
            var bestSlots: [Int] = []
            
            let durationHours = Int(ceil(activity.duration ?? 1))
            
            for startIndex in 0..<prices.count {
                
                let requiredSlots = startIndex..<(startIndex + durationHours)
                
                // Ensure within bounds
                guard startIndex + durationHours <= prices.count else { continue }
                
                // Skip if overlapping
                if requiredSlots.contains(where: { occupiedHours.contains($0) }) {
                    continue
                }
                
                // Calculate total price once
                var totalPrice = 0.0
                for i in requiredSlots {
                    totalPrice += prices[i].price
                }
                
                let score = (impact.kWh * totalPrice) * impact.impactScore
                
                if score < bestScore {
                    bestScore = score
                    bestStartHour = prices[startIndex].hour
                    bestSlots = Array(requiredSlots)
                }
            }
            
            let startTime = calendar.date(
                bySettingHour: bestStartHour,
                minute: 0,
                second: 0,
                of: baseDate
            ) ?? baseDate
            
            let totalCost = impact.kWh * bestScore
            
            // Optional: simple placeholder carbon model
            let carbon = impact.kWh * 0.5
            
            // Mark hours as occupied
            for slot in bestSlots {
                occupiedHours.insert(slot)
            }
            
            scheduled.append(
                ScheduledActivity(
                    activity: activity,
                    energyUsage: impact.kWh,
                    cost: totalCost,
                    carbon: carbon,
                    startTime: startTime
                )
            )
        }
        
        return scheduled
    }
}

struct ScheduledActivity {
    let activity: Activity
    let energyUsage: Double
    let cost: Double
    let carbon: Double
    let startTime: Date
}
