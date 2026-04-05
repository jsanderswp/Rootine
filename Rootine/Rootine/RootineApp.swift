//
//  RootineApp.swift
//  Rootine
//
//  Created by Jackson Sanders on 4/3/26.
//

import SwiftUI
import SwiftData

@main
struct RootineApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            UserTask.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                LandingView()
            }
        }
        .modelContainer(sharedModelContainer)
    }
}

#Preview {
    LandingView()
        .modelContainer(for: UserTask.self, inMemory: true)
}
