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
 
    // MARK: - Energy calculation
 
    func calculateEnergy(from activities: [Activity], startingAt base: Date = .now) -> [ActivityEnergy] {
        var result: [ActivityEnergy] = []
        var cursor = base
 
        for activity in activities {
            let durationMinutes = activity.duration ?? 60.0   // Default to 60 minutes if not specified
            let durationHours   = durationMinutes / 60.0
 
            let kWh: Double
            switch activity.type {
            case "streaming":  kWh = 0.20 * durationHours
            case "compute":    kWh = 0.50 * durationHours
            case "gaming":     kWh = 0.40 * durationHours
            case "charging":   kWh = 0.10 * durationHours
            case "appliance":  kWh = 1.50 * durationHours
            case "idle":       kWh = 0.05 * durationHours
            default:           kWh = 0.20 * durationHours
            }
 
            result.append(ActivityEnergy(activity: activity, kWh: kWh, date: cursor))
 
            // Advance the cursor so activities don't all overlap at the same timestamp
            cursor = cursor.addingTimeInterval(durationMinutes * 60)
        }
 
        return result
    }
 
    // MARK: - Impact calculation (uses pre-fetched LADWP rates)
 
    /// Preferred entry point called from DataController.
    /// Accepts rates from LADWPRateService so we don't re-fetch per-activity.
    func calculateImpact(
        from activityEnergies: [ActivityEnergy],
        using rates: LADWPRateService = .shared,
        originalInput: String? = nil
    ) async -> [ActivityImpact] {
 
        let carbonData      = await fetchCarbonData()
        let carbonIntensity = carbonData?.carbonIntensity ?? 0
 
        return activityEnergies.map { energy in
            let kWh    = energy.kWh
            let carbon = kWh * carbonIntensity
 
            // Cost via LADWP time-of-use rate at the activity's scheduled time
            let cost = rates.estimatedCost(kwh: kWh, for: energy.date) ?? (kWh * 0.31)
 
            // Activity-type multiplier for impact weighting
            let multiplier: Double
            switch energy.activity.type {
            case "appliance":  multiplier = 1.5
            case "gaming":     multiplier = 1.3
            case "compute":    multiplier = 1.2
            case "streaming":  multiplier = 1.0
            case "charging":   multiplier = 0.8
            case "idle":       multiplier = 0.3
            default:           multiplier = 1.0
            }
 
            let impactScore = carbon * multiplier
 
            return ActivityImpact(
                activity:    energy.activity,
                kWh:         kWh,
                carbon:      carbon,
                cost:        cost,
                impactScore: impactScore,
                originalInput: originalInput
            )
        }
    }
 
    // MARK: - Grid data fetching
 
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
 
    func fetchSolarPeak() async -> Date? {
        guard let url = URL(string: "https://api.electricitymap.org/v3/carbon-intensity/forecast?zone=US-CAL-CISO") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "auth-token")
        request.timeoutInterval = 15.0

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoded = try JSONDecoder().decode(CarbonForecastResponse.self, from: data)

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            let calendar = Calendar.current

            // Find the lowest carbon intensity point between 8am and 6pm (solar hours)
            let peakPoint = decoded.forecast
                .compactMap { point -> (date: Date, carbon: Double)? in
                    guard let date = formatter.date(from: point.datetime) else { return nil }
                    let hour = calendar.component(.hour, from: date)
                    guard hour >= 8 && hour <= 18 else { return nil }
                    return (date, point.carbonIntensity)
                }
                .min(by: { $0.carbon < $1.carbon })

            return peakPoint?.date

        } catch {
            return nil
        }
    }
    
    /// Fetch 24-hour carbon intensity forecast
    /// Returns a dictionary mapping hour (0-23) to carbon intensity and renewable percentage
    func fetchCarbonForecast() async -> [Int: (carbonIntensity: Double, renewablePercentage: Double)]? {
        guard let url = URL(string: "https://api.electricitymap.org/v3/carbon-intensity/forecast?zone=US-CAL-CISO") else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "auth-token")
        request.timeoutInterval = 15.0  // 15 second timeout
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Check HTTP response
            if let httpResponse = response as? HTTPURLResponse {
                guard (200...299).contains(httpResponse.statusCode) else {
                    return nil
                }
            }
            
            // Debug: Print raw response
            if let jsonString = String(data: data, encoding: .utf8) {
                print("📄 Raw API response: \(jsonString.prefix(500))...")
            }
            
            let decoded = try JSONDecoder().decode(CarbonForecastResponse.self, from: data)
            
            var hourlyData: [Int: (Double, Double)] = [:]
            let calendar = Calendar.current
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            
            for (index, point) in decoded.forecast.enumerated() {
                guard let date = formatter.date(from: point.datetime) else {
                    continue
                }
                let hour = calendar.component(.hour, from: date)
                
                let renewable = point.renewablePercentage ?? 0
                hourlyData[hour] = (
                    point.carbonIntensity,
                    renewable
                )
                
            }
            
            return hourlyData
        } catch let error as NSError {
            return nil
        } catch {
            return nil
        }
    }
    
    /// Fetch 24-hour power breakdown forecast (includes detailed renewable mix)
    /// Returns a dictionary mapping hour (0-23) to renewable percentage calculated from the mix
    func fetchPowerBreakdownForecast() async -> [Int: (renewablePercentage: Double, mix: ElectricityMix)]? {
        guard let url = URL(string: "https://api.electricitymap.org/v3/power-breakdown/forecast?zone=US-CAL-CISO") else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "auth-token")
        request.timeoutInterval = 15.0
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Check HTTP response
            if let httpResponse = response as? HTTPURLResponse {
                guard (200...299).contains(httpResponse.statusCode) else {
                    return nil
                }
            }
            
            
            let decoded = try JSONDecoder().decode(PowerBreakdownForecastResponse.self, from: data)
            
            var hourlyData: [Int: (Double, ElectricityMix)] = [:]
            let calendar = Calendar.current
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            
            for (index, point) in decoded.data.enumerated() {
                guard let date = formatter.date(from: point.datetime) else {
                    continue
                }
                let hour = calendar.component(.hour, from: date)
                
                let mix = point.powerProductionBreakdown
                let renewablePct = calculateRenewablePercentage(from: mix)
                
                
                hourlyData[hour] = (renewablePct, mix)
            }
            
            return hourlyData
        } catch {
            return nil
        }
    }
    
    func fetchRenewablePercentage() async -> Double? {
            guard let url = URL(string:
                "https://api.electricitymap.org/v3/renewable-energy/latest?zone=US-CAL-CISO"
            ) else { return nil }

            var request = URLRequest(url: url)
            request.setValue(apiKey, forHTTPHeaderField: "auth-token")
            request.timeoutInterval = 15.0
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                // Check HTTP response
                if let httpResponse = response as? HTTPURLResponse {
                    guard (200...299).contains(httpResponse.statusCode) else {
                        return nil
                    }
                }
                
                
                let decoded = try JSONDecoder().decode(RenewablePercentageResponse.self, from: data)
                return decoded.value
            } catch {
                return nil
            }
        }
    
    /// Fetch 24-hour renewable energy percentage forecast
    /// Returns a dictionary mapping hour (0-23) to renewable percentage
    func fetchRenewableEnergyForecast() async -> [Int: Double]? {
        guard let url = URL(string: "https://api.electricitymap.org/v3/renewable-energy/forecast?zone=US-CAL-CISO") else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "auth-token")
        request.timeoutInterval = 15.0
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Check HTTP response
            if let httpResponse = response as? HTTPURLResponse {
                guard (200...299).contains(httpResponse.statusCode) else {
                    return nil
                }
            }
            
            
            let decoded = try JSONDecoder().decode(RenewableEnergyForecastResponse.self, from: data)

            
            var hourlyData: [Int: Double] = [:]
            let calendar = Calendar.current
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            
            for (index, point) in decoded.data.enumerated() {
                guard let date = formatter.date(from: point.datetime) else {
                    continue
                }
                let hour = calendar.component(.hour, from: date)
                
                hourlyData[hour] = point.value
                
            }
            
            return hourlyData
        } catch let error as NSError {
            return nil
        } catch {
            return nil
        }
    }

    // MARK: - Helpers
 
    func calculateRenewablePercentage(from mix: ElectricityMix?) -> Double {
        guard let mix else { return 0 }
 
        let renewable = mix.solar + mix.wind + mix.hydro
        let total     = renewable + mix.nuclear + mix.coal + mix.gas + mix.oil
 
        guard total > 0 else { return 0 }
        return (renewable / total) * 100
    }
 
    func aggregateEnergy(from impacts: [ActivityImpact]) async -> EnergyResult {
        let totalKWh   = impacts.reduce(0) { $0 + $1.kWh }
        let totalCarbon = impacts.reduce(0) { $0 + $1.carbon }
 
        let carbonData         = await fetchCarbonData()
        let mix                = await fetchElectricityMix()
        let renewablePercentage = carbonData?.renewablePercentage
            ?? calculateRenewablePercentage(from: mix)
 
        return EnergyResult(
            totalKWh: totalKWh,
            carbon: totalCarbon,
            renewablePercentage: renewablePercentage
        )
    }
}
 
