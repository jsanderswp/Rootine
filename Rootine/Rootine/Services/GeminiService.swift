//
//  GeminiService.swift
//  Rootine
//
//  Created by Jackson Sanders on 4/3/26.
//

import Foundation

class GeminiService {
    private let apiKey: String = {
        Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String ?? ""
    }()

    func parseActivities(_ text: String) async -> Result<[Activity], GeminiError> {
        do {
            let prompt = """
            You are a parser.
            
            
            Extract energy-related activities from the user's text.
            
            Return ONLY valid JSON in this format:
            
            [
              {
                "activity": "string",
                "category": number (optional),
                "duration": number (optional, in hours)
              }
            ]
            
            Rules:
            - Do not include explanations
            - Do not include markdown
            - Return ONLY JSON
            - If something is not clear, make your best guess
            - Normalize activities (e.g., "washing dishes" → "dishwasher")
            
            Text:
            "I ran the dishwasher twice and charged my phone"
            """
            
            let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-lite:generateContent?key=\(apiKey)")!
            
            var request = URLRequest(url: url)
            
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let body: [String: Any] = [
                "contents": [
                    [
                        "parts": [
                            ["text": prompt]
                        ]
                    ]
                ]
            ]
            
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return .failure(.networkError)
            }
            
            // Try to decode
            let decoded = try JSONDecoder().decode([Activity].self, from: data)
            
            return .success(decoded)
        }
        catch {
            return .failure(.decodingFailed)
        }
    }
}

enum GeminiError: Error {
    case invalidResponse
    case decodingFailed
    case networkError
}
