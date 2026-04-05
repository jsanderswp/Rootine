import SQLite
import Foundation

// MARK: - Model

struct TOURate {
    let periodName: String  // "high_peak", "low_peak", "base"
    let season: String      // "summer", "winter"
    let isWeekend: Bool
    let hourStart: Int
    let hourEnd: Int
    let baseRate: Double
    let adjustment: Double

    var totalRate: Double { baseRate + adjustment }

    var periodLabel: String {
        switch periodName {
        case "high_peak": return "High Peak"
        case "low_peak":  return "Low Peak"
        default:          return "Base"
        }
    }
}

// MARK: - Service

class LADWPRateService {
    
    static let shared = LADWPRateService()
    
    private var db: Connection?
    
    private let tbl          = Table("tou_periods")
    private let colPeriod    = Expression<String>("period_name")
    private let colSeason    = Expression<String>("season")
    private let colWeekend   = Expression<Int>("is_weekend")
    private let colHourStart = Expression<Int>("hour_start")
    private let colHourEnd   = Expression<Int>("hour_end")
    private let colBase      = Expression<Double>("base_rate")
    private let colAdj       = Expression<Double>("adjustment")
    
    private init() {
        setupDatabase()
    }
    
    // MARK: - Setup
    
    private func setupDatabase() {
        let fileURL = databaseURL()
        let alreadyExists = FileManager.default.fileExists(atPath: fileURL.path)
        
        do {
            db = try Connection(fileURL.path)
            
            if !alreadyExists {
                try createSchema()
                try seedData()
            }
        } catch {
            print("DB Error: \(error)")
        }
    }
    
    private func databaseURL() -> URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ladwp_rates.sqlite")
    }
    
    private func createSchema() throws {
        guard let db else { return }
        
        try db.execute("""
        CREATE TABLE IF NOT EXISTS tou_periods (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            period_name TEXT NOT NULL,
            season TEXT NOT NULL,
            is_weekend INTEGER NOT NULL,
            hour_start INTEGER NOT NULL,
            hour_end INTEGER NOT NULL,
            base_rate REAL NOT NULL,
            adjustment REAL NOT NULL
        );
        
        CREATE TABLE IF NOT EXISTS rate_meta (
            key TEXT PRIMARY KEY,
            value TEXT
        );
        """)
    }
    
    private func seedData() throws {
        guard let db else { return }
        
        try db.execute("""
        INSERT INTO tou_periods
        (period_name, season, is_weekend, hour_start, hour_end, base_rate, adjustment)
        VALUES
        ('high_peak', 'summer', 0, 13, 16, 0.15858, 0.15623),
        ('low_peak',  'summer', 0, 10, 12, 0.10018, 0.15623),
        ('low_peak',  'summer', 0, 17, 19, 0.10018, 0.15623),
        ('base',      'summer', 0,  0,  9, 0.07274, 0.15623),
        ('base',      'summer', 0, 20, 23, 0.07274, 0.15623),
        ('base',      'summer', 1,  0, 23, 0.07274, 0.15623),
        
        ('high_peak', 'winter', 0, 13, 16, 0.15858, 0.17164),
        ('low_peak',  'winter', 0, 10, 12, 0.10018, 0.15154),
        ('low_peak',  'winter', 0, 17, 19, 0.10018, 0.15154),
        ('base',      'winter', 0,  0,  9, 0.07664, 0.15154),
        ('base',      'winter', 0, 20, 23, 0.07664, 0.15154),
        ('base',      'winter', 1,  0, 23, 0.07664, 0.15154);
        """)
    }
    
    // MARK: - Core Logic
    
    private func matches(hour: Int, start: Int, end: Int) -> Bool {
        if start <= end {
            return hour >= start && hour <= end
        } else {
            // overnight range (e.g. 20 → 9)
            return hour >= start || hour <= end
        }
    }
    
    // MARK: - Public API
    
    func rate(for date: Date) -> TOURate? {
        let cal = Calendar.current
        
        let hour = cal.component(.hour, from: date)
        let month = cal.component(.month, from: date)
        let weekday = cal.component(.weekday, from: date)
        
        let isWeekend = (weekday == 1 || weekday == 7)
        let season = (6...9).contains(month) ? "summer" : "winter"
        
        return rate(hour: hour, season: season, isWeekend: isWeekend)
    }
    
    func rate(hour: Int, season: String, isWeekend: Bool) -> TOURate? {
        guard let db else { return nil }
        
        do {
            let allRates = try db.prepare(tbl).map { row in
                TOURate(
                    periodName: row[colPeriod],
                    season: row[colSeason],
                    isWeekend: row[colWeekend] == 1,
                    hourStart: row[colHourStart],
                    hourEnd: row[colHourEnd],
                    baseRate: row[colBase],
                    adjustment: row[colAdj]
                )
            }
            
            return allRates.first(where: {
                $0.season == season &&
                $0.isWeekend == isWeekend &&
                matches(hour: hour, start: $0.hourStart, end: $0.hourEnd)
            })
            
        } catch {
            return nil
        }
    }
    
    func currentRate() -> TOURate? {
        rate(for: Date())
    }
    
    func estimatedCost(kwh: Double, for date: Date = .now) -> Double? {
        guard let r = rate(for: date) else { return nil }
        return kwh * r.totalRate
    }
    
    func allRates() -> [TOURate] {
        guard let db else { return [] }
        
        do {
            return try db.prepare(tbl).map { row in
                TOURate(
                    periodName: row[colPeriod],
                    season: row[colSeason],
                    isWeekend: row[colWeekend] == 1,
                    hourStart: row[colHourStart],
                    hourEnd: row[colHourEnd],
                    baseRate: row[colBase],
                    adjustment: row[colAdj]
                )
            }
        } catch {
            return []
        }
    }
    
    func cheapestHours(season: String, isWeekend: Bool) -> [(hour: Int, rate: Double)] {
        return (0...23).compactMap { hour in
            guard let r = rate(hour: hour, season: season, isWeekend: isWeekend) else {
                return nil
            }
            return (hour, r.totalRate)
        }
        .sorted { $0.rate < $1.rate }
    }
    
    /// Get 24-hour rate forecast for the given date
    /// Returns dictionary mapping hour (0-23) to the total rate
    func rateForecast(for baseDate: Date = Date()) -> [Int: Double] {
        let cal = Calendar.current
        var forecast: [Int: Double] = [:]
        
        // Build 24 hours starting from baseDate
        for offset in 0..<24 {
            guard let slotDate = cal.date(byAdding: .hour, value: offset, to: baseDate) else {
                continue
            }
            
            let hour = cal.component(.hour, from: slotDate)
            if let rateData = rate(for: slotDate) {
                forecast[hour] = rateData.totalRate
            }
        }
        
        return forecast
    }
    
    /// Get the cheapest and most expensive rates for analysis
    func rateRange(for baseDate: Date = Date()) -> (cheapest: Double, mostExpensive: Double)? {
        let forecast = rateForecast(for: baseDate)
        guard !forecast.isEmpty else { return nil }
        
        let rates = Array(forecast.values)
        guard let min = rates.min(), let max = rates.max() else { return nil }
        
        return (min, max)
    }
}

