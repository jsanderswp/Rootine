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
        print("🔍 GeminiService: Starting parseActivities for text: '\(text)'")
        print("🔍 GeminiService: API key present: \(apiKey.isEmpty ? "NO" : "YES"), length: \(apiKey.count)")
        
        do {
            
            let prompt = """
            You are a parser.
            
            Extract energy-related activities from the user's text.
            
            Return ONLY valid JSON in this format:
            
            [
              {
                "activity": "string",
                "type": "string",
                "duration": number (optional, in minutes),
                "isFlexible": boolean
              }
            ]
            
            Rules:
            - Do not include explanations
            - Do not include markdown code blocks
            - Return ONLY the JSON array, nothing else
            - If something is not clear, make your best guess
            - Normalize activities (e.g., "washing dishes" → "dishwasher")
            - Type should be one of: streaming, compute, gaming, charging, appliance, idle, or unknown
            - Duration should be in minutes (estimate if not specified)
            - isFlexible should be true if the task can be done at any time
            
            Text:
            "\(text)"
            """
            let url = URL(string: "https://generativelanguage.googleapis.com/v1/models/gemini-2.5-flash:generateContent?key=\(apiKey)")!
            
            print("🔍 GeminiService: Making API request to Gemini")
            
            var request = URLRequest(url: url)
            
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let body: [String: Any] = [
                "contents": [
                    [
                        "role": "user",
                        "parts": [
                            ["text": prompt]
                        ]
                    ]
                ]
            ]
            
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            print("🔍 GeminiService: Sending request...")
            let (data, response) = try await URLSession.shared.data(for: request)
            
            print("🔍 GeminiService: Received response")
            if let httpResponse = response as? HTTPURLResponse {
                print("🔍 GeminiService: HTTP Status: \(httpResponse.statusCode)")
                if !(200...299).contains(httpResponse.statusCode) {
                    if let responseText = String(data: data, encoding: .utf8) {
                        print("🔍 GeminiService: Error response body: \(responseText)")
                    }
                    return .failure(.networkError)
                }
            }
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return .failure(.networkError)
            }
            
            // Decode the Gemini API response wrapper
            struct GeminiResponse: Codable {
                struct Candidate: Codable {
                    struct Content: Codable {
                        struct Part: Codable {
                            let text: String
                        }
                        let parts: [Part]
                    }
                    let content: Content
                }
                let candidates: [Candidate]
            }
            
            let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
            
            print("🔍 GeminiService: Successfully decoded Gemini response")
            print("🔍 GeminiService: Candidates count: \(geminiResponse.candidates.count)")
            
            // Extract the text from the first candidate
            guard let firstCandidate = geminiResponse.candidates.first,
                  let firstPart = firstCandidate.content.parts.first else {
                print("🔍 GeminiService: No candidate or part found in response")
                return .failure(.invalidResponse)
            }
            
            print("🔍 GeminiService: Raw response text: \(firstPart.text)")
            
            // The text contains the JSON array as a string, so we need to parse it
            let jsonText = firstPart.text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard let jsonData = jsonText.data(using: .utf8) else {
                print("🔍 GeminiService: Failed to convert cleaned JSON to data")
                return .failure(.decodingFailed)
            }
            
            print("🔍 GeminiService: Cleaned JSON: \(jsonText)")
            let decoded = try JSONDecoder().decode([Activity].self, from: jsonData)
            
            print("🔍 GeminiService: Successfully decoded \(decoded.count) activities")
            for (i, activity) in decoded.enumerated() {
                print("🔍 GeminiService: Activity \(i): \(activity.activity), type: \(activity.type), duration: \(activity.duration ?? -1)")
            }
            
            return .success(decoded)
        }
        catch let error {
            print("🔍 GeminiService: Caught error: \(error)")
            print("🔍 GeminiService: Error type: \(type(of: error))")
            return .failure(.decodingFailed)
        }
    }
}

enum GeminiError: Error {
    case invalidResponse
    case decodingFailed
    case networkError
}
