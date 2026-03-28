# sync-protocols Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the hard-coded `bin/sync-preamble` with a registry-driven `bin/sync-protocols` engine that manages 4 protocol sections across all 45 SKILL.md files.

**Architecture:** A single bash script reads `protocols/registry.conf` to discover protocol definitions (source file, gate condition, exclude condition, insertion anchor). For each SKILL.md, it processes protocols in reverse declaration order (bottom-up) to preserve line numbers during splice operations. All protocols use `<!-- X_START -->` / `<!-- X_END -->` HTML comment markers.

**Tech Stack:** Bash (matching existing `bin/` scripts), shell unit tests (matching existing `tests/` pattern)

**Design doc:** `docs/plans/2026-03-29-protocol-extraction-design.md`

---

## Phase 1: Infrastructure

### Task 1: Create protocol source files

**Files:**
- Create: `protocols/registry.conf`
- Create: `protocols/preamble.md`
- Create: `protocols/consensus.md`
- Create: `protocols/error-handling.md`

**Step 1: Create `protocols/registry.conf`**

```conf
# Protocol registry — one protocol per line
# Format: SECTION_NAME | source_file | gate_condition | exclude_if | insertion_anchor
#
# gate_condition:
#   *           = all SKILL.md files
#   KEYWORD     = SKILL.md files containing KEYWORD
#
# exclude_if:
#   (empty)     = no exclusion
#   KEYWORD     = skip if SKILL.md contains this keyword
#
# insertion_anchor:
#   after_frontmatter  = after YAML frontmatter closing ---
#   after:KEYWORD      = after first line containing KEYWORD
#   end_of_file        = append to end

PREAMBLE_SECTION        | protocols/preamble.md        | *          |             | after_frontmatter
HANDOFF_SECTION         | HANDOFF.md                   | TeamCreate |             | after:TeamCreate
CONSENSUS_SECTION       | protocols/consensus.md       | TeamCreate | 共识发现数  | end_of_file
ERROR_HANDLING_SECTION  | protocols/error-handling.md   | TeamCreate |             | end_of_file
```

**Step 2: Create `protocols/preamble.md`**

Extract the canonical preamble from `team-dev/SKILL.md` (the reference skill), wrap it with `<!-- PREAMBLE_SECTION_START -->` and `<!-- PREAMBLE_SECTION_END -->` markers. The content between markers must be the exact preamble text currently in team-dev/SKILL.md (from `## Preamble (run first)` through the instruction paragraph, NOT including the trailing `---` separator).

To get the exact content, read team-dev/SKILL.md and extract lines from `## Preamble (run first)` to (but not including) the `---` line after it. Wrap with markers.

**Step 3: Create `protocols/consensus.md`**

```markdown
<!-- CONSENSUS_SECTION_START -->
### 共识度计算

team lead 按五维度评估双路分析的共识度：

| 维度 | 权重 |
|------|------|
| 发现一致性（相同问题/结论） | 20% |
| 互补性（独有但不矛盾的发现） | 20% |
| 分歧程度（直接矛盾的结论） | 20% |
| 严重度一致性（同一问题的严重等级差异） | 20% |
| 覆盖完整性（两路合并后的覆盖面） | 20% |

共识度 = 各维度加权得分之和

- **≥ 60%**：自动合并，分歧项由 team lead 裁决
- **50-59%**：合并但标注分歧，收尾时汇总争议点
- **< 50%**：触发熔断，暂停并向用户确认方向
<!-- CONSENSUS_SECTION_END -->
```

**Step 4: Create `protocols/error-handling.md`**

```markdown
<!-- ERROR_HANDLING_SECTION_START -->
### 错误处理

| 场景 | 处理方式 |
|------|---------|
| Teammate 无响应/崩溃 | Team lead 重新启动同名 teammate（传入完整上下文），从最近的检查点恢复 |
| 某阶段产出质量不达标 | 记录问题，在收尾阶段汇总，不阻塞后续流程（除非是熔断条件） |
| 用户中途修改需求 | 暂停当前阶段，重新评估影响范围，必要时回退到受影响的最早阶段 |

### 熔断机制（不可跳过）

以下条件触发时，**无论 `--auto` 还是 `--once` 模式，都必须暂停并向用户确认**：

- 共识度 < 50%（双路分析严重分歧）
- 迭代超过最大轮数仍未达标
- 关键依赖缺失（无法继续执行的前置条件不满足）

触发熔断时，向用户展示：当前状态、分歧/问题摘要、建议的下一步选项。
<!-- ERROR_HANDLING_SECTION_END -->
```

**Step 5: Verify files exist**

Run: `ls -la protocols/`
Expected: 4 files (registry.conf, preamble.md, consensus.md, error-handling.md)

