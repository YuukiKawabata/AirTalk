import SwiftUI

enum ThemeColor: String, CaseIterable, Identifiable {
    case black = "black"
    case white = "white"
    case purple = "purple"
    case blue = "blue"
    case green = "green"
    case orange = "orange"
    case pink = "pink"
    
    var id: String { rawValue }
    
    var color: Color {
        switch self {
        case .black: return .black
        case .white: return .white
        case .purple: return .purple
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .pink: return .pink
        }
    }
    
    var gradientColors: [Color] {
        switch self {
        case .black: return [Color(white: 0.1), Color(white: 0.3)]
        case .white: return [Color(white: 0.8), Color(white: 1.0)]
        case .purple: return [Color(red: 0.4, green: 0.1, blue: 0.8), Color(red: 0.8, green: 0.2, blue: 0.9)]
        case .blue: return [Color(red: 0.1, green: 0.3, blue: 0.8), Color(red: 0.2, green: 0.8, blue: 0.9)]
        case .green: return [Color(red: 0.1, green: 0.6, blue: 0.3), Color(red: 0.5, green: 0.9, blue: 0.2)]
        case .orange: return [Color(red: 0.9, green: 0.4, blue: 0.1), Color(red: 0.9, green: 0.8, blue: 0.2)]
        case .pink: return [Color(red: 0.9, green: 0.2, blue: 0.5), Color(red: 0.9, green: 0.6, blue: 0.8)]
        }
    }
}
