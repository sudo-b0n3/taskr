import SwiftUI

struct TaskTagPaletteOption: Identifiable {
    let key: String
    let title: String
    let color: Color

    var id: String { key }
}

enum TaskTagPalette {
    static let options: [TaskTagPaletteOption] = [
        TaskTagPaletteOption(key: TaskTagColorKey.slate.rawValue, title: "Slate", color: Color(red: 0.38, green: 0.44, blue: 0.52)),
        TaskTagPaletteOption(key: TaskTagColorKey.blue.rawValue, title: "Blue", color: Color(red: 0.24, green: 0.50, blue: 0.72)),
        TaskTagPaletteOption(key: TaskTagColorKey.green.rawValue, title: "Green", color: Color(red: 0.27, green: 0.58, blue: 0.43)),
        TaskTagPaletteOption(key: TaskTagColorKey.amber.rawValue, title: "Amber", color: Color(red: 0.72, green: 0.56, blue: 0.26)),
        TaskTagPaletteOption(key: TaskTagColorKey.red.rawValue, title: "Red", color: Color(red: 0.72, green: 0.36, blue: 0.33)),
        TaskTagPaletteOption(key: TaskTagColorKey.teal.rawValue, title: "Teal", color: Color(red: 0.21, green: 0.56, blue: 0.58)),
        TaskTagPaletteOption(key: TaskTagColorKey.gray.rawValue, title: "Gray", color: Color(red: 0.46, green: 0.48, blue: 0.50))
    ]

    static let defaultKey = TaskTagColorKey.slate.rawValue

    static func color(for key: String) -> Color {
        options.first(where: { $0.key == key })?.color ?? options[0].color
    }

    static func title(for key: String) -> String {
        options.first(where: { $0.key == key })?.title ?? options[0].title
    }
}
