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
    //var scheduledActivities: [ScheduledActivity]?
    var baseDate: Date?

    private let geminiService = GeminiService()
    private let energyService = EnergyService()
    private let rateService   = LADWPRateService.shared

    var solarPeak: Date? = nil
    
    var totalCO2Saved: Float = 0.0

    func calculateCO2Savings(schedule: [ScheduledActivity], taskMap: [String: UserTask]) async {
        guard let carbonForecast = await energyService.fetchCarbonForecast() else { return }

        let calendar = Calendar.current
        var totalSavings: Double = 0

        for scheduled in schedule {
            guard let originalInput = scheduled.impact.originalInput,
                  let task = taskMap[originalInput],
                  let originalTime = task.originalTimestamp else { continue }

            let originalHour = calendar.component(.hour, from: originalTime)
            let optimizedHour = calendar.component(.hour, from: scheduled.scheduledDate)

            let originalCarbon = carbonForecast[originalHour]?.carbonIntensity ?? 0
            let optimizedCarbon = carbonForecast[optimizedHour]?.carbonIntensity ?? 0

            let savingsKg = (originalCarbon - optimizedCarbon) * scheduled.impact.kWh / 1000.0
            totalSavings += savingsKg
        }

        totalCO2Saved = Float(totalSavings)
    }
    
    var currentTask: Task<Void, Never>?

    func processTasks(_ inputs: [String]) async -> [ScheduledActivity]{
        let now = baseDate ?? Date()
        let currentHourStart = Calendar.current.dateInterval(of: .hour, for: now)!.start
        let minutes = Calendar.current.component(.minute, from: now)
        let base = minutes >= 30
            ? Calendar.current.date(byAdding: .hour, value: 1, to: currentHourStart)!
            : currentHourStart
        var impacts: [ActivityImpact] = []

        for input in inputs {
            let result = await geminiService.parseActivities(input)

            switch result {
            case .success(let activities):

                // 1. Raw kWh per activity, stamped with sequential start times
                let energies = energyService.calculateEnergy(from: activities, startingAt: base)

                // 2. Carbon + LADWP cost + impact score (with original input for tracking)
                let activityImpacts = await energyService.calculateImpact(
                    from: energies,
                    using: rateService,
                    originalInput: input
                )

                impacts.append(contentsOf: activityImpacts)

            case .failure(let error):
                print("Gemini error:", error)
            }
        }

        // 3. Schedule flexible activities into the best 24h grid windows
        let scheduled = await scheduleActivities(
            impacts: impacts,
            baseDate: base,
            energyService: energyService,
            rateService: rateService
        )

        self.activityImpacts     = impacts
        //self.scheduledActivities = scheduled
        return scheduled
    }
    
    func processTask(_ input: String) async -> ActivityImpact? {
        let now = baseDate ?? Date()
        let currentHourStart = Calendar.current.dateInterval(of: .hour, for: now)!.start
        let minutes = Calendar.current.component(.minute, from: now)

        let base = minutes >= 30
            ? Calendar.current.date(byAdding: .hour, value: 1, to: currentHourStart)!
            : currentHourStart

        print("🔍 DataController: Processing task: \(input)")
        let result = await geminiService.parseActivities(input)

        switch result {
        case .success(let activities):
            print("🔍 DataController: Parsed \(activities.count) activities")
            for (i, activity) in activities.enumerated() {
                print("🔍 DataController: Activity \(i): \(activity.activity), type: \(activity.type), duration: \(activity.duration ?? -1)")
            }
            
            guard !activities.isEmpty else {
                print("🔍 DataController: No activities parsed from input")
                return nil
            }

            // 1. Raw kWh per activity, stamped with sequential start times
            let energies = energyService.calculateEnergy(from: activities, startingAt: base)
            print("🔍 DataController: Calculated \(energies.count) energy values")
            for (i, energy) in energies.enumerated() {
                print("🔍 DataController: Energy \(i): kWh = \(energy.kWh)")
            }

            // 2. Carbon + LADWP cost + impact score
            let impacts = await energyService.calculateImpact(
                from: energies,
                using: rateService
            )
            print("🔍 DataController: Calculated \(impacts.count) impacts")
            
            guard let firstImpact = impacts.first else {
                print("🔍 DataController: No impacts calculated")
                return nil
            }
            
            print("🔍 DataController: Returning impact with kWh = \(firstImpact.kWh)")
            return firstImpact

        case .failure(let error):
            print("🔍 DataController: Gemini error: \(error)")
            return nil
        }
    }
    
    func getRenewable () async -> Double {
        let percentage = await energyService.fetchRenewablePercentage()!
        return percentage
    }
    
    func getSolarPeak() async -> Date? {
        let peak = await energyService.fetchSolarPeak()
        solarPeak = peak
        print("🌞 Solar peak: \(String(describing: peak))")
        if let peak = peak {
            print("🌞 Minutes from now: \(Int(peak.timeIntervalSinceNow / 60))")
        }
        return peak
    }
}
