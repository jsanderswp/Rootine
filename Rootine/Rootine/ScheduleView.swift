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
    @Query private var optimizedTasks: [Task]
    @State private var taskName: String = ""
    @State var heavyCount: Int = 0
    @State var otherCount: Int = 0
    @State var totalCO2: Float = 0.0
    @State var cleanPercent: Int = 82
    @State var cleanWindowOpen: Int = 10
    @State var cleanWindowClose: Int = 1
    @State var times: [String] = ["6a", "8a", "10a", "12p", "2p", "4p", "6p", "8p", "10p", "12a"]
    @State var renewPercents: [Int] = [25, 30, 55, 73, 89, 61, 49, 20, 18, 27]
    @State var currHour: Int = Calendar.current.component(.hour, from: Date())%2 == 0 ? Calendar.current.component(.hour, from: Date()) : Calendar.current.component(.hour, from: Date())-1
    
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
                    + Text(" \(totalCO2.formatted(.number.precision(.fractionLength(1)))) kg CO₂")
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
                                Text("Clean window \(cleanWindowOpen) AM – \(cleanWindowClose) PM.")
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

                    
                    ForEach(optimizedTasks) { task in
                            OptimalRow(task: task)
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
    }
}

struct OptimalRow: View {
    let task: Task
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

    var body: some View {
        HStack(spacing: 10) {
            HStack{
                VStack(spacing: 0) {
                    Text(timeString)
                        .foregroundStyle(Color("Secondary"))
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
                    Text("Grid peaking — start now")
                        .foregroundStyle(Color("DarkText"))
                    Spacer()
                }
                HStack {
                    Text("82% clean")
                        .foregroundStyle(Color("Secondary"))
                        .font(.subheadline)
                        .padding()
                        .frame(height: 25)
                        .background(Color("DarkSecondary"))
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
        .modelContainer(for: Task.self, inMemory: true)
}
