//
//  ScheduleView.swift
//  Rootine
//
//  Created by Jackson Sanders on 4/3/26.
//

import SwiftUI
import SwiftData
import Foundation


struct ScheduleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(DataController.self) private var dataController
    @Query private var optimizedTasks: [UserTask]
    @State private var taskNames: [String] = []
    @State private var hasScheduled: Bool = false
    @State var heavyCount: Int = 0
    @State var otherCount: Int = 0
    @State var cleanPercent: Int = 82
    @State var cleanWindowOpen: Int = 10
    @State var cleanWindowClose: Int = 1
    @State var times: [String] = ["6a", "8a", "10a", "12p", "2p", "4p", "6p", "8p", "10p", "12a"]
    @State var renewPercents: [Int] = [25, 30, 55, 73, 89, 61, 49, 20, 18, 27]
    @State var currHour: Int = Calendar.current.component(.hour, from: Date())%2 == 0 ? Calendar.current.component(.hour, from: Date()) : Calendar.current.component(.hour, from: Date())-1
    @State private var hasFetchedRenewables: Bool = false
    @State private var renewableForecast: [Int: Double] = [:]  // Store full forecast for task rows
    private let energyService = EnergyService()
    
    // Computed property for sorted tasks
    private var sortedTasks: [UserTask] {
        optimizedTasks.sorted { $0.timestamp < $1.timestamp }
    }
    
    // Formatted clean window times
    private var cleanWindowOpenFormatted: String {
        let hour = cleanWindowOpen % 12
        let displayHour = hour == 0 ? 12 : hour
        let period = cleanWindowOpen < 12 ? "AM" : "PM"
        return "\(displayHour) \(period)"
    }
    
    private var cleanWindowCloseFormatted: String {
        let hour = cleanWindowClose % 12
        let displayHour = hour == 0 ? 12 : hour
        let period = cleanWindowClose < 12 ? "AM" : "PM"
        return "\(displayHour) \(period)"
    }
    
    var body: some View {
        VStack(spacing: 0){
            VStack {
                HStack {
                    Text("Optimized Day")
                        .foregroundStyle(Color("BrightText"))
                        .font(.largeTitle)
                    Spacer()
                }
                HStack {
                    Text("Saving")
                        .foregroundStyle(Color("DarkText"))
                    + Text(" \(dataController.totalCO2Saved.formatted(.number.precision(.fractionLength(1)))) kg CO₂")
                        .foregroundStyle(Color("Secondary"))
                    + Text(" vs default timing")
                        .foregroundStyle(Color("DarkText"))
                    Spacer()
                }
            }
            .padding(.leading, 20)
            .padding(.bottom, 10)
            
            VStack {
                List {
                    HStack {
                        VStack {
                            Image(systemName: "circle.fill")
                                .foregroundStyle(Color("Secondary"))
                            Spacer()
                        }
                        VStack {
                            HStack {
                                Text("Clean window \(cleanWindowOpenFormatted) – \(cleanWindowCloseFormatted).")
                                    .foregroundStyle(Color("Secondary"))
                                Spacer()
                            }
                            HStack {
                                Text("Heavy tasks scheduled automatically.")
                                    .foregroundStyle(Color("DarkText"))
                                Spacer()
                            }
                        }
                        .foregroundStyle(Color("Primary"))
                    }
                    .padding(.vertical, 10)
                    .padding(.leading, 20)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .background(Color("DarkSecondary"))
                    .cornerRadius(10)
                    .listRowBackground(Color("Primary"))
                    .contentShape(Rectangle())
                    .listRowSeparator(.hidden)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color("Secondary"), lineWidth: 1)
                    )
                    .padding(.top, 1)
                    .padding(.bottom, 10)
                    
                    VStack {
                        HStack {
                            Text("RENEWABLE % TODAY")
                                .foregroundStyle(Color("DarkText"))
                            Spacer()
                        }
                        .padding(.leading, 20)
                        HStack(spacing: 5) {
                            ForEach(0..<min(10, times.count), id: \.self) { index in
                                VStack{
                                    Spacer()
                                    RoundedTopRectangle(cornerRadius: 5)
                                        .fill(renewPercents[index] > CLEAN_THRESHOLD ? Color("Secondary") : Color("DarkText"))
                                        .frame(width: 30, height: CGFloat(renewPercents[index]) * 75.0 / 100.0)
                                        .overlay(
                                            RoundedTopRectangle(cornerRadius: 5)
                                                .stroke(currHour-6-index == index ? Color.white : Color.clear, lineWidth: 2)
                                        )
                                    Text(currHour-6-index == index ? "Now" : times[index])
                                        .foregroundStyle(currHour-6-index == index ? Color("BrightText") : Color("DarkText"))
                                }
                            }
                        }
                    }
                    .padding(.vertical, 10)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .background(Color("MenuBar"))
                    .cornerRadius(10)
                    .listRowBackground(Color("Primary"))
                    .contentShape(Rectangle())
                    .listRowSeparator(.hidden)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color("DarkText"), lineWidth: 1)
                    )
                    .padding(.top, 1)
                    .padding(.bottom, 10)
                    
                    ForEach(sortedTasks) { task in
                        OptimalRow(task: task, renewableForecast: renewableForecast)
                    }
                    
                }
                .listStyle(.plain)
            }
            .listRowBackground(Color.clear)
            .scrollContentBackground(.hidden)
            .background(Color("Primary"))
            .padding(.bottom, 10)
        }
        .background(Color("Primary").ignoresSafeArea())
        .task {
            // Fetch renewable percentages once on first appearance
            if !hasFetchedRenewables {
                await fetchRenewablePercentages()
                hasFetchedRenewables = true
            }
            
            if optimizedTasks.count > 0 && !hasScheduled {
                await createSchedule()
                hasScheduled = true
            }
        }
        .onChange(of: optimizedTasks.count) { oldValue, newValue in
            // Reset scheduling flag when tasks change
            hasScheduled = false
        }
    }
    
    private func fetchRenewablePercentages() async {
        
        guard let forecast = await energyService.fetchRenewableEnergyForecast() else {
            return
        }
        
        guard !forecast.isEmpty else {
            return
        }
        
        // Store the full forecast for use in OptimalRow
        renewableForecast = forecast
        
        // The chart shows 10 time slots starting from 6 AM (hours 6, 8, 10, 12, 14, 16, 18, 20, 22, 0)
        let chartHours = [6, 8, 10, 12, 14, 16, 18, 20, 22, 0]
        var newRenewPercents: [Int] = []
        
        for hour in chartHours {
            if let percentage = forecast[hour] {
                let roundedPercent = Int(percentage.rounded())
                newRenewPercents.append(roundedPercent)
            } else {
                // Fallback to current value if hour not in forecast
                let index = chartHours.firstIndex(of: hour) ?? 0
                let fallback = renewPercents[index]
                newRenewPercents.append(fallback)
            }
        }
        
        // Update the state on the main actor
        renewPercents = newRenewPercents

        
        // Calculate clean window (best renewable period)
        updateCleanWindow(from: forecast)
    }
    
    private func updateCleanWindow(from forecast: [Int: Double]) {
        // Find the continuous window with highest average renewable percentage
        var bestWindowStart = 10
        var bestWindowEnd = 16
        var bestAverage = 0.0
        
        // Try different window sizes (4-8 hours)
        for windowSize in 4...8 {
            for startHour in 0...(24-windowSize) {
                var sum = 0.0
                var count = 0
                
                for hour in startHour..<(startHour + windowSize) {
                    if let percentage = forecast[hour] {
                        sum += percentage
                        count += 1
                    }
                }
                
                let average = count > 0 ? sum / Double(count) : 0
                if average > bestAverage {
                    bestAverage = average
                    bestWindowStart = startHour
                    bestWindowEnd = startHour + windowSize - 1
                }
            }
        }
        
        cleanWindowOpen = bestWindowStart
        cleanWindowClose = bestWindowEnd
        cleanPercent = Int(bestAverage.rounded())
        
    }
    
    private func createSchedule() async {
        
        var taskMap: [String: UserTask] = [:]
        taskNames.removeAll()

        for task in optimizedTasks {
            taskNames.append(task.name)
            taskMap[task.name] = task
        }

        // processTasks handles CO₂ savings internally using the correct unoptimized baseline
        let schedule = await dataController.processTasks(taskNames)
        
        for scheduled in schedule {
            guard let originalInput = scheduled.impact.originalInput,
                  let task = taskMap[originalInput] else {
                
                continue
            }

            let oldTime = task.timestamp
            task.timestamp = Calendar.current.dateInterval(of: .hour, for: scheduled.scheduledDate)!.start
        }

        do {
            try modelContext.save()
        } catch {
        }

        hasScheduled = true
    }
}


