//
//  ScheduledActivity.swift
//  Rootine
//
//  Created by Jackson Sanders on 4/3/26.
//

import Foundation

// MARK: - Model

struct ScheduledActivity {
    let impact: ActivityImpact

    /// The hour slot this activity is assigned to (0–23, relative to baseDate's day)
    let scheduledHour: Int

    /// The concrete start time
    let scheduledDate: Date

    /// Why this slot was chosen
    let reason: SchedulingReason

    /// Whether this was flexible (rescheduled) or fixed (kept as-is)
    let wasRescheduled: Bool
}

struct SchedulingReason {
    let renewablePercentage: Double
    let carbonIntensity: Double
    let costPerKwh: Double
    let score: Double
    let label: String   // e.g. "Best renewable window", "Fixed time"
}

// MARK: - Slot scoring

/// One candidate hour slot across the 24-hour horizon, enriched with grid data.
private struct HourSlot {
    let hour: Int
    let date: Date
    let rate: TOURate?

    // Grid signals fetched async before scheduling
    var renewablePercentage: Double = 0
    var carbonIntensity: Double = 0

    /// Higher = better. Renewable % dominates, then carbon (inverted), then cost (inverted).
    func score(kWh: Double, rateRange: (min: Double, max: Double)?) -> Double {
        let costPerKwh = rate?.totalRate ?? 0.40   // fallback if DB miss
        let cost       = kWh * costPerKwh

        // Normalize each signal to ~0-1 range:
        //   renewable: 0–100 % → 0–1   (higher = better, weight 0.50)
        //   carbon:    0–500 g/kWh      (lower = better, weight 0.25)
        //   cost:      actual rate range (lower = better, weight 0.25)
        
        let renewableScore = (renewablePercentage / 100.0) * 0.50
        let carbonScore    = max(0, 1.0 - (carbonIntensity / 500.0)) * 0.25
        
        // Better cost normalization using actual LADWP rate range
        let costScore: Double
        if let range = rateRange, range.max > range.min {
            // Normalize based on actual rate spread
            // Base rates: ~$0.23 (base) to ~$0.31 (high peak)
            let normalizedCost = (costPerKwh - range.min) / (range.max - range.min)
            costScore = (1.0 - normalizedCost) * 0.25
        } else {
            // Fallback normalization
            costScore = max(0, 1.0 - (cost / (kWh * 0.50))) * 0.25
        }

        return renewableScore + carbonScore + costScore
    }

    func reason(kWh: Double, rateRange: (min: Double, max: Double)?) -> SchedulingReason {
        SchedulingReason(
            renewablePercentage: renewablePercentage,
            carbonIntensity: carbonIntensity,
            costPerKwh: rate?.totalRate ?? 0,
            score: score(kWh: kWh, rateRange: rateRange),
            label: renewablePercentage >= 60 ? "Best renewable window"
                 : renewablePercentage >= 40 ? "Good renewable window"
                 : "Lowest available cost"
        )
    }
}

// MARK: - Scheduler

