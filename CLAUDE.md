# CLAUDE.md

## 语言

使用中文思考和回复。

## Agent skills

### Issue tracker

Issues 在 Gitea（`lzxsvn:3000/qinyuanj/se-defense`），用 `tea` CLI + Gitea API 操作。见 `docs/agents/issue-tracker.md`。

### Triage labels

使用五个默认分诊标签。见 `docs/agents/triage-labels.md`。

### Domain docs

单上下文布局：根 `CONTEXT.md` + `docs/adr/`。见 `docs/agents/domain.md`。

### GDD

Base Defence 绿地重写的规则真源在 `docs/gdd/`（索引 `docs/gdd/README.md`）。写 gameplay/presentation feature 前先读对应系统文档。