**Step 6: Commit**

```bash
git add protocols/
git commit -m "feat: add protocol source files and registry for sync-protocols"
```

---

### Task 2: Implement sync-protocols engine — registry parsing and CLI

**Files:**
- Create: `bin/sync-protocols`

**Step 1: Write the failing test — registry parsing**

Create `tests/test_sync_protocols.sh`. Use the same test harness pattern as `tests/test_sync_preamble.sh` (setup/teardown/assert helpers).

Test: Create a minimal `registry.conf` with 2 entries. Run `sync-protocols --check`. Verify it parses without error and reports section names.

```bash
echo "Test: registry parsing"
setup
  create_ref_skill_with_markers  # creates team-dev with PREAMBLE marker-based
  mkdir -p "$CTO_FLEET_DIR/protocols"
  # Write a minimal registry
  cat > "$CTO_FLEET_DIR/protocols/registry.conf" << 'EOF'
# comment line
PREAMBLE_SECTION | protocols/preamble.md | * | | after_frontmatter
EOF
  # Write a minimal preamble source
  cat > "$CTO_FLEET_DIR/protocols/preamble.md" << 'EOF'
<!-- PREAMBLE_SECTION_START -->
## Preamble (run first)
Test preamble content.
<!-- PREAMBLE_SECTION_END -->
EOF
  result="$("$SYNC_CMD" --verbose 2>&1 || true)"
  assert_contains "mentions PREAMBLE_SECTION" "PREAMBLE_SECTION" "$result"
  assert_exit_zero "parses registry and checks" "$SYNC_CMD"
teardown
```

**Step 2: Run test to verify it fails**