/// Schedules activities over the next 24 hours from `baseDate`.
///
/// - Flexible activities are assigned the highest-scoring available hour slot.
/// - Non-flexible activities are pinned to their original time and scored informatively.
/// - Each hour slot can hold multiple activities (no exclusion).
///
/// Grid signals (renewable %, carbon intensity) are fetched once via `EnergyService`
/// and broadcast across all slots in the horizon.
@MainActor
func scheduleActivities(
    impacts: [ActivityImpact],
    baseDate: Date,
    energyService: EnergyService = EnergyService(),
    rateService: LADWPRateService = .shared
) async -> [ScheduledActivity] {

    // 1. Build 24 candidate hour slots
    var slots = buildHourSlots(from: baseDate, rateService: rateService)

    // Get rate range for better cost normalization
    let rateRange = rateService.rateRange(for: baseDate)
    let normalizedRateRange: (min: Double, max: Double)? = rateRange.map { (min: $0.cheapest, max: $0.mostExpensive) }
    if let range = rateRange {
        print("💰 Rate range: $\(String(format: "%.4f", range.cheapest)) - $\(String(format: "%.4f", range.mostExpensive))/kWh")
    }

    // 2. Fetch 24-hour carbon forecast from Electricity Maps API
    let forecast = await energyService.fetchCarbonForecast()
    
    // Fallback to current data + solar curve if forecast unavailable
    let carbonData = await energyService.fetchCarbonData()
    let fallbackRenewable = carbonData?.renewablePercentage ?? 30.0
    let fallbackCarbon = carbonData?.carbonIntensity ?? 300.0
    
    // Apply forecast data to each hour slot
    for i in slots.indices {
        let hour = slots[i].hour
        let rateInfo = slots[i].rate
        let rateDisplay = rateInfo != nil ? "$\(String(format: "%.4f", rateInfo!.totalRate))" : "N/A"
        
        if let hourlyData = forecast?[hour] {
            // Use real forecast data
            slots[i].renewablePercentage = hourlyData.renewablePercentage
            slots[i].carbonIntensity = hourlyData.carbonIntensity
            print("✅ Hour \(String(format: "%2d", hour)): \(String(format: "%5.1f", hourlyData.renewablePercentage))% renewable, \(String(format: "%3.0f", hourlyData.carbonIntensity)) g/kWh, \(rateDisplay)/kWh [\(rateInfo?.periodLabel ?? "?")]")
        } else {
            // Fallback: use solar curve estimation
            let solarBonus: Double
            if hour < 6 || hour > 18 {
                solarBonus = 0.0
            } else {
                let hoursFromNoon = abs(Double(hour) - 12.0)
                let normalizedDistance = hoursFromNoon / 6.0
                solarBonus = 25.0 * (1.0 - normalizedDistance * normalizedDistance)
            }
            
            slots[i].renewablePercentage = min(100, fallbackRenewable + solarBonus)
            slots[i].carbonIntensity = max(0, fallbackCarbon - (solarBonus * 2))
            print("⚠️ Hour \(String(format: "%2d", hour)): \(String(format: "%5.1f", slots[i].renewablePercentage))% renewable (fallback), \(rateDisplay)/kWh [\(rateInfo?.periodLabel ?? "?")]")
        }
    }
    
    print("🔍 Scheduling \(impacts.count) activities across best time slots...")
    print("📊 Weights: 50% renewable, 25% carbon, 25% cost")

    // 3. Schedule each activity
    var scheduled: [ScheduledActivity] = []

    for impact in impacts {
        let isFlexible = impact.activity.isFlexible ?? true

        if isFlexible {
            // Pick the best scoring slot and remove it so no two activities share an hour
            guard let bestIndex = slots.indices.max(by: {
                slots[$0].score(kWh: impact.kWh, rateRange: normalizedRateRange) < slots[$1].score(kWh: impact.kWh, rateRange: normalizedRateRange)
            }) else { continue }

            let best = slots[bestIndex]
            slots.remove(at: bestIndex)

            scheduled.append(ScheduledActivity(
                impact: impact,
                scheduledHour: best.hour,
                scheduledDate: best.date,
                reason: best.reason(kWh: impact.kWh, rateRange: normalizedRateRange),
                wasRescheduled: true
            ))

        } else {
            // Pin to original time, score it informatively
            let originalHour = Calendar.current.component(.hour, from: baseDate)
            let slot = slots.first(where: { $0.hour == originalHour }) ?? slots[0]

            scheduled.append(ScheduledActivity(
                impact: impact,
                scheduledHour: slot.hour,
                scheduledDate: slot.date,
                reason: SchedulingReason(
                    renewablePercentage: slot.renewablePercentage,
                    carbonIntensity: slot.carbonIntensity,
                    costPerKwh: slot.rate?.totalRate ?? 0,
                    score: slot.score(kWh: impact.kWh, rateRange: normalizedRateRange),
                    label: "Fixed time"
                ),
                wasRescheduled: false
            ))
        }
    }

    return scheduled.sorted { $0.scheduledHour < $1.scheduledHour }
}

// MARK: - Helpers

private func buildHourSlots(from base: Date, rateService: LADWPRateService) -> [HourSlot] {
    let cal = Calendar.current
    let startOfHour = cal.dateInterval(of: .hour, for: base)?.start ?? base

    return (0..<24).compactMap { offset -> HourSlot? in
        guard let slotDate = cal.date(byAdding: .hour, value: offset, to: startOfHour) else {
            return nil
        }
        let rate = rateService.rate(for: slotDate)
        let hour = cal.component(.hour, from: slotDate)
        return HourSlot(hour: hour, date: slotDate, rate: rate)
    }
}