// MARK: - Models
 
struct RenewablePercentageResponse: Codable {
    let zone: String
    let datetime: String
    let value: Double
    let unit: String
    let isEstimated: Bool
}

struct ActivityEnergy {
    let activity: Activity
    let kWh: Double
    let date: Date          // ← added: when this activity occurs
}
 
struct ActivityImpact {
    let activity:    Activity
    let kWh:         Double
    let carbon:      Double
    let cost:        Double   // ← added: LADWP cost in dollars
    let impactScore: Double
    let originalInput: String?  // ← Track original user input
}
 
struct ElectricityMix: Codable {
    let solar:   Double
    let wind:    Double
    let hydro:   Double
    let nuclear: Double
    let coal:    Double
    let gas:     Double
    let oil:     Double
}
 
struct PowerBreakdownResponse: Codable {
    let powerProductionBreakdown: ElectricityMix
}
 
struct CarbonResponse: Codable {
    let carbonIntensity:      Double
    let renewablePercentage:  Double?
}

struct CarbonForecastResponse: Codable {
    let forecast: [CarbonForecastPoint]
}

struct CarbonForecastPoint: Codable {
    let datetime: String
    let carbonIntensity: Double
    let renewablePercentage: Double?
}
 
struct EnergyResult {
    let totalKWh:           Double
    let carbon:             Double
    let renewablePercentage: Double
}

struct PowerBreakdownForecastResponse: Codable {
    let data: [PowerBreakdownForecastPoint]
}

struct PowerBreakdownForecastPoint: Codable {
    let datetime: String
    let powerProductionBreakdown: ElectricityMix
}
struct RenewableEnergyForecastResponse: Codable {
    let data: [RenewableEnergyForecastPoint]
}

struct RenewableEnergyForecastPoint: Codable {
    let zone: String
    let datetime: String
    let value: Double
    let unit: String
    let isEstimated: Bool
}

