//
//  EnergyService.swift
//  Rootine
//
//  Created by Jackson Sanders on 4/3/26.
//

import Foundation

class EnergyService {

    private let apiKey: String = {
        Bundle.main.object(forInfoDictionaryKey: "ELECTRICITY_MAPS_API_KEY") as? String ?? ""
    }()
    
    func calculateEnergy(from activities: [Activity]) -> [ActivityEnergy] {
        var activityEnergies: [ActivityEnergy] = []
        for activity in activities {
            switch activity.type {
            case "streaming":
                activityEnergies.append(ActivityEnergy(activity: activity, kWh: (0.2 * activity.duration!)))

            case "compute":
                activityEnergies.append(ActivityEnergy(activity: activity, kWh: (0.5 * activity.duration!)))

            case "gaming":
                activityEnergies.append(ActivityEnergy(activity: activity, kWh: (0.4 * activity.duration!)))

            case "charging":
                activityEnergies.append(ActivityEnergy(activity: activity, kWh: (0.1 * activity.duration!)))

            case "appliance":
                activityEnergies.append(ActivityEnergy(activity: activity, kWh: (1.5 * activity.duration!)))

            case "idle":
                activityEnergies.append(ActivityEnergy(activity: activity, kWh: (0.05 * activity.duration!)))

            default:
                activityEnergies.append(ActivityEnergy(activity: activity, kWh: (0.2 * activity.duration!)))
            }
        }
        
        return activityEnergies
    }

    func fetchCarbonData() async -> CarbonResponse? {
        guard let url = URL(string:
        "https://api.electricitymap.org/v3/carbon-intensity/latest?zone=US-CAL-CISO"
        ) else { return nil }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "auth-token")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return try JSONDecoder().decode(CarbonResponse.self, from: data)
        } catch {
            print("Error:", error)
            return nil
        }
    }
    
    func fetchElectricityMix() async -> ElectricityMix? {
        guard let url = URL(string:
            "https://api.electricitymap.org/v3/power-breakdown/latest?zone=US-CAL-CISO"
        ) else { return nil }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "auth-token")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoded = try JSONDecoder().decode(PowerBreakdownResponse.self, from: data)
            return decoded.powerProductionBreakdown
        } catch {
            print("Error:", error)
            return nil
        }
    }

    func calculateImpact(from activityEnergies: [ActivityEnergy]) async -> [ActivityImpact] {
        
        let carbonData = await fetchCarbonData()
        let carbonIntensity = carbonData?.carbonIntensity ?? 0
        
        return activityEnergies.map { energy in
            
            let kWh = energy.kWh
            let cost = kWh * 0.30
            let carbon = kWh * carbonIntensity
            
            // weight importance (this is your "impact")
            let multiplier: Double
            
            switch energy.activity.type {
            case "appliance":
                multiplier = 1.5
            case "gaming":
                multiplier = 1.3
            case "compute":
                multiplier = 1.2
            case "streaming":
                multiplier = 1.0
            case "charging":
                multiplier = 0.8
            case "idle":
                multiplier = 0.3
            default:
                multiplier = 1.0
            }
            
            let impactScore = carbon * multiplier
            
            return ActivityImpact(
                activity: energy.activity,
                kWh: kWh,
                cost: cost,
                carbon: carbon,
                impactScore: impactScore
            )
        }
    }

    func calculateRenewablePercentage(from mix: ElectricityMix?) -> Double {
        guard let mix = mix else { return 0 }

        let renewable = mix.solar + mix.wind + mix.hydro

        let total =
            mix.solar +
            mix.wind +
            mix.hydro +
            mix.nuclear +
            mix.coal +
            mix.gas +
            mix.oil

        guard total > 0 else { return 0 }

        return (renewable / total) * 100
    }
    
    func aggregateEnergy(from impacts: [ActivityImpact]) async -> EnergyResult {
        
        let totalKWh = impacts.reduce(0) { $0 + $1.kWh }
        let totalCost = impacts.reduce(0) { $0 + $1.cost }
        let totalCarbon = impacts.reduce(0) { $0 + $1.carbon }
        
        let carbonData = await fetchCarbonData()
        let mix = await fetchElectricityMix()
        
        let renewablePercentage =
            carbonData?.renewablePercentage ??
            calculateRenewablePercentage(from: mix)
        
        return EnergyResult(
            totalKWh: totalKWh,
            cost: totalCost,
            carbon: totalCarbon,
            renewablePercentage: renewablePercentage
        )
    }
}



struct ActivityEnergy {
    let activity: Activity
    let kWh: Double
}

struct ElectricityMix: Codable {
    let solar: Double
    let wind: Double
    let hydro: Double
    let nuclear: Double
    let coal: Double
    let gas: Double
    let oil: Double
}

struct PowerBreakdownResponse: Codable {
    let powerProductionBreakdown: ElectricityMix
}

struct CarbonResponse: Codable {
    let carbonIntensity: Double
    let renewablePercentage: Double?
}

struct EnergyResult {
    let totalKWh: Double
    let cost: Double
    let carbon: Double
    let renewablePercentage: Double
}

struct ActivityImpact {
    let activity: Activity
    let kWh: Double
    let cost: Double
    let carbon: Double
    let impactScore: Double
}
