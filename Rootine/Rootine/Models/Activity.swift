//
//  Activity.swift
//  Rootine
//
//  Created by Jackson Sanders on 4/3/26.
//

import Foundation

struct Activity: Codable {
    let activity: String
    let type: String
    let duration: Double?
    let isFlexible: Bool
}
