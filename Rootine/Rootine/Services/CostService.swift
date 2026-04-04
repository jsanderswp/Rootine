//
//  CostService.swift
//  Rootine
//
//  Created by Jackson Sanders on 4/4/26.
//

import Foundation

class CostService {
    
    private let baseURL = "https://api.openei.org/utility_rates"
    private let apiKey: String = {
        Bundle.main.object(forInfoDictionaryKey: "OPENEI_API_KEY") as? String ?? ""
    }()
    
    func fetchHourlyPrices() async -> [HourlyPrice]? {
        guard let url = URL(string: "\(baseURL)?api_key=\(apiKey)&format=json") else {
            return nil
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            
            let decoded = try JSONDecoder().decode(OpenEIResponse.self, from: data)
            
            guard let plan = decoded.items.first else { return nil }
            
            return buildHourlyPrices(from: plan)
            
        } catch {
            print("CostService error:", error)
            return nil
        }
    }
    
    func buildHourlyPrices(from plan: RatePlan) -> [HourlyPrice] {
            
        let isWeekend = Calendar.current.isDateInWeekend(Date())
            
        let schedule = isWeekend
            ? plan.energyweekendschedule?.first
            : plan.energyweekdayschedule?.first
            
        guard let schedule else { return [] }
            
        return schedule.enumerated().map { (hour, periodIndex) in
                
            let rate = plan.energyratestructure.indices.contains(periodIndex)
                ? plan.energyratestructure[periodIndex].first?.first?.rate ?? 0.0
                : 0.0
                
            return HourlyPrice(
                hour: hour,
                price: rate
            )
        }
    }
}

struct HourlyPrice: Codable {
    let hour: Int
    let price: Double
}

struct OpenEIResponse: Decodable {
    let items: [RatePlan]
}

struct RatePlan: Decodable {
    
    let energyweekdayschedule: [[Int]]?
    let energyweekendschedule: [[Int]]?
    
    let energyratestructure: [[[Rate]]]
    
    enum CodingKeys: String, CodingKey {
        case energyweekdayschedule
        case energyweekendschedule
        case energyratestructure
    }
}

struct Rate: Decodable {
    let rate: Double?
}
