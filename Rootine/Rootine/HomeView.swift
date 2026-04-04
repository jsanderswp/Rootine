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
    @Query private var optimizedTasks: [Task]
    @Binding var selectedTab: Tab
    @State var cleanPercent: Int = 74
    @State var timeToSolPeak: Int = 15
    @State var highestCO2Tasks: [String] = ["Water heater", "Refrigerator"]
    @State var kgCO2Saved: Float = 1.4
    @State var isBestWindow: Bool = true
    @State var cleanIsRising: Bool = true
    @State var dayStreak: Int = 4

    var body: some View {
        ZStack {
            Color("Primary").ignoresSafeArea()
            VStack {
                HStack {
                    Text("Grid is")
                        .foregroundStyle(Color("BrightText"))
                        .font(.largeTitle)
                    + Text(" \(cleanPercent)% clean")
                        .foregroundStyle(cleanPercent > CLEAN_THRESHOLD ? Color("Secondary") : Color("BurntOrange"))
                        .font(.largeTitle)
                    Spacer()
                }
                .padding(.leading, 20)

                HStack {
                    Text(isBestWindow ? "Best window now" : "Cleaner energy later")
                        .foregroundStyle(Color("DarkText"))
                    + Text(isBestWindow ? " • run heavy loads" : " • hold off on heavy loads")
                        .foregroundStyle(Color("DarkText"))
                    Spacer()
                }
                .padding(.leading, 20)

                HStack(alignment: .top) {
                    VStack(alignment: .center) {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(isBestWindow ? Color("Secondary") : Color("BurntOrange"))
                    }
                    VStack {
                        HStack {
                            Text(isBestWindow ? "Act now." : "Let's wait.")
                                .foregroundStyle(isBestWindow ? Color("Secondary") : Color("BurntOrange"))
                            + Text(" Solar peaks in \(timeToSolPeak) min.")
                                .foregroundStyle(Color("DarkText"))
                            Spacer()
                        }
                        HStack {
                            Text(isBestWindow ? "\(highestCO2Tasks[0]) + \(highestCO2Tasks[1]) = \(kgCO2Saved.formatted(.number.precision(.fractionLength(1)))) kg CO\u{2082} saved vs. tonight." : "\(highestCO2Tasks[0]) + \(highestCO2Tasks[1]) = \(kgCO2Saved.formatted(.number.precision(.fractionLength(1)))) kg CO\u{2082} that can be saved later." )
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

                VStack(spacing: 10) {
                    HStack {
                        Text("GRID CLEANLINESS")
                            .foregroundStyle(Color("DarkText"))
                        Spacer()
                    }

                    HStack {
                        Text("\(cleanPercent)")
                            .foregroundStyle(Color("BrightText"))
                            .font(.largeTitle)
                        + Text("%")
                            .foregroundStyle(Color("DarkText"))
                        
                        Spacer()
                        
                        Text(cleanIsRising ? "↑ rising" : "↓ falling")
                            .foregroundStyle(cleanIsRising ? Color("Secondary") : Color("BurntOrange"))
                    }

                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color("DarkText"))
                            .frame(height: 6)
                            .edgesIgnoringSafeArea(.horizontal)
                        
                        RoundedRectangle(cornerRadius: 10)
                            .fill(cleanPercent > CLEAN_THRESHOLD ? Color("Secondary") : Color("BurntOrange"))
                            .frame(height: 6)
                            .edgesIgnoringSafeArea(.horizontal)
                            .padding(.trailing, 322 - CGFloat(cleanPercent) * 322.0 / 100.0) //0-322
                    }
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
                
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("\(kgCO2Saved.formatted(.number.precision(.fractionLength(1))))")
                                .foregroundStyle(Color("BrightText"))
                                .font(.largeTitle)
                            + Text(" kg")
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
                    
                    VStack(alignment: .leading) {
                        HStack {
                            Text("\(dayStreak)")
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
                .frame(height: 115)
                .padding(.horizontal, 20)
                .padding(.bottom, 3)
                
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
                        ForEach(Array(optimizedTasks.prefix(2).enumerated()), id: \.element.id) { index, task in
                            OptimalRow(task: task)
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
                
                Spacer()
            }
        }
    }
}

#Preview {
    @Previewable @State var selectedTab: Tab = .home
    return LandingView()
        .modelContainer(for: Task.self, inMemory: true)
}
