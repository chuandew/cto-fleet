# cto-fleet Parameter Specification

Defines the standard and domain-specific parameters used across all cto-fleet skills.

## Standard Parameters

All skills MUST support these parameters. They are always listed first in the parameter parsing section.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `--auto` | flag | off | Fully autonomous mode. No user questions, all decisions automatic. |
| `--once` | flag | off | Single-confirmation mode. One approval round, then auto-execute. |
| `--lang=zh\|en` | enum | `zh` | Output language. |

### Behavior Matrix

| Mode | User confirmations | Conditional decisions | Circuit breakers |
|------|-------------------|----------------------|-----------------|
| **Standard** (default) | All fixed + conditional nodes | Ask user | Active |
| **Single-confirm** (`--once`) | Fixed nodes only | Auto-decide, summarize at end | Active |
| **Autonomous** (`--auto`) | None | All auto-decide, summarize at end | Active |

Circuit breakers (e.g., >3 iterations, score divergence >2) ALWAYS pause regardless of mode.

## Domain Parameters

Domain parameters are skill-specific. Use the canonical names below when the concept matches.

### Scope Parameters

Control the breadth or target of analysis.

| Parameter | Values | Used by | Description |
|-----------|--------|---------|-------------|
| `--scope` | Varies by skill | team-refactor, team-security, team-deps, team-governance | Analysis scope/breadth |
| `--focus` | Varies by skill | team-perf, team-review, team-arch, team-test | Dimension or area to emphasize |
| `--module` | path | team-techdebt, team-capacity | Limit to specific module path |
| `--service` | name | team-observability, team-runbook | Target service name |
| `--target` | Varies | team-chaos, team-onboard | Target of operation |

**Naming rule**: Use `--scope` for breadth control (module|package|system), `--focus` for dimension filtering (cpu,memory,io), `--module` for filesystem paths, `--service` for named services.

### Time Parameters

| Parameter | Values | Used by | Description |
|-----------|--------|---------|-------------|
| `--period` | `1w\|2w\|1m\|3m\|6m\|1y` | team-dora, team-capacity, team-sprint, team-report | Analysis time window |
| `--from` | tag/commit/version | team-release, team-migration | Starting point |
| `--to` | tag/commit/version | team-migration | Ending point |

**Value convention**: Use abbreviated duration codes — `1w` (1 week), `2w`, `1m` (1 month), `3m`, `6m`, `1y` (1 year).

### Action Parameters

| Parameter | Values | Used by | Description |
|-----------|--------|---------|-------------|
| `--fix` | flag | team-test, team-accessibility, team-i18n, team-cicd | Auto-apply fixes |
| `--dry-run` | flag | team-chaos | Preview without executing |
| `--compare` | flag | team-dora | Compare with previous period |
| `--evidence` | flag | team-compliance | Generate evidence artifacts |
| `--update` | flag | team-runbook | Update existing documents |
| `--action` | Varies | team-feature-flag, team-schema | Operation type |

### Classification Parameters

| Parameter | Values | Used by | Description |
|-----------|--------|---------|-------------|
| `--type` | Varies | team-rfc, team-release | Content/release type |
| `--framework` | Varies | team-compliance, team-threat-model, team-governance | Standard/framework |
| `--style` | Varies | team-api-design, team-contract-test | API/design style |
| `--level` | Varies | team-accessibility, team-interview | Quality/seniority level |
| `--severity` | `P0\|P1\|P2\|P3` | team-incident | Incident severity |
| `--platform` | Varies | team-cicd | CI/CD platform |
| `--db` | Varies | team-schema | Database engine |
| `--stack` | Varies | team-observability | Monitoring stack |
| `--provider` | Varies | team-feature-flag | Feature flag provider |

### Content Parameters

| Parameter | Values | Used by | Description |
|-----------|--------|---------|-------------|
| `--title` | string | team-adr | Document title |
| `--query` | string | team-adr | Search keywords |
| `--candidates` | list | team-vendor | Comma-separated candidate list |
| `--usecase` | string | team-vendor | Use case description |
| `--role` | enum | team-interview | Target role |
| `--count` | number | team-interview | Number of items to generate |
| `--target-locales` | list | team-i18n | Comma-separated locale codes |
| `--team-size` | number | team-sprint | Team size for planning |
| `--modules` | list | team-cto-briefing | Comma-separated module list |
| `--skip` | list | team-cto-briefing | Modules to skip |
| `--depth` | `quick\|standard\|deep` | team-research, team-arch | Analysis depth |
| `--mode` | Varies | team-report | Report audience mode |

## Value Format Conventions

| Convention | Usage | Example |
|-----------|-------|---------|
| `\|` (pipe) | Mutually exclusive options | `--scope=module\|package\|system` |
| `,` (comma) | Multiple selections | `--focus=cpu,memory,io` |
| `=` (equals) | Value assignment | `--lang=zh` |
| No value | Boolean flag | `--fix`, `--auto` |

## Defaults Documentation

Every parameter with possible values MUST document its default in one of these formats:

- **Inline**: `--period=1w|2w|1m|3m (default: 2w)`
- **Table**: Include a "Default" column

## Adding New Parameters

When creating a new skill:

1. Check if an existing canonical parameter name fits your use case
2. If yes, use the canonical name (values can differ per skill)
3. If no, choose a descriptive name following these conventions:
   - Use lowercase kebab-case: `--target-locales` not `--targetLocales`
   - Prefer single words: `--scope` not `--analysis-scope`
   - Boolean actions are bare flags: `--fix` not `--fix=true`
4. Document the parameter in this spec file
5. Update the router (`team/SKILL.md`) parameter table
