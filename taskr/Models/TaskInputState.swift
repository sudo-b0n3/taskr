import Foundation
import SwiftUI

@MainActor
final class TaskInputState: ObservableObject {
    @Published var text: String = ""
    @Published var suggestions: [String] = []
    @Published var selectedSuggestionIndex: Int? = nil

    var hasSuggestions: Bool {
        !suggestions.isEmpty
    }
}
