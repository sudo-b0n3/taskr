// taskr/taskr/TemplateView.swift
import SwiftUI
import SwiftData

struct TemplateView: View {
    @EnvironmentObject var taskManager: TaskManager
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\TaskTemplate.name)]) private var templates: [TaskTemplate]
    @State private var editingTemplateID: UUID? = nil
    @State private var editingTemplateName: String = ""
    private var palette: ThemePalette { taskManager.themePalette }
    private var backgroundColor: Color {
        taskManager.frostedBackgroundEnabled ? .clear : palette.backgroundColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { // Main VStack

            // --- Add Template Section ---
            HStack {
                TextField("New Template Name", text: $taskManager.newTemplateName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button(action: { taskManager.addTemplate() }) {
                    Label("Add Template", systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Create a new empty template")
                .padding(.leading, 4)
            }
            .padding([.horizontal, .top]).padding(.bottom, 8) // Padding for this section
            // --- End Add Template Section ---

            // --- Add Divider Here ---
            Divider().background(palette.dividerColor)
            // --- End Divider ---

            // --- Template List Section ---
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if templates.isEmpty {
                        Text("No templates yet. Add one above!")
                            .foregroundColor(palette.secondaryTextColor)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        ForEach(templates, id: \.persistentModelID) { template in
                            VStack(alignment: .leading, spacing: 0) {
                                HStack {
                                    // Expand/collapse chevron based on the template's container task ID
                                    let containerID = template.taskStructure?.id
                                    let isExpanded = containerID.map { taskManager.isTaskExpanded($0) } ?? false
                                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(palette.secondaryTextColor)
                                        .padding(5)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            if let id = containerID { taskManager.toggleTaskExpansion(id) }
                                        }

                                    if editingTemplateID == template.id {
                                        TextField("", text: $editingTemplateName, onCommit: {
                                            commitTemplateNameEdit(template)
                                        })
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .frame(maxWidth: 220)
                                        .onSubmit { commitTemplateNameEdit(template) }
                                        .onDisappear { if editingTemplateID == template.id { commitTemplateNameEdit(template) } }
                                    } else {
                                        Text(template.name)
                                            .font(.headline)
                                            .onTapGesture(count: 2) {
                                                editingTemplateID = template.id
                                                editingTemplateName = template.name
                                            }
                                    }
                                    Spacer()
                                    // Apply template to live tasks
                                    Button(action: { taskManager.applyTemplate(template) }) {
                                        Label("Apply", systemImage: "tray.and.arrow.down")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .help("Instantiate these tasks in the main list")
                                    // Add a root-level task under this template
                                    Button { taskManager.addTemplateRootTask(to: template) } label: {
                                        Label("Add Item", systemImage: "plus")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .help("Add a new root task to this template")
                                    // Delete template
                                    Button { deleteTemplate(template) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .foregroundColor(.red)
                                    .help("Delete this template")
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)

                                if let container = template.taskStructure,
                                   taskManager.isTaskExpanded(container.id) {
                                    // Render the template's root tasks using the same row view in template mode
                                    let subs = (container.subtasks ?? []).sorted { $0.displayOrder < $1.displayOrder }
                                    ForEach(subs, id: \.persistentModelID) { t in
                                        TaskRowView(task: t, mode: .template)
                                            .padding(.leading, 20)
                                            .padding(.vertical, 4)
                                        if t.persistentModelID != subs.last?.persistentModelID {
                                            Divider().background(palette.dividerColor).padding(.leading, 20)
                                        }
                                    }
                                }
                            }
                            Divider().background(palette.dividerColor)
                        }
                    }
                }
            }
            // --- End Template List Section ---
        }
        .foregroundColor(palette.primaryTextColor)
        .background(backgroundColor)
    }

    private func commitTemplateNameEdit(_ template: TaskTemplate) {
        let trimmed = editingTemplateName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && template.name != trimmed {
            template.name = trimmed
            try? modelContext.save()
        }
        editingTemplateID = nil
        editingTemplateName = ""
    }

    private func deleteTemplate(_ template: TaskTemplate) {
        modelContext.delete(template)
        try? modelContext.save()
        taskManager.pruneCollapsedState()
    }
}

// Preview Provider remains the same
struct TemplateView_Previews: PreviewProvider {
    static var previews: some View {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Task.self, TaskTemplate.self, configurations: config)
        let taskManager = TaskManager(modelContext: container.mainContext)

        let previewTemplateStructure = Task(name: "TEMPLATE_INTERNAL_ROOT_CONTAINER", isTemplateComponent: true)
        container.mainContext.insert(previewTemplateStructure)
        let previewTemplateTask = Task(name: "Task from Template Preview", isTemplateComponent: true, parentTask: previewTemplateStructure)
        container.mainContext.insert(previewTemplateTask)
        previewTemplateStructure.subtasks = [previewTemplateTask]

        let template1 = TaskTemplate(name: "Preview Template A", taskStructure: previewTemplateStructure)
        container.mainContext.insert(template1)
        let template2 = TaskTemplate(name: "Preview Template B")
        container.mainContext.insert(template2)

        return TemplateView()
            .modelContainer(container)
            .environmentObject(taskManager)
            .frame(width: 380, height: 400)
            .background(taskManager.themePalette.backgroundColor)
    }
}