Run: `bash tests/test_sync_protocols.sh`
Expected: FAIL (sync-protocols doesn't exist yet)

**Step 3: Implement `bin/sync-protocols` — scaffold with registry parsing**

Create `bin/sync-protocols` with:
- Shebang, `set -euo pipefail`, trap for cleanup
- Argument parsing: `--fix`, `--dry-run`, `--verbose`, `--skills=`, `--sections=`, `--remove=`, `--migrate-preamble`, `--help`
- `CTO_FLEET_DIR` resolution (same as sync-preamble)
- `parse_registry()` function: reads `protocols/registry.conf`, skips comments and blank lines, splits on `|`, trims whitespace, stores into parallel arrays: `SECTION_NAMES[]`, `SOURCE_FILES[]`, `GATE_CONDITIONS[]`, `EXCLUDE_IFS[]`, `INSERTION_ANCHORS[]`
- `build_skill_list()` function: same logic as sync-preamble for `--skills` filter
- Main loop skeleton: iterate skills, iterate sections (reverse), print names

**Step 4: Run test to verify it passes**

Run: `bash tests/test_sync_protocols.sh`
Expected: PASS

**Step 5: Commit**

```bash
git add bin/sync-protocols tests/test_sync_protocols.sh
git commit -m "feat: sync-protocols scaffold with registry parsing and CLI"
```

---

### Task 3: Implement sync-protocols engine — extract and compare

**Files:**
- Modify: `bin/sync-protocols`
- Modify: `tests/test_sync_protocols.sh`

**Step 1: Write the failing test — check detects matching section**

```bash
echo "Test: check detects matching section"
setup
  # Create skill with correct PREAMBLE_SECTION markers and matching content
  create_skill_with_preamble_markers "team-test-ok"
  setup_registry_and_sources
  assert_exit_zero "check passes when section matches" "$SYNC_CMD"
teardown
```

**Step 2: Write the failing test — check detects outdated section**

```bash
echo "Test: check detects outdated section"
setup
  # Create skill with PREAMBLE_SECTION markers but wrong content between them
  create_skill_with_wrong_preamble_markers "team-test-wrong"
  setup_registry_and_sources
  result="$("$SYNC_CMD" 2>&1 || true)"
  assert_contains "reports OUTDATED" "OUTDATED" "$result"
  assert_exit_nonzero "check fails on outdated" "$SYNC_CMD"
teardown
```

**Step 3: Write the failing test — check detects missing section**

```bash
echo "Test: check detects missing section"
setup
  # Create skill with no markers at all
  create_skill_no_markers "team-test-missing"
  setup_registry_and_sources
  result="$("$SYNC_CMD" 2>&1 || true)"
  assert_contains "reports MISSING" "MISSING" "$result"
  assert_exit_nonzero "check fails on missing" "$SYNC_CMD"
teardown
```

**Step 4: Run tests to verify they fail**

Run: `bash tests/test_sync_protocols.sh`
Expected: 3 new tests FAIL

**Step 5: Implement extract and compare logic**

Add to `bin/sync-protocols`:

- `extract_canonical(source_file, section_name)` function: reads source file, extracts content between `<!-- {SECTION_NAME}_START -->` and `<!-- {SECTION_NAME}_END -->` (inclusive of markers). Store in variable.
- `extract_existing(skill_file, section_name)` function: same extraction from a SKILL.md. Returns content + start_line + end_line. Returns empty if markers not found.
- `compare_section(skill_file, section_name, canonical)` function: extracts existing, compares with canonical. Returns "OK", "OUTDATED", or "MISSING".
- Update main loop to call compare for each section and report status.

**Step 6: Run tests to verify they pass**

Run: `bash tests/test_sync_protocols.sh`
Expected: All PASS

**Step 7: Commit**

```bash
git add bin/sync-protocols tests/test_sync_protocols.sh
git commit -m "feat: sync-protocols extract and compare logic"
```

---

### Task 4: Implement sync-protocols engine — fix (splice) logic

**Files:**
- Modify: `bin/sync-protocols`
- Modify: `tests/test_sync_protocols.sh`

**Step 1: Write the failing test — fix updates outdated section**

```bash
echo "Test: fix updates outdated section"
setup
  create_skill_with_wrong_preamble_markers "team-fix-outdated"
  setup_registry_and_sources
  "$SYNC_CMD" --fix >/dev/null 2>&1 || true
  fixed="$(cat "$CTO_FLEET_DIR/team-fix-outdated/SKILL.md")"
  assert_contains "canonical content present" "Test preamble content" "$fixed"
  # Verify old content is gone
  TOTAL=$((TOTAL + 1))
  if echo "$fixed" | grep -q "wrong content"; then
    FAIL=$((FAIL + 1)); echo "  FAIL: old content still present"
  else
    PASS=$((PASS + 1)); echo "  PASS: old content removed"
  fi
  # Verify check now passes
  assert_exit_zero "check passes after fix" "$SYNC_CMD"
teardown
```

**Step 2: Write the failing test — fix inserts missing section**

Test for each insertion anchor type:

```bash
echo "Test: fix inserts missing section at after_frontmatter"
setup
  create_skill_no_markers "team-fix-missing"
  setup_registry_and_sources  # registry has after_frontmatter anchor
  "$SYNC_CMD" --fix >/dev/null 2>&1 || true
  fixed="$(cat "$CTO_FLEET_DIR/team-fix-missing/SKILL.md")"
  assert_contains "section inserted" "PREAMBLE_SECTION_START" "$fixed"
  # Verify it's after frontmatter (line 3 = second ---, markers should be after)
  assert_contains "original content preserved" "Actual skill body" "$fixed"
  assert_exit_zero "check passes after fix" "$SYNC_CMD"
teardown

echo "Test: fix inserts at after:KEYWORD anchor"
# Similar test with a HANDOFF_SECTION using after:TeamCreate anchor
# Skill must contain TeamCreate keyword

echo "Test: fix inserts at end_of_file anchor"
# Similar test with CONSENSUS_SECTION using end_of_file anchor
```

**Step 3: Write the failing test — dry-run does not modify**

```bash
echo "Test: dry-run does not modify files"
setup
  create_skill_with_wrong_preamble_markers "team-dryrun"
  setup_registry_and_sources
  original="$(cat "$CTO_FLEET_DIR/team-dryrun/SKILL.md")"
  "$SYNC_CMD" --dry-run >/dev/null 2>&1 || true
  after="$(cat "$CTO_FLEET_DIR/team-dryrun/SKILL.md")"
  assert_eq "file unchanged after dry-run" "$original" "$after"
teardown
```

**Step 4: Run tests to verify they fail**

Run: `bash tests/test_sync_protocols.sh`
Expected: New tests FAIL

**Step 5: Implement fix logic**

Add to `bin/sync-protocols`:

- `fix_outdated(skill_file, section_name, canonical, start_line, end_line)`: head/tail splice — `head -n $((start_line - 1))` + canonical + `tail -n +$((end_line + 1))`. Atomic write via `.tmp` + `mv`.
- `fix_missing(skill_file, section_name, canonical, insertion_anchor)`: find anchor line number based on anchor type:
  - `after_frontmatter`: find the 2nd `---` line
  - `after:KEYWORD`: find first line containing KEYWORD
  - `end_of_file`: use `wc -l`
  Then `head -n $anchor_line` + blank + canonical + blank + `tail -n +$((anchor_line + 1))`. Atomic write.
- **Reverse-order processing**: In the main loop, process sections array from last to first index for each file. This ensures bottom-of-file splices happen before top-of-file ones, preserving line numbers.

**Step 6: Run tests to verify they pass**

Run: `bash tests/test_sync_protocols.sh`
Expected: All PASS

**Step 7: Commit**

```bash
git add bin/sync-protocols tests/test_sync_protocols.sh
git commit -m "feat: sync-protocols fix logic with splice and anchor insertion"
```

---

### Task 5: Implement sync-protocols engine — gate, exclude, sections filter, remove

**Files:**
- Modify: `bin/sync-protocols`
- Modify: `tests/test_sync_protocols.sh`

**Step 1: Write the failing test — gate condition filters skills**

```bash
echo "Test: gate condition skips non-matching skills"
setup
  # Create skill WITHOUT TeamCreate
  create_skill_no_teamcreate "team-no-tc"
  # Registry has HANDOFF_SECTION with gate=TeamCreate
  setup_registry_with_handoff
  # HANDOFF should be skipped for this skill
  result="$("$SYNC_CMD" --verbose 2>&1 || true)"
  assert_contains "skipped" "skipped" "$result"
teardown
```

**Step 2: Write the failing test — exclude condition**

```bash
echo "Test: exclude_if skips skills with keyword"
setup
  # Create skill WITH TeamCreate AND with 共识发现数 (domain-specific consensus)
  create_skill_with_domain_consensus "team-security-like"
  # Registry: CONSENSUS_SECTION exclude_if=共识发现数
  setup_registry_with_consensus
  result="$("$SYNC_CMD" --verbose 2>&1 || true)"
  assert_contains "excluded" "excluded" "$result"
  # CONSENSUS_SECTION should NOT be injected
  TOTAL=$((TOTAL + 1))
  if grep -q "CONSENSUS_SECTION_START" "$CTO_FLEET_DIR/team-security-like/SKILL.md"; then
    FAIL=$((FAIL + 1)); echo "  FAIL: consensus injected despite exclude"
  else
    PASS=$((PASS + 1)); echo "  PASS: consensus correctly excluded"
  fi
teardown
```

**Step 3: Write the failing test — --sections filter**

```bash
echo "Test: --sections limits processing"
setup
  create_skill_no_markers "team-filter"
  setup_registry_full  # 4 protocols
  "$SYNC_CMD" --fix --sections=PREAMBLE_SECTION >/dev/null 2>&1 || true
  fixed="$(cat "$CTO_FLEET_DIR/team-filter/SKILL.md")"
  # PREAMBLE injected
  assert_contains "preamble injected" "PREAMBLE_SECTION_START" "$fixed"
  # Others NOT injected
  TOTAL=$((TOTAL + 1))
  if grep -q "CONSENSUS_SECTION_START" "$CTO_FLEET_DIR/team-filter/SKILL.md"; then
    FAIL=$((FAIL + 1)); echo "  FAIL: consensus injected despite sections filter"
  else
    PASS=$((PASS + 1)); echo "  PASS: consensus not injected (filtered out)"
  fi
teardown
```

**Step 4: Write the failing test — --remove**

```bash
echo "Test: --remove strips section from all skills"
setup
  create_skill_with_consensus_markers "team-remove-test"
  setup_registry_with_consensus
  "$SYNC_CMD" --remove=CONSENSUS_SECTION >/dev/null 2>&1 || true
  after="$(cat "$CTO_FLEET_DIR/team-remove-test/SKILL.md")"
  TOTAL=$((TOTAL + 1))
  if grep -q "CONSENSUS_SECTION_START" <<< "$after"; then
    FAIL=$((FAIL + 1)); echo "  FAIL: section still present after remove"
  else
    PASS=$((PASS + 1)); echo "  PASS: section removed"
  fi
  assert_contains "original content preserved" "Actual skill body" "$after"
teardown
```

**Step 5: Run tests to verify they fail**

Run: `bash tests/test_sync_protocols.sh`
Expected: 4 new tests FAIL

**Step 6: Implement gate, exclude, sections filter, remove**

Add to `bin/sync-protocols`:

- `gate_check(skill_file, condition)`: if `*`, return 0. Otherwise `grep -q "$condition" "$skill_file"`.
- `exclude_check(skill_file, exclude_if)`: if empty, return 1 (don't exclude). Otherwise `grep -q "$exclude_if" "$skill_file"`.
- `--sections` filter: parse comma-separated list, skip sections not in the list during main loop.
- `--remove` mode: for each skill, if markers found, splice them out (head before START + tail after END). Skip the normal check/fix logic.

**Step 7: Run tests to verify they pass**

Run: `bash tests/test_sync_protocols.sh`
Expected: All PASS

**Step 8: Commit**

```bash
git add bin/sync-protocols tests/test_sync_protocols.sh
git commit -m "feat: sync-protocols gate, exclude, sections filter, and remove"
```

---

### Task 6: Implement sync-protocols — multi-section reverse-order processing

**Files:**
- Modify: `bin/sync-protocols`
- Modify: `tests/test_sync_protocols.sh`

**Step 1: Write the failing test — multiple sections in one file**

```bash
echo "Test: multi-section fix processes correctly (reverse order)"
setup
  # Create a skill with TeamCreate, missing both CONSENSUS and ERROR_HANDLING
  # but having correct PREAMBLE and HANDOFF
  create_skill_with_preamble_and_handoff_markers "team-multi"
  setup_registry_full  # all 4 protocols
  "$SYNC_CMD" --fix >/dev/null 2>&1 || true
  fixed="$(cat "$CTO_FLEET_DIR/team-multi/SKILL.md")"
  # All 4 sections should be present
  assert_contains "preamble present" "PREAMBLE_SECTION_START" "$fixed"
  assert_contains "handoff present" "HANDOFF_SECTION_START" "$fixed"
  assert_contains "consensus present" "CONSENSUS_SECTION_START" "$fixed"
  assert_contains "error handling present" "ERROR_HANDLING_SECTION_START" "$fixed"
  # Verify ordering: PREAMBLE before HANDOFF before CONSENSUS/ERROR_HANDLING
  preamble_line=$(grep -n "PREAMBLE_SECTION_START" "$CTO_FLEET_DIR/team-multi/SKILL.md" | head -1 | cut -d: -f1)
  handoff_line=$(grep -n "HANDOFF_SECTION_START" "$CTO_FLEET_DIR/team-multi/SKILL.md" | head -1 | cut -d: -f1)
  consensus_line=$(grep -n "CONSENSUS_SECTION_START" "$CTO_FLEET_DIR/team-multi/SKILL.md" | head -1 | cut -d: -f1)
  TOTAL=$((TOTAL + 1))
  if [ "$preamble_line" -lt "$handoff_line" ] && [ "$handoff_line" -lt "$consensus_line" ]; then
    PASS=$((PASS + 1)); echo "  PASS: sections in correct order"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: sections out of order (P:$preamble_line H:$handoff_line C:$consensus_line)"
  fi
  # After fix, check should pass
  assert_exit_zero "check passes after multi-section fix" "$SYNC_CMD"
teardown
```

**Step 2: Run test to verify it fails**

Run: `bash tests/test_sync_protocols.sh`
Expected: FAIL

**Step 3: Verify reverse-order logic is correct**

The main loop should already process sections in reverse order (from Task 4). This test validates the end-to-end behavior with multiple sections needing insertion in the same file. If the test passes with existing code, great. If not, debug the line-number interaction between insertions.

The key issue: when inserting CONSENSUS at end_of_file first (reverse order), then inserting ERROR_HANDLING also at end_of_file, the second insertion's "end_of_file" anchor must be recalculated after the first insertion. **Solution**: re-read the file after each splice within the same skill (or track line offset). The simpler approach: after each splice, the file is rewritten atomically, so subsequent operations on the same file read the updated version naturally (since we use `cat "$skill_file"` each time, not a cached copy).

**Step 4: Run test to verify it passes**

Run: `bash tests/test_sync_protocols.sh`
Expected: All PASS

**Step 5: Commit**

```bash
git add bin/sync-protocols tests/test_sync_protocols.sh
git commit -m "feat: validate multi-section reverse-order processing"
```

---

### Task 7: Implement --migrate-preamble and backward compatibility

**Files:**
- Modify: `bin/sync-protocols`
- Modify: `tests/test_sync_protocols.sh`

**Step 1: Write the failing test — migrate-preamble converts legacy markers**

```bash
echo "Test: --migrate-preamble converts heading+--- to HTML markers"
setup
  # Create skill with legacy preamble format (heading + --- separator)
  create_skill_legacy_preamble "team-legacy"
  setup_registry_and_sources
  "$SYNC_CMD" --migrate-preamble >/dev/null 2>&1 || true
  migrated="$(cat "$CTO_FLEET_DIR/team-legacy/SKILL.md")"
  assert_contains "START marker added" "PREAMBLE_SECTION_START" "$migrated"
  assert_contains "END marker added" "PREAMBLE_SECTION_END" "$migrated"
  assert_contains "preamble content preserved" "cto-fleet-update-check" "$migrated"
  # The old --- separator between preamble and body should be replaced by END marker
  # After migration, check should pass
  assert_exit_zero "check passes after migration" "$SYNC_CMD"
teardown
```

**Step 2: Write the failing test — legacy preamble detection in check mode**

During Phase 1 (before migration), `--check` should still work with legacy markers. Test that a skill with the old heading+`---` format and correct content reports OK.

```bash
echo "Test: check mode handles legacy preamble format"
setup
  create_skill_legacy_preamble "team-legacy-check"
  setup_registry_and_sources
  # In check mode (no --migrate-preamble), legacy format should be detected
  # and compared against canonical content
  result="$("$SYNC_CMD" --verbose 2>&1 || true)"
  assert_contains "legacy format detected" "legacy" "$result"
teardown
```

**Step 3: Run tests to verify they fail**

Run: `bash tests/test_sync_protocols.sh`
Expected: FAIL

**Step 4: Implement --migrate-preamble**

Add to `bin/sync-protocols`:

- `--migrate-preamble` mode: for each SKILL.md:
  1. Find `## Preamble (run first)` line → `start_line`
  2. Find next `---` line after it → `end_line`
  3. Extract content between (exclusive of `---`)
  4. Replace region with: `<!-- PREAMBLE_SECTION_START -->` + content + `<!-- PREAMBLE_SECTION_END -->`
  5. Atomic write

- Legacy detection in check mode: if markers not found but `## Preamble (run first)` heading exists, extract using legacy method, compare content, report as "OK (legacy)" or "OUTDATED (legacy)". Print a note suggesting `--migrate-preamble`.

**Step 5: Run tests to verify they pass**

Run: `bash tests/test_sync_protocols.sh`
Expected: All PASS

**Step 6: Commit**

```bash
git add bin/sync-protocols tests/test_sync_protocols.sh
git commit -m "feat: sync-protocols --migrate-preamble and legacy compat"
```

---

### Task 8: Symlink and edge case tests

**Files:**
- Modify: `bin/sync-preamble` (replace with symlink)
- Modify: `tests/test_sync_protocols.sh`

**Step 1: Write the failing test — edge cases**

```bash
echo "Test: unpaired markers → error"
setup
  # Create skill with START but no END marker
  create_skill_unpaired_markers "team-unpaired"
  setup_registry_and_sources
  result="$("$SYNC_CMD" 2>&1 || true)"
  assert_contains "error reported" "error" "$result"
teardown

echo "Test: empty registry → no sections processed"
setup
  create_skill_with_preamble_markers "team-empty-reg"
  mkdir -p "$CTO_FLEET_DIR/protocols"
  echo "# empty" > "$CTO_FLEET_DIR/protocols/registry.conf"
  result="$("$SYNC_CMD" --verbose 2>&1 || true)"
  assert_exit_zero "empty registry is not an error" "$SYNC_CMD"
teardown

echo "Test: missing source file → error for that section"
setup
  create_skill_no_markers "team-missing-src"
  mkdir -p "$CTO_FLEET_DIR/protocols"
  cat > "$CTO_FLEET_DIR/protocols/registry.conf" << 'EOF'
PREAMBLE_SECTION | protocols/nonexistent.md | * | | after_frontmatter
EOF
  result="$("$SYNC_CMD" 2>&1 || true)"
  assert_contains "source not found" "not found" "$result"
teardown
```

**Step 2: Run tests to verify they fail**

Run: `bash tests/test_sync_protocols.sh`
Expected: FAIL

**Step 3: Implement edge case handling**

Add to `bin/sync-protocols`:
- Unpaired marker detection: if START found but no END (or vice versa), print error, increment error counter, skip that section for that file.
- Empty registry: 0 sections parsed → loop body never executes → exit 0.
- Missing source file: check `[ -f "$source" ]` when loading canonical content. Print error, skip section entirely.

**Step 4: Create symlink**

```bash
cd bin/
rm sync-preamble
ln -s sync-protocols sync-preamble
```

**Step 5: Write backward compat test**

```bash
echo "Test: sync-preamble symlink works"
setup
  create_skill_with_preamble_markers "team-compat"
  setup_registry_and_sources
  # Use the old command name
  OLD_CMD="$CTO_FLEET_DIR/bin/sync-preamble"
  assert_exit_zero "sync-preamble symlink works" "$OLD_CMD"
teardown
```

**Step 6: Run all tests**

Run: `bash tests/test_sync_protocols.sh`
Expected: All PASS

Also run the old test suite to verify backward compat:
Run: `bash tests/test_sync_preamble.sh`
Expected: All PASS (the old tests should work via symlink, but may need minor adjustment since the output format might change — if so, update them)

**Step 7: Commit**

```bash
git add bin/sync-protocols bin/sync-preamble tests/test_sync_protocols.sh
git commit -m "feat: sync-protocols edge cases, symlink, backward compat"
```

---

### Task 9: Verify Phase 1 against real SKILL.md files

**Files:**
- No changes (verification only)

**Step 1: Run check against all real skills with legacy preamble support**

Run: `bin/sync-protocols --check --verbose`

Expected: All PREAMBLE sections report "OK (legacy)". All HANDOFF sections report "OK". CONSENSUS and ERROR_HANDLING sections report "MISSING" for skills that need them (this is expected — they'll be injected in Phase 3).

**Step 2: Verify no false positives on gate/exclude**

Run: `bin/sync-protocols --check --verbose --sections=CONSENSUS_SECTION`

Expected: Skills with `共识发现数` (team-security, team-compliance, team-accessibility, team-i18n, team-arch, team-cost, team-design-review, team-governance, team-observability, team-postmortem, team-release, team-research, team-vendor) should show "excluded". Others with TeamCreate should show "MISSING" or "OK".

**Step 3: Document results**

If any unexpected results, investigate and fix before proceeding.

---

## Phase 2: Preamble Marker Migration

### Task 10: Migrate all SKILL.md preambles to HTML markers

**Files:**
- Modify: all 45 `*/SKILL.md` files (content-preserving marker change)

**Step 1: Run migration**

Run: `bin/sync-protocols --migrate-preamble --dry-run`
Expected: Shows which files would be changed and how many.

**Step 2: Execute migration**

Run: `bin/sync-protocols --migrate-preamble`
Expected: All SKILL.md files updated. Output shows count of migrated files.

**Step 3: Verify**

Run: `bin/sync-protocols --check --verbose`
Expected: All PREAMBLE sections now report "OK" (not "OK (legacy)"). All HANDOFF sections still "OK".

**Step 4: Spot-check 3 files**

Read `team-dev/SKILL.md`, `team-review/SKILL.md`, `team-security/SKILL.md` and verify:
- `<!-- PREAMBLE_SECTION_START -->` present after frontmatter
- `<!-- PREAMBLE_SECTION_END -->` present before the rest of skill content
- No leftover `---` separator between preamble and body that was the old boundary
- Preamble content unchanged

**Step 5: Run existing tests**

Run: `bash tests/test_sync_preamble.sh && bash tests/test_sync_protocols.sh`
Expected: All PASS

**Step 6: Commit**

```bash
git add -A
git commit -m "feat: migrate all SKILL.md preambles to HTML comment markers"
```

---

## Phase 3: New Protocol Injection + Cleanup

### Task 11: Inject CONSENSUS_SECTION and ERROR_HANDLING_SECTION

**Files:**
- Modify: ~35 `team-*/SKILL.md` files (those matching gate conditions)

**Step 1: Dry-run injection**

Run: `bin/sync-protocols --dry-run --fix --sections=CONSENSUS_SECTION,ERROR_HANDLING_SECTION`
Expected: Shows which skills would get each section. Verify:
- CONSENSUS excluded from: team-accessibility, team-arch, team-compliance, team-cost, team-design-review, team-governance, team-i18n, team-observability, team-postmortem, team-release, team-research, team-security, team-vendor (13 skills with `共识发现数`)
- ERROR_HANDLING excluded from: none (all TeamCreate skills get it)
- Non-TeamCreate skills (team router) skipped for both

**Step 2: Execute injection**

Run: `bin/sync-protocols --fix --sections=CONSENSUS_SECTION,ERROR_HANDLING_SECTION`
Expected: Sections injected at end_of_file for matching skills.

**Step 3: Verify**

Run: `bin/sync-protocols --check --verbose`
Expected: All OK across all 4 protocols.

**Step 4: Spot-check**

Read `team-deps/SKILL.md` (should have generic consensus at end), `team-security/SKILL.md` (should NOT have generic consensus, has domain-specific), `team-dev/SKILL.md` (should have both consensus and error-handling at end).

**Step 5: Commit**

```bash
git add team-*/SKILL.md
git commit -m "feat: inject consensus and error-handling protocol sections"
```

---

### Task 12: Clean up duplicate content

**Files:**
- Modify: `team-arch/SKILL.md`, `team-cost/SKILL.md`, `team-postmortem/SKILL.md`, `team-release/SKILL.md` (duplicate consensus blocks)
- Modify: `team-dev/SKILL.md`, `team-review/SKILL.md`, `team-security/SKILL.md` (orphaned handoff sections)

**Step 1: Remove duplicate generic consensus blocks**

For each of team-arch, team-cost, team-postmortem, team-release:
- These have `共识发现数` (domain-specific) AND the just-injected `<!-- CONSENSUS_SECTION_START -->` generic block
- Wait — per the exclude_if logic, these should NOT have gotten the generic block injected. Let me verify:
  - team-arch: has `共识发现数` → excluded from CONSENSUS injection. But it also has the OLD inline generic block (`发现一致性（相同问题/结论）`). That old inline block needs manual removal.
  - Same for team-cost, team-postmortem, team-release.

So the cleanup is: remove the OLD inline (non-marker) generic consensus block from these 4 skills. Search for the text `发现一致性（相同问题/结论）` that is NOT inside `<!-- CONSENSUS_SECTION -->` markers, and remove the surrounding `### 共识度计算` section.

For each file, identify the line range of the old inline block (from `### 共识度计算` to the line before the next `##` heading or end-of-section), and remove it.

**Step 2: Remove orphaned manual handoff sections**

For team-dev, team-review, team-security:
- After `<!-- HANDOFF_SECTION_END -->` there is a second `## 文件交接规范` heading with ~20 lines of old manual content.
- Find the line range: from the `## 文件交接规范` heading that appears AFTER `HANDOFF_SECTION_END` to the next `##` heading (or next section).
- Remove those lines.

**Step 3: Verify**

Run: `bin/sync-protocols --check --verbose`
Expected: All OK.

Grep to verify no duplicate content remains:
Run: `grep -l '发现一致性' team-arch/SKILL.md team-cost/SKILL.md team-postmortem/SKILL.md team-release/SKILL.md`
Expected: Only files where it's inside CONSENSUS markers (which for these 4 it shouldn't be, since they were excluded). Actually these 4 should have NO `发现一致性` at all after cleanup — they keep their domain-specific `共识发现数` formula only.

Run: `grep -c '## 文件交接规范' team-dev/SKILL.md team-review/SKILL.md team-security/SKILL.md`
Expected: 1 occurrence each (only the one inside HANDOFF_SECTION markers: `## 文件交接规范（File-Based Handoff）`).

**Step 4: Commit**

```bash
git add team-arch/SKILL.md team-cost/SKILL.md team-postmortem/SKILL.md team-release/SKILL.md \
        team-dev/SKILL.md team-review/SKILL.md team-security/SKILL.md
git commit -m "fix: remove duplicate consensus blocks and orphaned handoff sections"
```

---

### Task 13: Final verification and test suite

**Files:**
- Modify: `tests/test_sync_protocols.sh` (ensure comprehensive)

**Step 1: Run full check**

Run: `bin/sync-protocols --check --verbose 2>&1 | tail -20`
Expected: Summary shows all OK, 0 outdated, 0 missing, 0 errors.

**Step 2: Run all test suites**

Run: `bash tests/test_sync_protocols.sh && bash tests/test_sync_preamble.sh && bash tests/test_config.sh && bash tests/test_update_check.sh`
Expected: All PASS.

**Step 3: Verify idempotency**

Run: `bin/sync-protocols --fix && bin/sync-protocols --check`
Expected: No changes made (already in sync), check passes.

**Step 4: Test round-trip (modify protocol source → sync → verify)**

```bash
# Temporarily change consensus content
echo "<!-- CONSENSUS_SECTION_START -->" > /tmp/test-consensus.md
echo "Modified consensus." >> /tmp/test-consensus.md
echo "<!-- CONSENSUS_SECTION_END -->" >> /tmp/test-consensus.md
cp protocols/consensus.md protocols/consensus.md.bak
cp /tmp/test-consensus.md protocols/consensus.md
bin/sync-protocols --check 2>&1 | grep -c "OUTDATED"  # should show outdated count
cp protocols/consensus.md.bak protocols/consensus.md   # restore
```

**Step 5: Commit final test additions (if any)**

```bash
git add tests/
git commit -m "test: comprehensive sync-protocols test suite"
```

---

### Task 14: Update documentation

**Files:**
- Modify: `docs/SKILL-DEVELOPMENT-GUIDE.md` (add protocol sync instructions)
- Modify: `SKILL-TEMPLATE.md` (remove inline protocol text, add note about sync-protocols)

**Step 1: Update SKILL-DEVELOPMENT-GUIDE.md**

Add a section "Protocol Management" explaining:
- Protocol source files live in `protocols/` and `HANDOFF.md`
- `registry.conf` controls which protocols go where
- New skills get protocols auto-injected via `bin/sync-protocols --fix`
- Never manually edit content between `<!-- X_SECTION_START -->` and `<!-- X_SECTION_END -->` markers
- To modify a protocol, edit the source file then run `bin/sync-protocols --fix`

**Step 2: Update SKILL-TEMPLATE.md**

Remove any inline protocol boilerplate. Add a note:
```markdown
<!-- Protocol sections (handoff, consensus, error-handling) are auto-injected by bin/sync-protocols -->
<!-- Do not add them manually. Run: bin/sync-protocols --fix after creating this skill. -->
```

**Step 3: Commit**

```bash
git add docs/SKILL-DEVELOPMENT-GUIDE.md SKILL-TEMPLATE.md
git commit -m "docs: update skill development guide and template for sync-protocols"
```
