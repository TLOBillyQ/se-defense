# 固化spoke原语约束

把「业务代码必须建立在 common/spoke 原语之上」固化为长期约束，防止后续迁移或重写把 spoke 架构换掉。

要做的事：
1. CONTEXT.md 明确写入：server/ 业务逻辑（server/game、server/present 等）必须使用 common/spoke 的响应式原语（spoke.reactive / State / Memo / Effect / Epoch / Phase / Dock 等）构建，不允许改成无 spoke 的普通 Lua 实现。
2. 在 features/engineering/ 新增一个 feature（或扩展 source-layout.feature），断言 server/game 下的业务模块 require common.spoke，且仓库中存在对 spoke 原语的实际调用；不用 spoke 的实现视为不合规。
3. 让该 feature 接入 run_acceptance.sh，能自动跑。

背景：greenfield/rewrite 分支的 src/ 完全不用 spoke，任务「迁移rewrite分支的feature」只迁 feature 不迁实现，本卡用来堵住架构被替换的口子。
