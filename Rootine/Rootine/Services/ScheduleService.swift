//
//  ScheduleService.swift
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
    let label: String
}

// MARK: - Slot scoring

private struct HourSlot {
    let hour: Int
    let date: Date
    let rate: TOURate?

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

@MainActor
func scheduleActivities(
    impacts: [ActivityImpact],
    baseDate: Date,
    energyService: EnergyService = EnergyService(),
    rateService: LADWPRateService = .shared
) async -> [ScheduledActivity] {

    var enrichedSlots = buildHourSlots(from: baseDate, rateService: rateService)

    // Tracks every hour that is fully or partially occupied by a previously assigned task.
    // A 2-hour task at hour 13 blocks both 13 and 14.
    var blockedHours = Set<Int>()

    /// Returns the hours spanned by a task starting at `startHour` with `durationMinutes`.
    /// e.g. startHour=13, duration=90 → [13, 14]  (spans into hour 14)
    func hoursSpanned(startHour: Int, durationMinutes: Double) -> [Int] {
        let hoursNeeded = Int(ceil(durationMinutes / 60.0))
        return (0..<hoursNeeded).map { startHour + $0 }
    }

    /// True only if every hour the task would occupy is free.
    func canFit(slot: HourSlot, durationMinutes: Double) -> Bool {
        let needed = hoursSpanned(startHour: slot.hour, durationMinutes: durationMinutes)
        return needed.allSatisfy { !blockedHours.contains($0) }
    }

    /// Marks all hours a task spans as blocked.
    func block(startHour: Int, durationMinutes: Double) {
        for h in hoursSpanned(startHour: startHour, durationMinutes: durationMinutes) {
            blockedHours.insert(h)
        }
    }

    // Rate range for cost normalization
    let rateRange = rateService.rateRange(for: baseDate)
    let normalizedRateRange: (min: Double, max: Double)? = rateRange.map { ($0.cheapest, $0.mostExpensive) }

    // Fetch grid data
    let forecast   = await energyService.fetchCarbonForecast()
    let carbonData = await energyService.fetchCarbonData()
    let fallbackRenewable = carbonData?.renewablePercentage ?? 30.0
    let fallbackCarbon    = carbonData?.carbonIntensity    ?? 300.0

    // Enrich slots with forecast or solar-curve fallback
    for i in enrichedSlots.indices {
        let hour     = enrichedSlots[i].hour
        let rateInfo = enrichedSlots[i].rate
        let rateDisplay = rateInfo.map { "$\(String(format: "%.4f", $0.totalRate))" } ?? "N/A"

        if let hourlyData = forecast?[hour] {
            enrichedSlots[i].renewablePercentage = hourlyData.renewablePercentage
            enrichedSlots[i].carbonIntensity     = hourlyData.carbonIntensity
        } else {
            let solarBonus: Double
            if hour >= 6 && hour <= 18 {
                let hoursFromNoon = abs(Double(hour) - 12.0)
                solarBonus = 25.0 * (1.0 - (hoursFromNoon / 6.0) * (hoursFromNoon / 6.0))
            } else {
                solarBonus = 0.0
            }
            enrichedSlots[i].renewablePercentage = min(100, fallbackRenewable + solarBonus)
            enrichedSlots[i].carbonIntensity     = max(0,   fallbackCarbon    - solarBonus * 2)
        }
    }


    let energyImpacts    = impacts.filter { $0.kWh >  0.01 }.sorted { $0.kWh > $1.kWh }
    let nonEnergyImpacts = impacts.filter { $0.kWh <= 0.01 }

    struct Assignment {
        let impact: ActivityImpact
        let slot: HourSlot
        let wasRescheduled: Bool
    }
    var assignments: [Assignment] = []

    // Flexible energy tasks → best slot where the full duration fits
    for impact in energyImpacts {
        let duration = impact.activity.duration ?? 60.0

        if impact.activity.isFlexible {
            guard let best = enrichedSlots
                .filter({ canFit(slot: $0, durationMinutes: duration) })
                .max(by: {
                    $0.score(kWh: impact.kWh, rateRange: normalizedRateRange) <
                    $1.score(kWh: impact.kWh, rateRange: normalizedRateRange)
                })
            else {
                continue
            }
            block(startHour: best.hour, durationMinutes: duration)
            assignments.append(Assignment(impact: impact, slot: best, wasRescheduled: true))

        } else {
            // Fixed: pin to baseDate's hour if the duration fits from there
            let fixedHour = Calendar.current.component(.hour, from: baseDate)
            guard let fixed = enrichedSlots.first(where: { $0.hour == fixedHour }),
                  canFit(slot: fixed, durationMinutes: duration)
            else {
                continue
            }
            block(startHour: fixedHour, durationMinutes: duration)
            assignments.append(Assignment(impact: impact, slot: fixed, wasRescheduled: false))
        }
    }

    // Non-energy tasks → worst slot where they fit (duration usually short, but still respected)
    for impact in nonEnergyImpacts {
        let duration = impact.activity.duration ?? 60.0

        guard let worst = enrichedSlots
            .filter({ canFit(slot: $0, durationMinutes: duration) })
            .min(by: {
                $0.score(kWh: 0.01, rateRange: normalizedRateRange) <
                $1.score(kWh: 0.01, rateRange: normalizedRateRange)
            })
        else {
            continue
        }
        block(startHour: worst.hour, durationMinutes: duration)
        assignments.append(Assignment(impact: impact, slot: worst, wasRescheduled: true))
    }

    // Rebuild ActivityImpact with cost + carbon recalculated at the actual scheduled hour
    let carbonIntensityFallback = carbonData?.carbonIntensity ?? 0

    let scheduled: [ScheduledActivity] = assignments.map { assignment in
        let scheduledDate = assignment.slot.date
        let kWh           = assignment.impact.kWh

        let cost = rateService.estimatedCost(kwh: kWh, for: scheduledDate) ?? (kWh * 0.31)

        let carbonIntensity = forecast?[assignment.slot.hour]?.carbonIntensity ?? carbonIntensityFallback
        let carbon = kWh * carbonIntensity

        let multiplier: Double
        switch assignment.impact.activity.type {
        case "appliance": multiplier = 1.5
        case "gaming":    multiplier = 1.3
        case "compute":   multiplier = 1.2
        case "streaming": multiplier = 1.0
        case "charging":  multiplier = 0.8
        case "idle":      multiplier = 0.3
        default:          multiplier = 1.0
        }

        let updatedImpact = ActivityImpact(
            activity:      assignment.impact.activity,
            kWh:           kWh,
            carbon:        carbon,
            cost:          cost,
            impactScore:   carbon * multiplier,
            originalInput: assignment.impact.originalInput
        )

        return ScheduledActivity(
            impact:         updatedImpact,
            scheduledHour:  assignment.slot.hour,
            scheduledDate:  scheduledDate,
            reason:         assignment.slot.reason(kWh: kWh, rateRange: normalizedRateRange),
            wasRescheduled: assignment.wasRescheduled
        )
    }

    return scheduled.sorted { $0.scheduledHour < $1.scheduledHour }
}

// MARK: - Helpers

private func buildHourSlots(from base: Date, rateService: LADWPRateService) -> [HourSlot] {
    let cal      = Calendar.current
    let endOfDay = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: base)!)

    return (0..<24).compactMap { offset -> HourSlot? in
        guard let slotDate = cal.date(byAdding: .hour, value: offset, to: base),
              slotDate >= base,
              slotDate < endOfDay
        else { return nil }

        let hour = cal.component(.hour, from: slotDate)
        let rate = rateService.rate(for: slotDate)
        return HourSlot(hour: hour, date: slotDate, rate: rate)
    }
}
