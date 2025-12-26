# Taskr

Taskr is a lightweight macOS menu bar companion for rapidly capturing and organizing nested checklists. The app stays out of the way until you trigger it with your global hotkey (default `⌃⌥N`) or click the menu bar icon, letting you focus on the tasks you want to track.

## Features
- **Fast path-based capture** – Create deeply nested subtasks in one line using `/`-delimited paths with optional quoted segments.
- **Status menu and standalone window** – Use the compact popover for quick edits or open the full SwiftUI window when you need elbow room.
- ![Tasks view screenshot](docs/screenshots/01-Tasks.png)
- **Reusable templates** – Author checklist templates once and apply them to your live task list without duplicating work.
- ![Templates view screenshot](docs/screenshots/02-Templates.png)
- **Persistent hierarchy** – Duplicate, collapse, and clear tasks while Taskr keeps display order, completion state, and collapsed sections in sync.
- **Preferences in one place** – Tune hotkeys, insertion defaults, and menu bar styling without leaving the app.
- ![Settings view screenshot](docs/screenshots/03-Settings.png)
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

## Updating
Taskr does not include an in-app updater yet. To update:
- Quit Taskr.
- Download the latest release.
- Replace `Taskr.app` in `/Applications` with the new copy.
- Relaunch Taskr.

## License
Taskr is released under the MIT License. See [LICENSE](LICENSE) for details.
