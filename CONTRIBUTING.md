# Contributing to Taskr

Thanks for your interest in improving Taskr! This document explains how to set up your environment, follow the existing conventions, and submit thoughtful pull requests.

## Development Environment
1. Install the latest Xcode 15.x release (SwiftData requires macOS 14+
   and Xcode 15.4 or newer).
2. Clone the repository and open the project:
   ```bash
   git clone https://github.com/your-org/taskr.git
   cd taskr
   open taskr.xcodeproj
   ```
3. Trust the developer certificate the first time you build so Xcode can run
   the menu bar app locally.

## Coding Standards
- Swift code uses four-space indentation and follows the Swift API design guidelines.
- Business logic should flow through `TaskManager` helpers so display ordering,
  template state, and collapsed IDs stay in sync.
- Keep UI logic inside SwiftUI views; non-trivial view-specific helpers belong
  in small `View` extensions or dedicated types.
- Avoid introducing non-ASCII characters unless the surrounding file already
  relies on them.
- Comment sparingly—only for nuanced behavior that is not obvious from the
  code (e.g., SwiftData migrations or drag-and-drop edge cases).

## Running the App
```bash
xcodebuild -project taskr.xcodeproj -scheme taskr -configuration Debug build
xcodebuild -project taskr.xcodeproj -scheme taskr -configuration Debug run
```
On first launch macOS will request Accessibility permissions to allow the
`⌃⌥N` global hotkey. Approve the prompt from **System Settings → Privacy &
Security → Accessibility**.

## Tests
All automated tests live in the `taskrTests` target.

```bash
xcodebuild \
  -project taskr.xcodeproj \
  -scheme taskr \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  test
```

Guidelines for new tests:
- Use an in-memory `ModelContainer` (`ModelConfiguration(isStoredInMemoryOnly: true)`).
- Exercise task creation, reordering, template application, import/export, and
  UserDefaults migrations.
- Prefer constructing fixtures with the helpers already exposed on `TaskManager`.

## Git Workflow
1. Create a feature branch from `main`.
2. Commit changes with imperative, scope-sized subjects (e.g., `Add JSON export regression tests`).
3. Run the full build and test commands above.
4. Open a pull request that includes:
   - A short feature summary + screenshots or screen recordings for UI changes.
   - Mention of any SwiftData schema or user preferences that changed.
   - Notes about new permissions (e.g., Accessibility) if required.

## Pull Request Checklist
- [ ] Code builds and runs in Debug configuration
- [ ] `xcodebuild … test` passes locally
- [ ] UI strings are localized or hard-coded intentionally
- [ ] New settings persist through `AppPreferences.swift`
- [ ] Documentation (README, docs/) updated as needed

We appreciate your help making Taskr a reliable companion for busy Mac users!
