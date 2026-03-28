# Skill Development Guide

How to create, test, and maintain cto-fleet skills.

## Quick Start

1. Copy the template: `cp SKILL-TEMPLATE.md team-{name}/SKILL.md`
2. Fill in the YAML frontmatter (name, description, argument-hint)
3. Keep the Preamble section unchanged
4. Define your parameters, roles, and workflow
5. Run `bin/sync-protocols --fix` to inject protocol sections
6. Add your skill to the router (`team/SKILL.md`) decision matrix

## Directory Structure

```
team-{name}/
  SKILL.md          # The skill definition (required)
```

Each skill is a single directory with a `SKILL.md` file. The `setup` script creates symlinks in `~/.claude/skills/` pointing to these directories.

## SKILL.md Structure

Every SKILL.md follows this structure (see `SKILL-TEMPLATE.md` for a ready-to-use template):

### 1. YAML Frontmatter

```yaml
---
name: team-{domain}
description: {1-2 sentence description with usage example}
argument-hint: {parameter summary}
---
```

**`name`**: Must match the directory name.

**`description`**: Include:
- What the skill does (team composition, method)
- Usage example: `/team-{name} [params] task description`

**`argument-hint`**: Shows in auto-complete. Format:
```
[--auto] [--once] [--domain-param=values] [--lang=zh|en] task description
```

### 2. Preamble

Auto-injected by `bin/sync-protocols`. Never modify manually.

### 3. Parameter Parsing

Standard parameters first (--auto, --once, --lang), then domain-specific ones.
Include the mode behavior matrix table.
See `docs/PARAMETER-SPEC.md` for naming conventions.

### 4. Flow Overview

ASCII diagram showing the high-level workflow stages.

### 5. Role Definitions

Table with role names and responsibilities. Key rules:
- Clearly state what each role does NOT do
- Analysts/reviewers do not write code
- Coders/fixers do not make design decisions

### 6. Detailed Workflow Stages

Numbered steps with:
- Clear entry/exit criteria
- Decision points marked for each mode (standard/once/auto)
- Circuit breakers for dangerous auto-decisions

### 7. Error Handling (optional)

Table of failure scenarios and recovery procedures.

### 8. Core Principles (optional)

3-5 guiding principles for the skill's operation.

### 9. Needs Section

Always end with:
```
## Needs

$ARGUMENTS
```

## Design Patterns

### Dual-Analysis Pattern

Most cto-fleet skills use two independent analysts/reviewers for the same task.

```
Task → Analyst-1 (independent) ──→ Merge + Cross-calibrate → Report
     → Analyst-2 (independent) ──↗
```

- Analysts work independently (no communication during analysis)
- Team lead merges results and calculates consensus
- Cross-calibration: each sees the other's results and can adjust their own scores
- Consensus < 50% triggers circuit breaker

### Iterative Improvement Pattern

```
Analyze → Fix → Verify → Score → (loop if not meeting threshold)
```

- Maximum iteration count (typically 3-5)
- Each round must show measurable improvement
- Stagnation (score change < threshold) triggers user escalation

### Circuit Breaker Pattern

Certain conditions ALWAYS pause execution regardless of --auto/--once:
- Iteration count exceeds limit
- Score divergence between analysts too large
- Critical safety issue detected

## Naming Conventions

| Item | Convention | Example |
|------|-----------|---------|
| Skill directory | `team-{domain}` | `team-perf`, `team-security` |
| Team name | `team-{domain}-{YYYYMMDD-HHmmss}` | `team-perf-20260327-143022` |
| Role names | lowercase descriptive | `scanner`, `analyzer-1`, `fixer` |
| Parameter names | lowercase kebab-case | `--target-locales`, `--team-size` |

## Testing Your Skill

1. **Syntax check**: Ensure the markdown renders correctly
2. **Protocol check**: `bin/sync-protocols --skills=team-{name}`
3. **Parameter check**: Verify parameters match `docs/PARAMETER-SPEC.md`
4. **Router check**: Ensure `team/SKILL.md` has your skill in the decision matrix
5. **Dry run**: Test with a small, safe task using `--once` mode

## Adding to the Router

Update `team/SKILL.md` with:
1. Add intent signals to the decision matrix table
2. Add parameter list to the skill entry
3. Add to the skill quick-reference table
4. Add any relevant combination patterns

## Checklist

Before submitting a new skill:

- [ ] Directory matches name in frontmatter
- [ ] Protocol sections present (preamble, handoff, etc.)
- [ ] Standard parameters (--auto/--once/--lang) documented
- [ ] Mode behavior matrix included
- [ ] Circuit breaker conditions defined
- [ ] Role responsibilities have explicit "does NOT" boundaries
- [ ] Consensus/scoring mechanism defined (if multi-analyst)
- [ ] Error handling table included
- [ ] Router updated with intent signals
- [ ] `bin/sync-protocols` passes (no drift)

## Protocol Management

Protocol sections (preamble, handoff, consensus, error-handling) are managed centrally and injected into skills automatically. Never hand-edit content between `<!-- X_SECTION_START -->` and `<!-- X_SECTION_END -->` markers.

### Source files

- `protocols/preamble.md` — update check + upgrade flow (injected into all skills)
- `HANDOFF.md` — file-based handoff protocol (TeamCreate skills only)
- `protocols/consensus.md` — consensus scoring (TeamCreate skills, excludes domain-specific)
- `protocols/error-handling.md` — standard error table (TeamCreate skills only)
- `protocols/registry.conf` — controls which protocols go where and in what order

### Common tasks

| Task | Command |
|------|---------|
| Check for drift (read-only) | `bin/sync-protocols` |
| Fix all drift | `bin/sync-protocols --fix` |
| Inject protocols into a new skill | Create the skill directory, then `bin/sync-protocols --fix` |
| Modify a protocol | Edit the source file in `protocols/`, then `bin/sync-protocols --fix` |
| Add a new protocol | Create source file with `<!-- NAME_START -->` / `<!-- NAME_END -->` markers, add a line to `registry.conf`, run `bin/sync-protocols --fix` |