struct OptimalRow: View {
    let task: UserTask
    let renewableForecast: [Int: Double]
    @State private var isChecked: Bool = false
    
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter.string(from: task.timestamp)
    }

    private var amPmString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "a"
        return formatter.string(from: task.timestamp)
    }
    
    private var renewablePercent: Int {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: task.timestamp)
        
        if let percentage = renewableForecast[hour] {
            return Int(percentage.rounded())
        }
        
        // Fallback to 82% if no forecast data available
        return 82
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack{
                VStack(spacing: 0) {
                    Text(timeString)
                        .foregroundStyle(Color("Secondary"))
                        .frame(width: 50, alignment: .leading)
                    Text(amPmString)
                        .foregroundStyle(Color("DarkText"))
                        .font(.caption)
                    Spacer()
                }
                VStack {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(Color("Secondary"))
                    Spacer()
                }
            }
            VStack {
                HStack {
                    Text(task.name)
                        .foregroundStyle(Color("BrightText"))
                    Spacer()
                }
                HStack {
                    Text("\(renewablePercent)% clean")
                        .foregroundStyle(renewablePercent > CLEAN_THRESHOLD ? Color("Secondary") : Color("BurntOrange"))
                        .font(.subheadline)
                        .padding()
                        .frame(height: 25)
                        .background(renewablePercent > CLEAN_THRESHOLD ? Color("DarkSecondary") : Color("DarkBurntOrange"))
                        .cornerRadius(8)
                    Spacer()
                }
                
            }
        }
        .padding(.vertical, 20)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .background(Color("Primary"))
        .listRowBackground(Color("Primary"))
        .contentShape(Rectangle())
        .listRowSeparatorTint(Color("DarkText"))
    }
}

struct RoundedTopRectangle: Shape {
    var cornerRadius: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))
        
        path.addArc(
            center: CGPoint(x: rect.minX + cornerRadius, y: rect.minY + cornerRadius),
            radius: cornerRadius,
            startAngle: Angle(degrees: 180),
            endAngle: Angle(degrees: 270),
            clockwise: false
        )
        
        path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY))
        
        path.addArc(
            center: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY + cornerRadius),
            radius: cornerRadius,
            startAngle: Angle(degrees: 270),
            endAngle: Angle(degrees: 0),
            clockwise: false
        )
        
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        
        path.closeSubpath()
        
        return path
    }
}

#Preview {
    LandingView()
        .environment(DataController())
        .modelContainer(for: UserTask.self, inMemory: true)
}
