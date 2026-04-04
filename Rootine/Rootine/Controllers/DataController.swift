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
    
    var currentTask: Task<Void, Never>?
    
    func processInput(_ input: String) {
        Task {
            guard let text = text else { return }
            let result = await geminiService.parseActivities(text)
            
            guard !Task.isCancelled else { return }

            switch result {
            case .success(let activities):
                let activityEnergies = energyService.calculateEnergy(from: activities)
                let activityImpacts = await energyService.calculateImpact(from: activityEnergies)
                
                guard !Task.isCancelled else { return }
                self.activityImpacts = activityImpacts
                
                let prices = await costService.fetchHourlyPrices()

            case .failure(let error):
                print("Gemini error:", error)
                self.activityImpacts = nil
            }
        }
    }
    
    func scheduleActivities(
        impacts: [ActivityImpact],
        prices: [HourlyPrice],
        baseDate: Date
    ) -> [ScheduledActivity] {
        
        var scheduled: [ScheduledActivity] = []
        let calendar = Calendar.current
        
        for impact in impacts {
            let activity = impact.activity
            
            var bestScore = Double.infinity
            var bestStartHour = 0
            
            for startIndex in 0..<prices.count {
                
                let durationHours = Int(ceil(activity.duration ?? 1))
                
                // Ensure activity fits within available hours
                guard startIndex + durationHours <= prices.count else { continue }
                
                var totalPrice = 0.0
                
                for i in startIndex..<(startIndex + durationHours) {
                    totalPrice += prices[i].price
                }
                
                let score = (impact.kWh * totalPrice) * impact.impactScore
                
                if score < bestScore {
                    bestScore = score
                    bestStartHour = prices[startIndex].hour
                }
            }
            
            let startTime = calendar.date(
                bySettingHour: bestStartHour,
                minute: 0,
                second: 0,
                of: baseDate
            ) ?? baseDate
            
            let totalCost = impact.kWh * bestScore
            let carbon = impact.kWh * (bestScore / impact.kWh) // adjust if needed
            
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
