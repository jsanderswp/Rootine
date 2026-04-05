//
//  ContentView.swift
//  Rootine
//
//  Created by Jack Baker on 4/3/26.
//

import SwiftUI

enum Tab: Hashable {
    case home, tasks, schedule, impact
}

struct LandingView: View {
    @State private var selectedTab: Tab = .home
    @State private var homePath = NavigationPath()
    @State private var tasksPath = NavigationPath()
    @State private var schedulePath = NavigationPath()
    @State private var impactPath = NavigationPath()
    
    var body: some View {
        ZStack {
            Color("MenuBar").ignoresSafeArea()
            VStack(spacing: 0) {
                
                Group {
                    switch selectedTab {
                    case .home:
                        NavigationStack(path: $homePath) {
                            HomeView(selectedTab: $selectedTab)
                                .padding(.top, -15)
                                .toolbar {
                                    ToolbarItem(placement: .principal) {
                                        Text("Rootine")
                                            .font(.headline)
                                            .foregroundStyle(Color("Secondary"))
                                    }
                                }
                                .navigationBarTitleDisplayMode(.inline)
                        }
                        
                    case .tasks:
                        NavigationStack(path: $tasksPath) {
                            TasksView(selectedTab: $selectedTab)
                                .padding(.top, -15)
                                .toolbar {
                                    ToolbarItem(placement: .principal) {
                                        Text("Rootine")
                                            .font(.headline)
                                            .foregroundStyle(Color("Secondary"))
                                    }
                                }
                                .navigationBarTitleDisplayMode(.inline)
                        }
                        
                    case .schedule:
                        NavigationStack(path: $schedulePath) {
                            ScheduleView()
                                .padding(.top, -15)
                                .toolbar {
                                    ToolbarItem(placement: .principal) {
                                        Text("Rootine")
                                            .font(.headline)
                                            .foregroundStyle(Color("Secondary"))
                                    }
                                }
                                .navigationBarTitleDisplayMode(.inline)
                        }
                        
                    case .impact:
                        NavigationStack(path: $impactPath) {
                            ImpactView()
                                .padding(.top, -15)
                                .toolbar {
                                    ToolbarItem(placement: .principal) {
                                        Text("Rootine")
                                            .font(.headline)
                                            .foregroundStyle(Color("Secondary"))
                                    }
                                }
                                .navigationBarTitleDisplayMode(.inline)
                        }
                    }
                }
                
                Rectangle()
                    .fill(Color("DarkText"))
                    .frame(height: 1)
                    .edgesIgnoringSafeArea(.horizontal)
                
                HStack(spacing: 40) {
                    Button { selectedTab = .home } label: {
                        VStack {
                            Image(systemName: "bolt.house")
                            Text("Home")
                        }
                        .foregroundStyle(selectedTab == .home ? Color("Secondary") : Color("DarkText"))
                    }
                    Button { selectedTab = .tasks } label: {
                        VStack {
                            Image(systemName: "square.and.pencil")
                            Text("Tasks")
                        }
                        .foregroundStyle(selectedTab == .tasks ? Color("Secondary") : Color("DarkText"))
                    }
                    Button { selectedTab = .schedule } label: {
                        VStack {
                            Image(systemName: "calendar.badge.clock")
                            Text("Schedule")
                        }
                        .foregroundStyle(selectedTab == .schedule ? Color("Secondary") : Color("DarkText"))
                    }
                    Button { selectedTab = .impact } label: {
                        VStack {
                            Image(systemName: "bolt")
                            Text("Impact")
                        }
                        .foregroundStyle(selectedTab == .impact ? Color("Secondary") : Color("DarkText"))
                    }
                }
                .padding()
            }
        }
    }
}

#Preview {
    LandingView()
        .environment(DataController())
        .modelContainer(for: UserTask.self, inMemory: true)
}
