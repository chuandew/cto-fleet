---
name: team-{domain}
description: 启动一个{描述}团队（{角色列表}），通过{方法描述}，输出{产出描述}。使用方式：/team-{domain} [--auto (全自动，不询问)] [--once (仅确认一次后自动执行)] [--lang=zh|en] 任务描述
argument-hint: [--auto (全自动，不询问)] [--once (仅确认一次后自动执行)] [--lang=zh|en] 任务描述
---

## Preamble (run first)

```bash
_UPD=$(~/.claude/skills/cto-fleet/bin/cto-fleet-update-check 2>/dev/null || true)
[ -n "$_UPD" ] && echo "$_UPD" || true
```

If output shows `UPGRADE_AVAILABLE <old> <new>`: read `~/.claude/skills/cto-fleet/cto-fleet-upgrade/SKILL.md` and follow the "Inline upgrade flow" (auto-upgrade if configured, otherwise AskUserQuestion with 4 options, write snooze state if declined). If `JUST_UPGRADED <from> <to>`: tell user "Running cto-fleet v{to} (just updated!)" and continue.

---

**参数解析**：从 `$ARGUMENTS` 中检测以下标志：
- `--auto`：完全自主模式（不询问用户任何问题，全程自动决策）
- `--once`：单轮确认模式（将所有需要确认的问题合并为一轮提问，确认后全程自动执行）
- `--lang=zh|en`：输出语言（默认 `zh` 中文）

<!-- 添加领域参数（参考 docs/PARAMETER-SPEC.md 选择规范名称）-->
<!-- 例如：
- `--scope=module|package|system`：分析范围（默认 `module`）
- `--fix`：自动修复发现的问题
-->

| 模式 | 用户确认范围 | 条件节点处理 |
|------|-------------|-------------|
| **标准模式**（默认） | 每轮报告确认 + 修复方案确认 | 正常询问用户 |
| **单轮确认模式**（`--once`） | 仅首轮报告确认 | 自动决策 + 收尾汇总 |
| **完全自主模式**（`--auto`） | 不询问用户 | 全部自动决策，收尾汇总所有决策 |

单轮确认模式下自动决策规则：
- <!-- 列出 --once 模式下的自动决策规则 -->
- **迭代超 N 轮** → **不可跳过，必须暂停问用户**（熔断机制）

使用 TeamCreate 创建 team（名称格式 `team-{domain}-{YYYYMMDD-HHmmss}`），你作为 team lead 按以下流程协调。

## 流程概览

```
阶段零  {阶段名} → {关键步骤}
         ↓
阶段一  {阶段名} → {关键步骤}
         ↓
阶段二  {阶段名} → {关键步骤}
         ↓
阶段三  收尾 → 最终报告 + 清理
```

## 角色定义

| 角色 | 职责 |
|------|------|
| {role-1} | {职责描述}。**不编写或修改代码，只做分析。** |
| {role-2} | {职责描述}。**独立工作，不与 {role-1} 交流。** |
| {fixer} | {职责描述}。**只修复审查指出的问题，不做额外重构。** |

---

## 阶段零：{初始化阶段名}

### 步骤 1：{步骤名}

<!-- 详细描述步骤，包括：
  - 启动哪些角色
  - 各角色的具体任务
  - 输出格式要求
-->

---

## 阶段一：{核心分析/审查阶段名}

### 步骤 N：{独立分析}

<!-- 双分析师独立工作 -->

### 步骤 N+1：{合并 + 交叉校准}

<!-- team lead 合并报告，计算共识度 -->

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

---

## 阶段二：{修复/实施阶段名}

### 步骤 N：{修复/实施}

<!-- 修复逻辑 -->

### 步骤 N+1：{验证}

<!-- 验证修复效果 -->

---

## 阶段三：收尾

### 步骤 N：最终报告

Team lead 按 `--lang` 指定的语言向用户输出最终报告。

### 步骤 N+1：清理

关闭所有 teammate，用 TeamDelete 清理 team。

---

## 错误处理

| 异常情况 | 处理方式 |
|---------|---------|
| {异常1} | {处理方式} |
| {异常2} | {处理方式} |
| Teammate 无响应/崩溃 | Team lead 重新启动同名 teammate，从当前轮次恢复 |

---

## 核心原则

- **{原则1}**：{说明}
- **{原则2}**：{说明}
- **{原则3}**：{说明}

---

## 需求

$ARGUMENTS
