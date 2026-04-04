//
//  TasksView.swift
//  Rootine
//
//  Created by Jackson Sanders on 4/3/26.
//

import SwiftUI
import SwiftData

struct TasksView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var tasks: [Task]
    @State private var taskName: String = ""
    @State var heavyCount: Int = 0
    @State var otherCount: Int = 0
    
    var body: some View {
        VStack(){
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
                
                Button(action: addTask) {
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
                    
                    let sortedTasks = tasks.sorted(by: >)
                    
                    ForEach(sortedTasks) { task in
                        if task.isHighImpact {
                            TaskRow(task: task)
                        }
                    }
                    .onDelete(perform: deleteTasks)
                    
                    Text("OTHER")
                        .foregroundStyle(Color("DarkText"))
                        .listRowBackground(Color("Primary"))
                        .listRowSeparatorTint(Color("Primary"))
                                        
                    ForEach(sortedTasks) { task in
                        if !task.isHighImpact {
                            TaskRow(task: task)
                        }
                    }
                    .onDelete(perform: deleteTasks)
                    
                }
                .listStyle(.plain)
                Button("Optimize my day ↗") {
                    
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
    
    private func addTask() {
        if taskName.isEmpty { return }
        withAnimation {
            let usage = Float.random(in: 0...10)
            if usage >= HEAVY_USAGE {
                heavyCount += 1
            } else {
                otherCount += 1
            }
            let newTask = Task(name: taskName, energyUsage: Float(usage), taskLength: "1 hr", timestamp: Date())
            modelContext.insert(newTask)
        }
    }
    
    private func deleteTasks(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                if tasks[index].isHighImpact {
                    heavyCount -= 1
                } else {
                    otherCount -= 1
                }
                modelContext.delete(tasks[index])
            }
        }
    }
}

struct TaskRow: View {
    let task: Task
    @State private var isChecked: Bool = false

    var body: some View {
        HStack {
            VStack{
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
                    if task.energyUsage >= HEAVY_USAGE && !isChecked{
                        Text("High impact")
                            .foregroundStyle(Color("BurntOrange"))
                            .font(.subheadline)
                            .padding()
                            .frame(height: 25)
                            .background(Color("DarkBurntOrange"))
                            .cornerRadius(8)
                    } else if task.energyUsage < HEAVY_USAGE && !isChecked{
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
        .modelContainer(for: Task.self, inMemory: true)
}
