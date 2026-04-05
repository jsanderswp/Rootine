//
//  TasksView.swift
//  Rootine
//
//  Created by Jackson Sanders on 4/3/26.
//

import SwiftUI
import SwiftData

func formatDuration(minutes: Double) -> String {
    let hours = minutes / 60.0
    let formatted = hours.formatted(.number.precision(.fractionLength(1)))
    let unit = hours == 1.0 ? "hr" : "hrs"
    return "\(formatted) \(unit)"
}

struct TasksView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(DataController.self) private var dataController
    @Query(sort: \UserTask.energyUsage, order: .reverse) private var tasks: [UserTask]
    @Binding var selectedTab: Tab
    @State private var taskName: String = ""

    var heavyTasks: [UserTask] { tasks.filter { $0.isHighImpact } }
    var otherTasks: [UserTask] { tasks.filter { !$0.isHighImpact } }
    var heavyCount: Int { heavyTasks.count }
    var otherCount: Int { otherTasks.count }

    var body: some View {
        VStack() {
            VStack {
                HStack {
                    Text("My Tasks")
                        .foregroundStyle(Color("BrightText"))
                        .font(.largeTitle)
                    Spacer()
                }
                HStack {
                    Text("\(heavyCount) energy-heavy")
                        .foregroundStyle(Color("Secondary"))
                    + Text(" • \(otherCount) other")
                        .foregroundStyle(Color("DarkText"))
                    Spacer()
                }
            }
            .padding(.leading, 20)

            HStack(spacing: 10) {
                TextField("Add a task", text: $taskName, prompt: Text("Add a task").foregroundColor(Color("DarkText")))
                    .padding(.horizontal)
                    .frame(height: 60)
                    .foregroundStyle(Color("BrightText"))
                    .background(Color("MenuBar"))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color("DarkText"), lineWidth: 1))
                    .padding(.leading, 20)

                Button(action: { Task { await addTask() } }) {
                    Image(systemName: "plus.square.fill")
                        .font(.system(size: 73, weight: .regular))
                        .foregroundStyle(Color("Secondary"))
                        .frame(width: 60, height: 60)
                        .background(Color("Primary"))
                        .cornerRadius(10)
                }
                .padding(.trailing, 20)
            }

            VStack {
                List {
                    Text("ENERGY-HEAVY")
                        .foregroundStyle(Color("DarkText"))
                        .listRowBackground(Color("Primary"))
                        .listRowSeparatorTint(Color("Primary"))

                    ForEach(heavyTasks) { task in
                        TaskRow(task: task)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            modelContext.delete(heavyTasks[index])
                        }
                    }

                    Text("OTHER")
                        .foregroundStyle(Color("DarkText"))
                        .listRowBackground(Color("Primary"))
                        .listRowSeparatorTint(Color("Primary"))

                    ForEach(otherTasks) { task in
                        TaskRow(task: task)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            modelContext.delete(otherTasks[index])
                        }
                    }
                }
                .listStyle(.plain)

                Button("Optimize my day ↗") {
                    selectedTab = .schedule
                }
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Color("Primary"))
                .frame(width: 350, height: 60)
                .background(Color("Secondary"))
                .cornerRadius(10)
            }
            .listRowBackground(Color.clear)
            .scrollContentBackground(.hidden)
            .background(Color("Primary"))
            .padding(.bottom, 10)
        }
        .background(Color("Primary").ignoresSafeArea())
    }

    private func addTask() async {
        if taskName.isEmpty { return }

        print("🔍 DEBUG: Adding task: \(taskName)")
        let impact = await dataController.processTask(taskName)

        print("🔍 DEBUG: Impact returned: \(impact != nil ? "YES" : "NO")")
        if let impact = impact {
            print("🔍 DEBUG: Activity: \(impact.activity.activity)")
            print("🔍 DEBUG: Type: \(impact.activity.type)")
            print("🔍 DEBUG: Duration: \(impact.activity.duration ?? -1)")
            print("🔍 DEBUG: kWh: \(impact.kWh)")
        }

        let usage = impact?.kWh ?? 0.0
        print("🔍 DEBUG: Final usage: \(usage)")

        withAnimation {
            let durationMinutes = impact?.activity.duration ?? 60.0
            let durationString = formatDuration(minutes: durationMinutes)
            print("🔍 DEBUG: Duration string: \(durationString)")

            let newTask = UserTask(name: taskName, energyUsage: usage, taskLength: durationString, timestamp: Date())
            modelContext.insert(newTask)
            taskName = ""
        }
    }
}

struct TaskRow: View {
    let task: UserTask
    @State private var isChecked: Bool = false

    var body: some View {
        HStack {
            VStack {
                Button(action: { isChecked.toggle() }) {
                    Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                        .foregroundStyle(isChecked ? Color("Secondary") : Color("DarkText"))
                        .imageScale(.large)
                }
                Spacer()
            }
            .padding(.leading, 16)

            VStack(alignment: .leading) {
                Text(task.name)
                    .foregroundStyle(isChecked ? Color("DarkText") : Color("BrightText"))
                    .strikethrough(isChecked, color: Color("BrightText"))
                if task.energyUsage == 0.0 {
                    Text(isChecked ? "Done" : "No energy use")
                        .foregroundStyle(Color("DarkText"))
                        .font(.subheadline)
                } else {
                    Text(isChecked ? "Done" : "~\(task.energyUsage.formatted(.number.precision(.fractionLength(1)))) kWh • \(task.taskLength)")
                        .foregroundStyle(Color("DarkText"))
                        .font(.subheadline)
                    if task.energyUsage >= HEAVY_USAGE && !isChecked {
                        Text("High impact")
                            .foregroundStyle(Color("BurntOrange"))
                            .font(.subheadline)
                            .padding()
                            .frame(height: 25)
                            .background(Color("DarkBurntOrange"))
                            .cornerRadius(8)
                    } else if task.energyUsage < HEAVY_USAGE && !isChecked {
                        Text("Low impact")
                            .foregroundStyle(Color("DarkText"))
                            .font(.subheadline)
                            .padding()
                            .frame(height: 25)
                            .background(Color("MenuBar"))
                            .cornerRadius(8)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 20)
        .padding(.trailing, 16)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .background(Color("Primary"))
        .listRowBackground(Color("Primary"))
        .contentShape(Rectangle())
        .listRowSeparatorTint(Color("DarkText"))
    }
}

#Preview {
    LandingView()
        .environment(DataController())
        .modelContainer(for: UserTask.self, inMemory: true)
}
