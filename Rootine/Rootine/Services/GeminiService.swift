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
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if !(200...299).contains(httpResponse.statusCode) {
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
            
            
            // Extract the text from the first candidate
            guard let firstCandidate = geminiResponse.candidates.first,
                  let firstPart = firstCandidate.content.parts.first else {
                return .failure(.invalidResponse)
            }
            
            
            // The text contains the JSON array as a string, so we need to parse it
            let jsonText = firstPart.text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard let jsonData = jsonText.data(using: .utf8) else {
                return .failure(.decodingFailed)
            }
            
            let decoded = try JSONDecoder().decode([Activity].self, from: jsonData)
            
            
            return .success(decoded)
        }
        catch let error {
            return .failure(.decodingFailed)
        }
    }
}

enum GeminiError: Error {
    case invalidResponse
    case decodingFailed
    case networkError
}
