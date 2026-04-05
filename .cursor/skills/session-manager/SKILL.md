---
name: session-manager
description: >-
  Manages AI session lifecycle for Crystal Server development. Handles session
  start (loading context from HANDOFF.md), session end (updating handoff,
  logging learnings), and continuous improvement tracking. Use when starting a
  new session, ending work, or when asked about project state, handoff, or
  session management.
---

# Session Manager

## Session Start

When a new conversation begins or the user asks about project state:

1. **Read** `docs/HANDOFF.md` — understand what was done last, current WIP, next steps
2. **Read** last 3 entries of `docs/SESSION_LOG.md` — recent pitfalls to avoid
3. **Check** `docs/INSTANCE_SYSTEM_ROADMAP.md` — which phase we're in
4. **Summarize** to user: "Current state: [what's done]. Next up: [what's planned]. Known issues: [blockers]."

## Session End

Before the session ends after significant work was done:

### 1. Update HANDOFF.md

Replace the entire content of `docs/HANDOFF.md` with fresh state:

```markdown
# Crystal Server — Current Handoff

> Last updated: [DATE] | Session: [brief description]

## What Was Done This Session
- [bullet points of completed work]

## Current State
- Build: [compiles? warnings?]
- Server: [boots? errors?]
- Last tested: [what was tested and result]

## Work In Progress
- [anything started but not finished]

## Next Steps (Priority Order)
1. [highest priority next task]
2. [second priority]
3. [etc.]

## Known Issues / Blockers
- [any bugs, warnings, or blockers]

## Key Decisions Made
- [architectural decisions with rationale]

## Files Modified This Session
- [list of files changed]
```

### 2. Append to SESSION_LOG.md

Append a new entry (never overwrite existing entries):

```markdown
---

## [DATE] — [Session Title]

**Summary:** [1-2 sentence overview]

**Completed:**
- [what was done]

**Learnings:**
- [pitfalls discovered, patterns that work, things to remember]

**Decisions:**
- [any architectural or design decisions with rationale]

**Next Session Should:**
- [what the next session should start with]
```

### 3. Update Roadmap (if applicable)

If any roadmap milestones were completed or if phase status changed, update the relevant section in `docs/INSTANCE_SYSTEM_ROADMAP.md`.

## Continuous Improvement

Each session should check:
- Are the cursor rules still accurate? If not, update them.
- Did we discover a new pitfall? Add it to the relevant rule.
- Did the architecture change? Update `docs/ARCHITECTURE.md`.
- Is the roadmap still accurate? Update phase status.

This creates a **feedback loop**: each session improves the documentation that makes the next session smoother.
