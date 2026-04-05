//  DataController.swift
//  Rootine
//
//  Created by Jackson Sanders on 4/3/26.
//

import Observation
import Foundation

@MainActor
@Observable
class DataController {
    var text: String?
    var activityImpacts: [ActivityImpact]?
    var baseDate: Date?

    private let geminiService = GeminiService()
    private let energyService = EnergyService()
    private let rateService   = LADWPRateService.shared

    var solarPeak: Date? = nil
    var totalCO2Saved: Float = 0.0

    var currentTask: Task<Void, Never>?

    func processTasks(_ inputs: [String]) async -> [ScheduledActivity] {
        let now = baseDate ?? Date()
        let currentHourStart = Calendar.current.dateInterval(of: .hour, for: now)!.start
        let minutes = Calendar.current.component(.minute, from: now)
        let base = minutes >= 30
            ? Calendar.current.date(byAdding: .hour, value: 1, to: currentHourStart)!
            : currentHourStart

        var impacts: [ActivityImpact] = []

        // Also build the unoptimized sequential baseline: tasks run back-to-back from base.
        // This is what the user would do without the app — used for CO₂ savings comparison.
        var unoptimizedCursor = base
        var unoptimizedHours: [String: Int] = [:]   // originalInput → unoptimized start hour

        for input in inputs {
            let result = await geminiService.parseActivities(input)

            switch result {
            case .success(let activities):
                let energies = energyService.calculateEnergy(from: activities, startingAt: base)
                let activityImpacts = await energyService.calculateImpact(
                    from: energies,
                    using: rateService,
                    originalInput: input
                )
                impacts.append(contentsOf: activityImpacts)

                // Record the unoptimized hour for this input, then advance cursor by total duration
                unoptimizedHours[input] = Calendar.current.component(.hour, from: unoptimizedCursor)
                let totalDuration = activities.reduce(0.0) { $0 + ($1.duration ?? 60.0) }
                unoptimizedCursor = unoptimizedCursor.addingTimeInterval(totalDuration * 60)

            case .failure(let error):
                print("Gemini error:", error)
            }
        }

        let scheduled = await scheduleActivities(
            impacts: impacts,
            baseDate: base,
            energyService: energyService,
            rateService: rateService
        )

        self.activityImpacts = impacts

        // Calculate CO₂ savings: optimized hours vs the unoptimized sequential baseline
        await calculateCO2Savings(schedule: scheduled, originalHours: unoptimizedHours)

        return scheduled
    }

    /// Compares carbon intensity at each task's unoptimized hour vs its scheduled hour.
    /// Positive = we saved CO₂. Negative = we made it worse (shouldn't happen for energy tasks,
    /// but non-energy tasks are intentionally put in bad slots so they may not contribute).
    private func calculateCO2Savings(
        schedule: [ScheduledActivity],
        originalHours: [String: Int]
    ) async {
        guard let carbonForecast = await energyService.fetchCarbonForecast() else {
            return
        }

        var totalSavings: Double = 0

        for scheduled in schedule {
            // Only count energy-consuming tasks — non-energy tasks have negligible kWh
            // and are placed in bad slots intentionally, which would skew savings negative
            guard scheduled.impact.kWh > 0.01 else { continue }

            guard let originalInput = scheduled.impact.originalInput,
                  let originalHour = originalHours[originalInput] else { continue }

            let optimizedHour = scheduled.scheduledHour
            let originalCarbon  = carbonForecast[originalHour]?.carbonIntensity  ?? 0
            let optimizedCarbon = carbonForecast[optimizedHour]?.carbonIntensity ?? 0

            // kg CO₂: (g/kWh difference) × kWh ÷ 1000 g/kg
            let savingsKg = (originalCarbon - optimizedCarbon) * scheduled.impact.kWh / 1000.0
            totalSavings += savingsKg

            
        }

        totalCO2Saved = Float(totalSavings)
    
    }

    func processTask(_ input: String) async -> ActivityImpact? {
        let now = baseDate ?? Date()
        let currentHourStart = Calendar.current.dateInterval(of: .hour, for: now)!.start
        let minutes = Calendar.current.component(.minute, from: now)
        let base = minutes >= 30
            ? Calendar.current.date(byAdding: .hour, value: 1, to: currentHourStart)!
            : currentHourStart

        
        let result = await geminiService.parseActivities(input)

        switch result {
        case .success(let activities):
            guard !activities.isEmpty else { return nil }

            let energies = energyService.calculateEnergy(from: activities, startingAt: base)
            let impacts  = await energyService.calculateImpact(from: energies, using: rateService)

            guard let firstImpact = impacts.first else { return nil }
            
            return firstImpact

        case .failure(let error):
            
            return nil
        }
    }

    func getRenewable() async -> Double {
        return await energyService.fetchRenewablePercentage() ?? 0
    }

    func getSolarPeak() async -> Date? {
        let peak = await energyService.fetchSolarPeak()
        solarPeak = peak
        
        if let peak = peak {
            print("🌞 Minutes from now: \(Int(peak.timeIntervalSinceNow / 60))")
        }
        return peak
    }
}
