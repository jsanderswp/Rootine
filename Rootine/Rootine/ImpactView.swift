//
//  Impact.swift
//  Rootine
//
//  Created by Jack Baker on 4/3/26.
//

import SwiftUI

struct ImpactView: View {
    @State var avgCleanPercent: Int = 73
    @State var kgCO2SavedThisWeek: Float = 12.3
    @State var dayStreak: Int = 4
    @State var tasksOptimized: Int = 34
    @State var energySaved: Float = 4.20 //$$
    @State var dayChars: [String] = ["S", "M", "T", "W", "T", "F", "S"]
    @State var weeklyCO2Saved: [Float] = [2.1, 3.4, 0.0, 4.2, 2.9, -1, -1]
    
    var body: some View {
        ZStack {
            Color("Primary").ignoresSafeArea()
            VStack {
                HStack {
                    Text("Your Impact")
                        .foregroundStyle(Color("BrightText"))
                        .font(.largeTitle)
                    Spacer()
                }
                .padding(.leading, 20)
                
                HStack {
                    Text("Since you started using Rootine")
                        .foregroundStyle(Color("DarkText"))
                    Spacer()
                }
                .padding(.leading, 20)
                .padding(.bottom, 10)
                
                ZStack {
                    Circle()
                        .stroke(Color("MenuBar"), lineWidth: 15)
                    
                    Circle()
                        .trim(from: 0, to: CGFloat(avgCleanPercent) / 100.0)
                        .stroke(avgCleanPercent > CLEAN_THRESHOLD ? Color("Secondary") : Color("BurntOrange"), style: StrokeStyle(lineWidth: 15, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    
                    VStack {
                        Text("\(avgCleanPercent)%")
                            .font(.largeTitle)
                            .foregroundStyle(avgCleanPercent > CLEAN_THRESHOLD ? Color("Secondary") : Color("BurntOrange"))
                        Text("avg clean")
                            .foregroundStyle(Color("DarkText"))
                    }
                }
                .frame(width: 150, height: 150)
                .padding()
                
                Text("Average grid cleanliness this week")
                    .foregroundStyle(Color("DarkText"))
                
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("\(kgCO2SavedThisWeek.formatted(.number.precision(.fractionLength(1))))")
                                .foregroundStyle(Color("Secondary"))
                                .font(.largeTitle)
                            + Text(" kg")
                                .foregroundStyle(Color("DarkText"))
                            Spacer()
                        }
                        HStack {
                            VStack {
                                Text("CO\u{2082} SAVED")
                                    .foregroundStyle(Color("DarkText"))
                            }
                            Spacer()
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 5)
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
                    .padding(.vertical, 5)
                    .padding(.horizontal, 20)
                    .background(Color("MenuBar"))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color("DarkText"), lineWidth: 1)
                    )
                }
                .frame(height: 80)
                .padding(.horizontal, 20)
                .padding(.bottom, 5)
                
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("\(tasksOptimized)")
                                .foregroundStyle(Color("BrightText"))
                                .font(.largeTitle)
                        }
                        HStack {
                            VStack {
                                Text("TASKS\nOPTIMIZED")
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
                            Text("$\(energySaved.formatted(.number.precision(.fractionLength(2))))")
                                .foregroundStyle(Color("Secondary"))
                                .font(.largeTitle)
                            Spacer()
                        }
                        HStack {
                            Text("ENERGY\nSAVED")
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
                .padding(.bottom, 10)
                
                HStack {
                    Text("THIS WEEK")
                        .foregroundStyle(Color("DarkText"))
                    Spacer()
                }
                .padding(.leading, 20)
                
                HStack {
                    ForEach(Array(0..<min(7, dayChars.count)), id: \.self) { index in
                        VStack{
                            Spacer()
                            
                            Text(dayChars[index])
                                .foregroundStyle(weeklyCO2Saved[index] >= 3.0 ? Color("Secondary") : weeklyCO2Saved[index] == 0.0 ? Color("BurntOrange") : Color("DarkText"))
                            
                            Spacer()
                            
                            Text(weeklyCO2Saved[index] == -1.0 ? "—" : weeklyCO2Saved[index] == 0.0 ? "0" : weeklyCO2Saved[index].formatted(.number.precision(.fractionLength(1))))
                                .foregroundStyle(weeklyCO2Saved[index] >= 3.0 ? Color("Secondary") : weeklyCO2Saved[index] == 0.0 ? Color("BurntOrange") : Color("DarkText"))
                            
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: 75)
                        .background(weeklyCO2Saved[index] >= 3.0 ? Color("DarkSecondary") : weeklyCO2Saved[index] == 0.0 ? Color("DarkBurntOrange") : Color("MenuBar"))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(weeklyCO2Saved[index] >= 3.0 ? Color("Secondary") : weeklyCO2Saved[index] == 0.0 ? Color("BurntOrange") : Color("DarkText"), lineWidth: 1)
                        )
                        

                    }
                }
                .padding(.horizontal, 20)
                
                Spacer()
            }
        }
    }
}

#Preview {
    LandingView()
        .modelContainer(for: Task.self, inMemory: true)
}
