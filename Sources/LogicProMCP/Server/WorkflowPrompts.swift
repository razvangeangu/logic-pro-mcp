import Foundation
import MCP

enum WorkflowPromptProvider {
    static func list(snapshot: WorkflowSkillSnapshot = WorkflowSkillCatalog.defaultSnapshot()) -> ListPrompts.Result {
        ListPrompts.Result(
            prompts: snapshot.workflows.map { workflow in
                Prompt(
                    name: workflow.id,
                    title: workflow.title,
                    description: workflow.intent
                )
            },
            nextCursor: nil
        )
    }

    static func get(name: String, snapshot: WorkflowSkillSnapshot = WorkflowSkillCatalog.defaultSnapshot()) throws -> GetPrompt.Result {
        guard let workflow = WorkflowSkillCatalog.workflow(id: name, snapshot: snapshot) else {
            throw MCPError.invalidParams("Unknown prompt: \(name)")
        }
        let text = encodeJSON(workflow, compact: true)
        return GetPrompt.Result(
            description: workflow.intent,
            messages: [
                .user(.text(text: text)),
            ]
        )
    }
}

