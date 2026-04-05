//
//  RootineTests.swift
//  RootineTests
//
//  Created by Jackson Sanders on 4/3/26.
//

import Testing
@testable import Rootine

struct RootineTests {

    @Test func example() async throws {
        let dataController = await MainActor.run {
            DataController()
        }
        _ = dataController // keep it alive for the duration of the test

        let geminiService = GeminiService()

        let response = await geminiService.parseActivities("Run the dishwasher for 60 minutes")

        switch response {
        case .success(let activities):
            print(activities.count)
            #expect(activities.count > 0)
        case .failure(let error):
            Issue.record("parseActivities failed: \(error)")
            #expect(Bool(false), "parseActivities should succeed in this test")
        }
    }

}
