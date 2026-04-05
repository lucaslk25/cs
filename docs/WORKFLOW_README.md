# Crystal Server — AI Workflow Guide

> How to use the AI-assisted development workflow for smooth, continuous sessions.

---

## Quick Start

Open Cursor in this project. The workflow activates automatically — no setup needed.

When you start a new chat, the AI will:
1. Read the handoff document to understand current state
2. Check recent session logs for pitfalls to avoid
3. Tell you what's ready to work on next

Just say what you want to do and the system handles context.

---

## How the System Works

```
 YOU open a new Cursor session
  │
  ▼
 Coordinator Rule (always-apply) auto-injects into the AI
  │
  ├── AI reads docs/HANDOFF.md        → knows current state
  ├── AI reads docs/SESSION_LOG.md    → knows recent pitfalls
  └── AI reads docs/ROADMAP           → knows the plan
  │
  ▼
 You work normally — ask questions, request changes, debug
  │
  ├── C++ file open? → crystal-cpp rule injects conventions
  ├── Lua file open? → crystal-lua rule injects conventions
  └── Instance files? → instance-system rule injects architecture
  │
  ▼
 Session ends — AI updates the living documents
  │
  ├── docs/HANDOFF.md      ← fresh state for next session
  ├── docs/SESSION_LOG.md  ← new learning entry appended
  └── docs/ROADMAP         ← milestone checkboxes updated
```

---

## The Documents

### `docs/HANDOFF.md` — "Where are we right now?"

This is the most important file. It contains:
- What was done in the last session
- Current build/server state
- Work in progress
- Next steps in priority order
- Known issues and blockers
- Key decisions and their rationale
- List of files modified

**Updated:** Every session end. The AI replaces its entire content with fresh state.

### `docs/SESSION_LOG.md` — "What did we learn?"

Append-only journal. Each session adds an entry with:
- Date and title
- What was completed
- Learnings and pitfalls discovered
- Decisions made and why
- What the next session should start with

**Updated:** Every session end. New entries appended at the bottom, never overwritten.

**Why it matters:** Prevents debugging the same issue twice. If you hit a weird Lua stack error, the log likely has the fix from a previous session.

### `docs/ARCHITECTURE.md` — "How does the system work?"

Complete technical reference for the instance system:
- C++ classes and their roles
- Lua loading order and lifecycle
- Zone flood-fill algorithm details
- Instance isolation model
- Lua API reference
- Teleport taxonomy

**Updated:** When the architecture changes (new classes, new APIs, changed flows).

### `docs/INSTANCE_SYSTEM_ROADMAP.md` — "What's the plan?"

Phase-based implementation plan with checkboxes:
- Phase 0: Hunt discovery infrastructure (COMPLETE)
- Phase 1: Instance hunt MVP (NEXT — stamina, selection UI, costs)
- Phase 2: UI polish
- Phase 3: Testing and balancing
- Phase 4: Production

**Updated:** When milestones are completed or priorities shift.

---

## The Rules (`.cursor/rules/`)

Rules inject automatically based on context. You never need to reference them manually.

| Rule | When It Activates | What It Does |
|------|-------------------|--------------|
| `crystal-coordinator.mdc` | Every session | Bootstraps context, enforces handoff protocol, lists key files |
| `crystal-cpp.mdc` | Any `src/**` file open | C++ naming, build commands, Lua binding patterns, pitfall warnings |
| `crystal-lua.mdc` | Any `data/**/*.lua` file open | Loading order, key APIs, teleport system, common mistakes |
| `instance-system.mdc` | Instance/zone files open | Architecture flow, data flow diagram, expansion logic |

---

## The Skills (`.cursor/skills/`)

Skills are invoked when relevant. The AI reads them when it recognizes the task matches.

| Skill | When It's Used |
|-------|---------------|
| `session-manager` | Starting a session, ending a session, updating handoff or learnings |
| `hunt-instance-dev` | Working on hunt instances, `/hunt` commands, zone building, testing |

---

## Common Workflows

### Starting a New Session

Just open Cursor and start chatting. The AI picks up context automatically.

If you want to be explicit:
> "Check the handoff and tell me what's next."

### Continuing Previous Work

> "Continue where we left off."

The AI reads HANDOFF.md and picks up the next priority item.

### Reporting a Bug

> "I'm getting this error: [paste error]"

The AI checks SESSION_LOG.md for similar past issues, then debugs with full architecture context.

### Adding a New Hunt

> "Let's register a new hunt at [location]."

The AI uses the hunt-instance-dev skill for the step-by-step process:
1. Position your character near the entrance
2. `/hunt discover`
3. Validate with `/hunt goto`
4. `/hunt test` to try the instance
5. `/hunt save` to persist

### Making Architecture Changes

> "I need to add [feature] to the instance system."

The AI reads ARCHITECTURE.md for the current system model, proposes changes, implements them, and updates the architecture doc afterward.

### Ending a Session

> "Let's wrap up."

Or the AI does it automatically when the conversation is ending. It:
1. Updates HANDOFF.md with everything that was done
2. Appends a learning entry to SESSION_LOG.md
3. Updates the roadmap if milestones changed
4. Notes any new pitfalls in the relevant cursor rules

---

## Maintaining the System

### If a Rule Becomes Outdated

Edit the `.mdc` file directly in `.cursor/rules/`. Keep rules under 50 lines — concise and actionable.

### If a Learning is Missing

Ask the AI:
> "Add to the session log that [pitfall/learning]."

Or edit `docs/SESSION_LOG.md` directly.

### If the Architecture Changes

Ask the AI:
> "Update ARCHITECTURE.md — we changed [what changed]."

### If the Roadmap Needs Adjusting

Edit `docs/INSTANCE_SYSTEM_ROADMAP.md` directly, or ask:
> "Move [task] to Phase 2 and mark [task] as complete."

---

## File Map

```
.cursor/
├── rules/
│   ├── crystal-coordinator.mdc    # Always-apply session bootstrap
│   ├── crystal-cpp.mdc            # C++ conventions (src/**)
│   ├── crystal-lua.mdc            # Lua conventions (data/**/*.lua)
│   └── instance-system.mdc        # Instance architecture context
├── skills/
│   ├── session-manager/
│   │   └── SKILL.md               # Session lifecycle management
│   └── hunt-instance-dev/
│       └── SKILL.md               # Hunt development workflow
└── handoff-instanced-hunt-teleport.md  # Legacy handoff (historical)

docs/
├── HANDOFF.md                     # Living state — updated every session
├── SESSION_LOG.md                 # Append-only learning journal
├── ARCHITECTURE.md                # System architecture reference
├── INSTANCE_SYSTEM_ROADMAP.md     # Phase-based plan with checkboxes
├── WORKFLOW_README.md             # This file
├── hunt_discover_review_fixes.md  # Review/fix tracker
├── HUNT_INSTANCE_TESTING.md       # Testing notes
├── PREY_SYSTEM_ANALYSIS.md        # Prey system reference (for hunt UI design)
└── QUICK_START.md                 # Server setup guide
```

---

## Design Principles

1. **Zero friction** — Rules inject automatically. No manual steps to "activate" the workflow.
2. **Self-improving** — Each session's learnings become the next session's context. Pitfalls discovered get added to rules so they're never repeated.
3. **Living over static** — HANDOFF.md is always current, never stale. SESSION_LOG.md only grows. The roadmap tracks real progress.
4. **Progressive disclosure** — The coordinator rule gives just enough context to start. Skills and architecture docs provide depth on demand.
5. **Fail-safe** — If the AI forgets to update the handoff, the session log still captures what happened. If both are missed, the git diff tells the story.
