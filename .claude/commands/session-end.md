# Session End

Update all living documentation before ending the session.

## 1. Update HANDOFF.md

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

## 2. Append to SESSION_LOG.md

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

## 3. Update Roadmap (if applicable)

If any roadmap milestones were completed or if phase status changed, update the relevant section in `docs/INSTANCE_SYSTEM_ROADMAP.md`.

## 4. Continuous Improvement

Check and update if needed:
- Are the CLAUDE.md conventions still accurate? If not, update them.
- Did we discover a new pitfall? Add it to CLAUDE.md.
- Did the architecture change? Update `docs/ARCHITECTURE.md`.
- Is the roadmap still accurate? Update phase status.
