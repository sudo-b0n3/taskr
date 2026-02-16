import SwiftUI
import SwiftData

struct TagView: View {
    @EnvironmentObject var taskManager: TaskManager

    @Query(sort: [SortDescriptor(\TaskTag.displayOrder, order: .forward)])
    private var tags: [TaskTag]

    @State private var newTagPhrase: String = ""
    @State private var selectedColorKey: String = TaskTagPalette.defaultKey

    private var palette: ThemePalette { taskManager.themePalette }
    private var backgroundColor: Color {
        taskManager.frostedBackgroundEnabled ? .clear : palette.backgroundColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            addTagSection
            Divider().background(palette.dividerColor)
            tagList
        }
        .foregroundColor(palette.primaryTextColor)
        .background(backgroundColor)
    }

    private var addTagSection: some View {
        HStack(alignment: .top, spacing: 8) {
            ExpandingTaskInput(
                text: $newTagPhrase,
                placeholder: "New Tag Phrase",
                onCommit: { createTagFromDraft() },
                onTextChange: { _ in },
                onTab: { },
                onShiftTab: { },
                onArrowDown: { false },
                onArrowUp: { false },
                fieldTextColor: palette.primaryText,
                placeholderTextColor: palette.secondaryText
            )
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(palette.controlBackgroundColor)
                .cornerRadius(10)

            Menu {
                colorSelectionMenu(selectedKey: selectedColorKey) { key in
                    selectedColorKey = key
                }
            } label: {
                colorMenuLabel(selectedKey: selectedColorKey)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(minWidth: 32, minHeight: 28)
            .fixedSize()
            .accessibilityLabel("Tag color")
            .accessibilityValue(TaskTagPalette.title(for: selectedColorKey))
            .help("Tag color")

            Button(action: createTagFromDraft) {
                Image(systemName: "plus.circle.fill")
                    .taskrFont(.title2)
                    .foregroundColor(palette.accentColor)
            }
            .buttonStyle(PlainButtonStyle())
            .focusable(false)
            .padding(.vertical, 8)
            .padding(.trailing, -4)
        }
        .padding([.horizontal, .top])
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var tagList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if tags.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "tag")
                            .font(.system(size: 34))
                            .foregroundColor(palette.secondaryTextColor.opacity(0.5))
                        Text("No tags yet")
                            .taskrFont(.headline)
                            .foregroundColor(palette.primaryTextColor)
                        Text("Create reusable tags with a phrase and color.")
                            .taskrFont(.subheadline)
                            .foregroundColor(palette.secondaryTextColor)
                    }
                    .padding(.vertical, 40)
                    .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(tags, id: \.persistentModelID) { tag in
                        HStack(spacing: 10) {
                            tagChip(for: tag)
                            Spacer(minLength: 8)
                            Menu {
                                colorSelectionMenu(selectedKey: tag.colorKey) { key in
                                    taskManager.updateTag(tag, phrase: tag.phrase, colorKey: key)
                                }
                            } label: {
                                colorMenuLabel(selectedKey: tag.colorKey)
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()
                            .accessibilityLabel("Change tag color")
                            .accessibilityValue(TaskTagPalette.title(for: tag.colorKey))
                            .help("Change tag color")

                            Button(role: .destructive) {
                                taskManager.deleteTag(tag)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Delete tag")
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        Divider().background(palette.dividerColor)
                    }
                }
            }
        }
    }

    private func createTagFromDraft() {
        let phrase = newTagPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else { return }
        taskManager.createTag(phrase: phrase, colorKey: selectedColorKey)
        newTagPhrase = ""
    }

    @ViewBuilder
    private func colorSelectionMenu(selectedKey: String, onSelect: @escaping (String) -> Void) -> some View {
        ForEach(TaskTagPalette.options) { option in
            Button {
                onSelect(option.key)
            } label: {
                HStack(spacing: 8) {
                    Text("●")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(option.color)
                        .accessibilityHidden(true)
                    if selectedKey == option.key {
                        Image(systemName: "checkmark")
                            .foregroundColor(palette.primaryTextColor)
                            .accessibilityHidden(true)
                    }
                }
            }
            .accessibilityLabel(option.title)
            .accessibilityValue(selectedKey == option.key ? "Selected" : "")
        }
    }

    @ViewBuilder
    private func colorMenuLabel(selectedKey: String) -> some View {
        HStack(spacing: 0) {
            Text("●")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(TaskTagPalette.color(for: selectedKey))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(palette.controlBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(palette.dividerColor.opacity(0.7), lineWidth: 1)
        )
        .accessibilityLabel("Color")
        .accessibilityValue(TaskTagPalette.title(for: selectedKey))
    }

    @ViewBuilder
    private func tagChip(for tag: TaskTag) -> some View {
        Text(tag.phrase)
            .taskrFont(.caption)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(TaskTagPalette.color(for: tag.colorKey))
            .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

struct TagView_Previews: PreviewProvider {
    static var previews: some View {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Task.self, TaskTemplate.self, TaskTag.self, configurations: config)
        let taskManager = TaskManager(modelContext: container.mainContext)

        let urgent = TaskTag(phrase: "NOT IN DROPBOX", colorKey: TaskTagColorKey.blue.rawValue, displayOrder: 0)
        let blocked = TaskTag(phrase: "WAITING ON CLIENT", colorKey: TaskTagColorKey.amber.rawValue, displayOrder: 1)
        container.mainContext.insert(urgent)
        container.mainContext.insert(blocked)

        return TagView()
            .modelContainer(container)
            .environmentObject(taskManager)
            .environmentObject(taskManager.inputState)
            .environmentObject(taskManager.selectionManager)
            .environmentObject(AppDelegate())
            .frame(width: 380, height: 420)
            .background(taskManager.themePalette.backgroundColor)
    }
}
