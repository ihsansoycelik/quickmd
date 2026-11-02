import AppKit

/// Ready-made documents for File › New from Template. Dates are
/// filled in when the document is made.
enum Starter: String, CaseIterable {
    case blank, note, meeting, todo, journal, weekly, project, readme, blog, decision

    var displayName: String {
        switch self {
        case .blank: return "Blank"
        case .note: return "Note"
        case .meeting: return "Meeting Notes"
        case .todo: return "To-Do List"
        case .journal: return "Daily Journal"
        case .weekly: return "Weekly Review"
        case .project: return "Project Plan"
        case .readme: return "README"
        case .blog: return "Blog Post"
        case .decision: return "Decision Record"
        }
    }

    /// SF Symbol shown next to the name in menus.
    var symbol: String {
        switch self {
        case .blank: return "doc"
        case .note: return "note.text"
        case .meeting: return "person.2"
        case .todo: return "checklist"
        case .journal: return "sun.max"
        case .weekly: return "calendar"
        case .project: return "flag"
        case .readme: return "book.closed"
        case .blog: return "text.quote"
        case .decision: return "signpost.right"
        }
    }

    var text: String {
        let today = Self.date(.long)
        let iso = Self.date(nil)
        switch self {
        case .blank:
            return ""
        case .note:
            return """
            # Untitled Note

            \(today)

            Start writing here.

            """
        case .meeting:
            return """
            # Meeting Notes

            **Date:** \(today)\\
            **Attendees:**\\
            **Goal:**

            ## Agenda

            1.
            2.
            3.

            ## Notes

            -

            ## Decisions

            -

            ## Action Items

            - [ ] Who — what — by when
            - [ ]

            """
        case .todo:
            return """
            # To-Do

            ## Today

            - [ ]
            - [ ]
            - [ ]

            ## This Week

            - [ ]

            ## Later

            - [ ]

            ## Done

            - [x] Make a list

            """
        case .journal:
            return """
            # \(today)

            ## Grateful for

            1.
            2.
            3.

            ## What would make today great

            -

            ## Notes



            ## Tonight

            > What went well? What did I learn?

            """
        case .weekly:
            return """
            # Weekly Review — \(iso)

            ## Wins

            -

            ## What didn't go well

            -

            ## Lessons

            -

            ## Next week's priorities

            - [ ]
            - [ ]
            - [ ]

            """
        case .project:
            return """
            # Project Name

            > [!NOTE]
            > One sentence: what this project is and why it matters.

            ## Goals

            -

            ## Non-goals

            -

            ## Milestones

            | Milestone | Owner | Due | Status |
            | --- | --- | --- | --- |
            | Kickoff |  | \(iso) | Planned |
            |  |  |  |  |

            ## Risks

            -

            ## Open Questions

            - [ ]

            """
        case .readme:
            return """
            # Project Name

            A short description of what this does and who it's for.

            ## Install

            ```sh
            # how to install
            ```

            ## Usage

            ```sh
            # how to run it
            ```

            ## Features

            -
            -

            ## Contributing

            Pull requests are welcome.

            ## License

            MIT

            """
        case .blog:
            return """
            ---
            title: Post Title
            date: \(iso)
            tags: []
            ---

            # Post Title

            *A one-line hook that makes people want to read on.*

            ## Introduction



            ## Main Point



            ## Conclusion



            """
        case .decision:
            return """
            # Decision: Title

            **Date:** \(today)\\
            **Status:** Proposed

            ## Context

            What is the problem, and why decide now?

            ## Options

            1. **Option A** — pros / cons
            2. **Option B** — pros / cons

            ## Decision

            We chose …

            ## Consequences

            -

            """
        }
    }

    private static func date(_ style: DateFormatter.Style?) -> String {
        let formatter = DateFormatter()
        if let style {
            formatter.dateStyle = style
            formatter.timeStyle = .none
        } else {
            // ISO dates are Gregorian with ASCII digits whatever the region.
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
        }
        return formatter.string(from: Date())
    }
}

/// The app's document controller: opens new documents from a
/// template and replaces an untouched blank window when a file opens.
@MainActor
final class QuickMDDocumentController: NSDocumentController {
    override func newDocument(_ sender: Any?) {
        newDocument(from: Settings.newDocumentStarter)
    }

    @objc func newDocumentFromTemplate(_ sender: NSMenuItem) {
        guard let starter = Starter(rawValue: sender.representedObject as? String ?? "") else { return }
        newDocument(from: starter)
    }

    @objc func showHelp(_ sender: Any?) {
        // Unchanged, so closing it asks nothing.
        _ = openUntitled(text: Help.text)
    }

    func newDocument(from starter: Starter) {
        if let document = openUntitled(text: starter.text), !document.text.isEmpty {
            document.updateChangeCount(.changeDone)
            document.editor?.placeCaretAtFirstBlank()
        }
    }

    private func openUntitled(text: String) -> MarkdownDocument? {
        do {
            guard let type = defaultType,
                  let document = try makeUntitledDocument(ofType: type) as? MarkdownDocument else { return nil }
            document.text = text
            addDocument(document)
            document.makeWindowControllers()
            document.showWindows()
            return document
        } catch {
            presentError(error)
            return nil
        }
    }
}
