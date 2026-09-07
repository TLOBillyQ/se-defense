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

## 工具链

入口 `lua5.4 tools/cli.lua <子命令>`（仓库根执行，`--help` 看封闭命令集）：

- `deploy` — 仓库根 `client/ common/ server/`（白名单，即官方强制的工作区根，本项目跟随，无 `src/` 中间层）byte 镜像进 SE 工作区（Windows 侧，WSL 经 /mnt/c）；仓库根其余内容不部署；工作区根杂物（`tools/deploy_plan.lua` 的 `JUNK`）随部署清除，`.vscode/` 与 `log.txt` 保留；`--clean` 只清不装。
- `sync` — 反方向：把工作区的 `eggy.json` / `EggyAPI.lua` / `data/`（整目录镜像）回同步到仓库根（CRLF→LF）。

工作区默认路径在 `tools/eggy_workspace.lua`，环境变量 `EGGY_WORKSPACE` 可覆盖。
