//
//  HomeView.swift
//  Rootine
//
//  Created by Jack Baker on 4/3/26.
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(DataController.self) private var dataController
    @Query(sort: \UserTask.timestamp) private var optimizedTasks: [UserTask]
    @Binding var selectedTab: Tab
    @State var cleanPercent: Int = 74
    @State var timeToSolPeak: Int = 15
    @State var highestCO2Tasks: [String] = ["Water-heater", "Washing machine"]
    @State var isBestWindow: Bool = true
    @State var cleanIsRising: Bool = true
    @State var dayStreak: Int = 4
    @State private var renewableForecast: [Int: Double] = [:]
    private let energyService = EnergyService()
    
    // Timer for periodic updates (every 15 minutes)
    private let updateTimer = Timer.publish(every: 15 * 60, on: .main, in: .common).autoconnect()

    private var detailMessage: String {
        let tasksString = "\(highestCO2Tasks[0]) + \(highestCO2Tasks[1])"
        let co2Amount = dataController.totalCO2Saved.formatted(.number.precision(.fractionLength(1)))
        
        if isBestWindow {
            return "\(tasksString) = \(co2Amount) kg CO₂ saved vs. tonight."
        } else {
            return "\(tasksString) = \(co2Amount) kg CO₂ that can be saved later."
        }
    }
    
    private var cleanPercentText: String {
        " \(cleanPercent)% clean"
    }
    
    private var cleanPercentNumber: String {
        "\(cleanPercent)"
    }
    
    private var formattedKgCO2: String {
        dataController.totalCO2Saved.formatted(.number.precision(.fractionLength(1)))
    }
    
    private var solarPeakText: String {
        guard let peak = dataController.solarPeak else {
            return " Solar peak loading..."
        }
        let minutes = Int(peak.timeIntervalSinceNow / 60)
        guard minutes > 0 else { return " Solar peak passed." }
        if minutes < 60 {
            return " Solar peaks in \(minutes) min."
        } else {
            let hours = minutes / 60
            return " Solar peaks in \(hours) hr."
        }
    }
    
    private var dayStreakText: String {
        "\(dayStreak)"
    }
    
    private var upcomingTasks: [UserTask] {
        optimizedTasks
            .filter { $0.timestamp > Date() }
            .sorted { $0.timestamp < $1.timestamp }
            .prefix(2)
            .map { $0 }
    }
    
    var body: some View {
        ZStack {
            Color("Primary").ignoresSafeArea()
            VStack {
                headerView
                subheaderView
                actionBannerView
                gridCleanlinessView
                statsCardsView
                upcomingTasksView
                Spacer()
            }
            .task {
                await fetchCurrentRenewablePercentage()
                await dataController.getSolarPeak()
            }
            .onReceive(updateTimer) { _ in
                Task {
                    await fetchCurrentRenewablePercentage()
                    await dataController.getSolarPeak()
                }
            }
        }
    }
    
    private var headerView: some View {
        HStack {
            Text("Grid is")
                .foregroundStyle(Color("BrightText"))
                .font(.largeTitle)
            Text(cleanPercentText)
                .foregroundStyle(cleanPercent > CLEAN_THRESHOLD ? Color("Secondary") : Color("BurntOrange"))
                .font(.largeTitle)
            Spacer()
        }
        .padding(.leading, 20)
    }
    
    private var subheaderView: some View {
        HStack {
            Text(isBestWindow ? "Best window now" : "Cleaner energy later")
                .foregroundStyle(Color("DarkText"))
            Text(isBestWindow ? " • run heavy loads" : " • hold off on heavy loads")
                .foregroundStyle(Color("DarkText"))
            Spacer()
        }
        .padding(.leading, 20)
    }
    
    private var actionBannerView: some View {
        HStack(alignment: .top) {
            VStack(alignment: .center) {
                Image(systemName: "circle.fill")
                    .foregroundStyle(isBestWindow ? Color("Secondary") : Color("BurntOrange"))
            }
            VStack {
                HStack {
                    Text(isBestWindow ? "Act now." : "Let's wait.")
                        .foregroundStyle(isBestWindow ? Color("Secondary") : Color("BurntOrange"))
                    Text(solarPeakText)
                        .foregroundStyle(Color("DarkText"))
                    Spacer()
                }
                HStack {
                    Text(detailMessage)
                        .foregroundStyle(Color("DarkText"))
                    Spacer()
                }
            }
            .foregroundStyle(Color("Primary"))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 20)
        .background(isBestWindow ? Color("DarkSecondary") : Color("DarkBurntOrange"))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isBestWindow ? Color("Secondary") : Color("BurntOrange"), lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .padding(.top, 0)
        .padding(.bottom, 3)
    }
    
    private var gridCleanlinessView: some View {
        VStack(spacing: 10) {
            HStack {
                Text("GRID CLEANLINESS")
                    .foregroundStyle(Color("DarkText"))
                Spacer()
            }

            HStack {
                Text(cleanPercentNumber)
                    .foregroundStyle(Color("BrightText"))
                    .font(.largeTitle)
                Text("%")
                    .foregroundStyle(Color("DarkText"))
                
                Spacer()
                
                Text(cleanIsRising ? "↑ rising" : "↓ falling")
                    .foregroundStyle(cleanIsRising ? Color("Secondary") : Color("BurntOrange"))
            }

            progressBarView
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 20)
        .background(Color("MenuBar"))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color("DarkText"), lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .padding(.top, 1)
        .padding(.bottom, 3)
    }
    
    private var progressBarView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color("DarkText"))
                .frame(height: 6)
                .edgesIgnoringSafeArea(.horizontal)
            
            RoundedRectangle(cornerRadius: 10)
                .fill(cleanPercent > CLEAN_THRESHOLD ? Color("Secondary") : Color("BurntOrange"))
                .frame(height: 6)
                .edgesIgnoringSafeArea(.horizontal)
                .padding(.trailing, 322 - CGFloat(cleanPercent) * 322.0 / 100.0)
        }
    }
    
    private var statsCardsView: some View {
        HStack(alignment: .top, spacing: 10) {
            co2SavedCard
            dayStreakCard
        }
        .frame(height: 115)
        .padding(.horizontal, 20)
        .padding(.bottom, 3)
    }
    
    private var co2SavedCard: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(formattedKgCO2)
                    .foregroundStyle(Color("BrightText"))
                    .font(.largeTitle)
                Text(" kg")
                    .foregroundStyle(Color("DarkText"))
                Spacer()
            }
            HStack {
                VStack {
                    Text("CO\u{2082} SAVED TODAY")
                        .foregroundStyle(Color("DarkText"))
                }
                Spacer()
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 20)
        .background(Color("MenuBar"))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color("DarkText"), lineWidth: 1)
        )
    }
    
    private var dayStreakCard: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(dayStreakText)
                    .foregroundStyle(Color("Secondary"))
                    .font(.largeTitle)
                Spacer()
            }
            HStack {
                Text("DAY STREAK")
                    .foregroundStyle(Color("DarkText"))
                Spacer()
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 20)
        .background(Color("MenuBar"))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color("DarkText"), lineWidth: 1)
        )
    }
    
    private var upcomingTasksView: some View {
        VStack {
            Button(action: { selectedTab = .schedule }) {
                HStack {
                    Text("UPCOMING TASKS")
                        .foregroundStyle(Color("DarkText"))
                    Spacer()
                }
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.bottom, -12)
            
            List {
                ForEach(Array(upcomingTasks.enumerated()), id: \.element.id) { index, task in
                    OptimalRow(task: task, renewableForecast: renewableForecast)
                        .listRowSeparator(index == 0 ? .hidden : .visible, edges: .top)
                        .onTapGesture {
                            selectedTab = .schedule
                        }
                }
            }
            .padding(.leading, -18)
            .listStyle(.plain)
        }
        .listRowBackground(Color.clear)
        .scrollContentBackground(.hidden)
        .background(Color("Primary"))
        .padding(.bottom, 10)
        .padding(.leading, 20)
    }
    
    private func fetchCurrentRenewablePercentage() async {
        
        guard let percentage = await energyService.fetchRenewablePercentage() else {
            return
        }
        
        // Update current percentage
        cleanPercent = Int(percentage.rounded())
        
        // Fetch forecast to determine trend (compare current to 15 min from now)
        if let forecast = await energyService.fetchRenewableEnergyForecast() {
            // Store forecast for OptimalRow
            renewableForecast = forecast
            
            let now = Date()
            let calendar = Calendar.current
            
            // Get current hour and next hour (15 min from now will likely be same or next hour)
            let currentHour = calendar.component(.hour, from: now)
            let currentMinute = calendar.component(.minute, from: now)
            
            // Determine which hour to check (if we're past :45, check next hour, otherwise same hour)
            let compareHour = currentMinute >= 45 ? (currentHour + 1) % 24 : currentHour
            
            if let futurePercentage = forecast[compareHour] {
                let futurePercent = Int(futurePercentage.rounded())
                cleanIsRising = futurePercent > cleanPercent
            } else {
                print("⚠️ No forecast data for hour \(compareHour), keeping cleanIsRising as-is")
            }
        }
        
        // Determine if we're in the best window (>50% clean)
        isBestWindow = cleanPercent > CLEAN_THRESHOLD
        
    }
}

#Preview {
    @Previewable @State var selectedTab: Tab = .home
    return LandingView()
        .environment(DataController())
        .modelContainer(for: UserTask.self, inMemory: true)
}
