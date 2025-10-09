# Taskr

Taskr is a lightweight macOS menu bar companion for rapidly capturing and organizing nested checklists. The app stays out of the way until you trigger it with the global hotkey (`⌃⌥N`) or click the menu bar icon, letting you focus on the tasks you want to track.

## Features
- **Fast path-based capture** – Create deeply nested subtasks in one line using `/`-delimited paths with optional quoted segments.
- **Status menu and standalone window** – Use the compact popover for quick edits or open the full SwiftUI window when you need elbow room.
- **Reusable templates** – Author checklist templates once and apply them to your live task list without duplicating work.
- **Persistent hierarchy** – Duplicate, collapse, and clear tasks while Taskr keeps display order, completion state, and collapsed sections in sync.
- **Import & export** – Round-trip non-template tasks as JSON so you can back up or share curated lists.

## Requirements
- macOS 14.0 or newer
- Xcode 15.4 or newer (SwiftData + SwiftUI)

## Getting Started
```bash
# Open the project in Xcode
open taskr.xcodeproj

# Or build from the command line
xcodebuild -project taskr.xcodeproj -scheme taskr -configuration Debug build
```

When you run the app for the first time macOS will prompt for accessibility access so Taskr can register the global hotkey. Approve the request from **System Settings → Privacy & Security → Accessibility**.

## Project Structure
- `taskrApp.swift` – Application entry point and SwiftData container wiring.
- `AppDelegate.swift` – Menu bar status item lifecycle, popover handling, and global hotkey / accessibility prompts.
- `TaskManager.swift` + extensions – Centralized task, template, and autocomplete orchestration (all `@MainActor`).
- `TaskView.swift`, `TemplateView.swift`, `SettingsView.swift` – Primary SwiftUI surfaces for live tasks, templates, and preferences.
- `DataModels.swift` – SwiftData models for `Task` and `TaskTemplate`.
- `ImportExport.swift` – JSON round-trip helpers.
- `WindowConfigurator.swift` – Window appearance and autosave behavior.

## Development Tips
- Task creation routes through `TaskManager.addTaskFromPath`, maintaining display order and collapsed-state persistence.
- Template editing helpers live in `TaskManager+Templates.swift`, mirroring the live-task APIs so template updates stay consistent.
- Autocomplete and copy-path logic is handled by `TaskManager+PathInput.swift` and is safe to reuse anywhere you surface path entry.

## Testing
Automated tests live in the `taskrTests` target (see [Contributing](CONTRIBUTING.md)). The test suite uses an in-memory `ModelContainer` so ordering and template behaviors stay deterministic.

## Roadmap
We’re keeping the near-term roadmap intentionally focused on three big ideas:

1. **CLI Support** – Add a `taskr` command-line companion so you can add, list, and complete tasks without leaving the terminal.
2. **Sync Service** – Explore a lightweight server-backed sync so multiple Macs stay up to date automatically.
3. **Mobile Companion** – Prototype a phone/tablet edition that mirrors the Taskr hierarchy on the go.

If another idea excites you, open an issue and let’s talk!

## Contributing
Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details on the preferred workflow, coding standards, and how to run the test suite before opening a pull request.

## License
Taskr is released under the MIT License. See [LICENSE](LICENSE) for details.
