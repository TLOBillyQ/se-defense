# ADR 0005：依赖门禁是被查询的，不是被复述的

状态：已采纳

## 背景

`docs/gdd/README.md` 的系统依赖图在源码层由 `features/engineering/dependencies.feature` 固定，其中场景 3「架构门禁禁止模块 A 依赖模块 B」断言的是一条**不存在**的边：日后有人写出这条 require，`tools/arch check` 必须失败。

这类断言有个天然的陷阱。判定「门禁会不会拒绝这条边」需要门禁的规则引擎——禁止依赖规则的模式匹配 + 分层上行判定。这套引擎属于 arch_view（`internal/analyzer.lua` 的 `_build_check`），是另一个仓库的决策。最直接的实现是在本仓照抄一份，但那份副本没有任何东西盯着：这些边在真实源码树上不存在，真门禁永远不会去判它们，所以副本和上游一旦分叉，feature 照样全绿，而 CI 里真正跑的 `tools/arch check` 已经换了语义。断言看着很强，实际固定的是本仓自己的复制品。

## 决策

本仓不复述门禁规则，只查询门禁。

`tools/acceptance/arch_probe.lua` 在 `./tmp` 下临时生成一棵只含待判那条边的两模块树，用仓库真实的 `arch_view.config.json` 跑 `arch_view.analyze`，把 arch_view 给出的裁决作为答案，跑完即删。一次探针约 10ms。

由此分出三个各司其职的模块：

- `repo_checks.lua`——对 Lua 源码文本的纯谓词（spoke 原语约束、源码树布局）。
- `arch_checks.lua`——对 arch_view 模型与配置的纯谓词（边是否存在、组件层级、未豁免环数）。
- `arch_probe.lua`——唯一会问「门禁会拒绝吗」的地方，且它是去问，不是自己算。

场景 3 的步骤因此是三重断言：两端都是真实存在的模块、真实树上没有这条边、真门禁拒绝这条边。第一条不是冗余——跨层的拒绝由**组件**层级决定，同组件里换个模块名结论不变，所以拼错的模块名本来能蒙混过关（由 Gherkin 变异测试实证发现）。

## 后果

- arch_view 改变分层语义时，本仓的 feature 会跟着改变行为，不会出现「feature 绿、门禁红」的分叉。
- 代价是场景 3 每个例子多一次 ~10ms 的进程内扫描，以及对 `./tmp` 的写权限依赖。整份 dependencies.feature 40 例仍在 1 秒级。
- 分层门禁语义的性质测试（曾经的 `tests/property/arch_layering_property.lua`）随复制品一并删除：它测的是本仓对上游规则的抄写，属于 arch_view 自己的测试范围。门禁语义现由 `tests/acceptance_arch_probe_test.lua` 对**真门禁**验证。
- 这套做法只适用于「问一个假设边的裁决」。已存在的边由 `tools/arch check` 直接判定，不走探针。
