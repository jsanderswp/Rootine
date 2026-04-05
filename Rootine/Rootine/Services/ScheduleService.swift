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
        let costPerKwh = rate?.totalRate ?? 0.40
        let cost       = kWh * costPerKwh

        let renewableScore = (renewablePercentage / 100.0) * 0.50
        let carbonScore    = max(0, 1.0 - (carbonIntensity / 500.0)) * 0.25

        let costScore: Double
        if let range = rateRange, range.max > range.min {
            let normalizedCost = (costPerKwh - range.min) / (range.max - range.min)
            costScore = (1.0 - normalizedCost) * 0.25
        } else {
            costScore = max(0, 1.0 - (cost / (kWh * 0.50))) * 0.25
        }

        let baseScore = renewableScore + carbonScore + costScore

        // Amplify score for heavier tasks so they compete harder for the best slots
        let kWhMultiplier = 1.0 + log(max(1.0, kWh * 10))

        return baseScore * kWhMultiplier
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
/// - Energy-heavy flexible activities are assigned the highest-scoring available hour slot.
/// - Non-energy tasks are assigned the lowest-scoring remaining slots.
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
    var occupiedRanges: [(start: Date, end: Date)] = []

    func isSlotAvailable(_ slot: HourSlot, duration: Double) -> Bool {
        let slotEnd = slot.date.addingTimeInterval(duration * 60)
        return !occupiedRanges.contains(where: { range in
            slot.date < range.end && slotEnd > range.start
        })
    }

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
            slots[i].renewablePercentage = hourlyData.renewablePercentage
            slots[i].carbonIntensity = hourlyData.carbonIntensity
            print("✅ Hour \(String(format: "%2d", hour)): \(String(format: "%5.1f", hourlyData.renewablePercentage))% renewable, \(String(format: "%3.0f", hourlyData.carbonIntensity)) g/kWh, \(rateDisplay)/kWh [\(rateInfo?.periodLabel ?? "?")]")
        } else {
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

    // 3. Split into energy and non-energy tasks
    let energyImpacts = impacts.filter { $0.kWh > 0.01 }.sorted { $0.kWh > $1.kWh }
    let nonEnergyImpacts = impacts.filter { $0.kWh <= 0.01 }

    var scheduled: [ScheduledActivity] = []

    // 4. Schedule energy tasks first into best available slots
    for impact in energyImpacts {
        let isFlexible = impact.activity.isFlexible ?? true

        if isFlexible {
            guard let bestIndex = slots.indices.filter({
                isSlotAvailable(slots[$0], duration: impact.activity.duration ?? 60)
            }).max(by: {
                slots[$0].score(kWh: impact.kWh, rateRange: normalizedRateRange) < slots[$1].score(kWh: impact.kWh, rateRange: normalizedRateRange)
            }) else { continue }

            let best = slots[bestIndex]
            slots.remove(at: bestIndex)

            let duration = impact.activity.duration ?? 60
            occupiedRanges.append((start: best.date, end: best.date.addingTimeInterval(duration * 60)))

            scheduled.append(ScheduledActivity(
                impact: impact,
                scheduledHour: best.hour,
                scheduledDate: best.date,
                reason: best.reason(kWh: impact.kWh, rateRange: normalizedRateRange),
                wasRescheduled: true
            ))

        } else {
            let originalHour = Calendar.current.component(.hour, from: baseDate)
            guard let slotIndex = slots.firstIndex(where: { $0.hour == originalHour }) else { continue }
            let slot = slots[slotIndex]
            slots.remove(at: slotIndex)

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

    // 5. Schedule non-energy tasks into worst remaining slots
    for impact in nonEnergyImpacts {
        guard let worstIndex = slots.indices.filter({
            isSlotAvailable(slots[$0], duration: impact.activity.duration ?? 60)
        }).min(by: {
            slots[$0].score(kWh: 0.01, rateRange: normalizedRateRange) < slots[$1].score(kWh: 0.01, rateRange: normalizedRateRange)
        }) else { continue }

        let worst = slots[worstIndex]
        slots.remove(at: worstIndex)

        let duration = impact.activity.duration ?? 60
        occupiedRanges.append((start: worst.date, end: worst.date.addingTimeInterval(duration * 60)))

        scheduled.append(ScheduledActivity(
            impact: impact,
            scheduledHour: worst.hour,
            scheduledDate: worst.date,
            reason: worst.reason(kWh: impact.kWh, rateRange: normalizedRateRange),
            wasRescheduled: true
        ))
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

        guard slotDate >= base else { return nil }

        let endOfDay = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: base)!)
        guard slotDate < endOfDay else { return nil }

        let rate = rateService.rate(for: slotDate)
        let hour = cal.component(.hour, from: slotDate)
        return HourSlot(hour: hour, date: slotDate, rate: rate)
    }
}
