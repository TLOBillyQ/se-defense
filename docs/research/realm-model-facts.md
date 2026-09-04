# SE 状态同步 Realm 模型事实清单 —— Base Defence 单人仿真归属

> Wayfinder 票：[调研：SE 状态同步 realm 模型与单人仿真归属](http://lzxsvn:3000/qinyuanj/se-defense/issues/2)
> 调研日期：2026-09-04。一手来源 = `$CLI docs search`（game-api / manual docset）+ 官方技能文件（只读）。
> 标注约定：**【文档事实】** = 一手文档/官方技能明文；**【demo 证据】** = 官方双端示例的用法；**【待探针】** = 一手来源查不到定量描述，需真机确认。

## 结论先行（四个问题的答案）

1. **仿真放 server realm。** SE（世界版/状态同步）文档明文规定：`server/` = 权威状态（计分、倒计时、结算、存储、命中判定），`client/` = 本地表现（UI 显示、输入响应、相机、音效）。**没有任何一手文档允许「单人玩法可客户端仿真」**；官方全部双端 demo（含单人向的引导小游戏、钓鱼）都把玩法循环放服务端。客户端仿真工程上可跑（client 侧 Heartbeat / CreateUnit / EUI 都可用），但属未文档化的非标准路径（见选项 B）。
2. **`GAME_INIT` / `LEVEL_BEGIN` 不存在于 SE 状态同步 API** —— 这两个名字来自 monopoly 的 FS 模式宿主（`monopoly/EggyAPI.lua` 的 `LuaAPI.global_register_trigger_event` 事件表），不能带进 SE。SE 两端的真实生命周期锚点：`server/main.lua` 顶层自动执行（server 端）+ `Players.PlayerAdded`；`client/main.lua` 顶层自动执行（client 端）+ `game.Loaded`（**local 触发、client 端**的初始加载完成事件）。SE 无「关卡开始」这类全局生命周期事件，回合/关卡状态由业务自建并经 RemoteEvent 广播。
3. **server→client 驱动 EUI 的唯一文档化通道是 `RemoteEvent`**：`RemoteEvent.New(name)` 双端同名；服务端 `:FireClient(player, args)` / `:FireAllClients(args)` → 客户端 `OnClientEvent:Connect(function(payload) end)`。形态：**每次仅一个可选 `args: Any`**（多字段封装成 table）；单向异步；**不可直接传 `CFrame`**（拆 Vector3/Quaternion）。可靠性边界：**文档未承诺送达/有序/频率上限【待探针】**；文档明文的工程约束是「客户端先监听后请求 + ready 握手 + 重连重发快照」防竞态，以及服务端必须把入参当不可信输入校验。
4. **Unit 同步边界：服务端创建 → 同步到客户端；客户端创建 → 仅本端可见。** 服务端 `World:CreateUnit` 的 WorldUnit 会复制到客户端场景树（Tool/外观/装配体多处文档化），但**每 tick `Position` 写入的复制节奏、延迟与带宽无定量文档【待探针】**；官方 demo 的做法是「空间存在靠复制，逻辑状态（HP/分数/阶段）靠 RemoteEvent 快照」。EUI（`PlayerGui`/`ScreenGui`/`EuiManager`）**归 client 端创建与操作**（ScreenGui 明文 `realm: client`；公开契约**没有服务端代理节点**），**server 不能直接操作玩家 EUI**，只能发 RemoteEvent 让客户端自己改。

---

## 事实清单

### A. 双端职责与生命周期（问题 a）

- **F1【文档事实】** SE 状态同步地图 = 编辑器【世界模式】→【空白地图（世界版）】模板；必须用世界版而非原点版模板，SE Lua 开发才适用。
  来源：manual docset《第 0 章：从可视化编辑器到状态同步 Lua 开发》「如何创建状态同步地图」。
- **F2【文档事实】** 职责分工表（官方教程的工程规定）：`server/` = 维护权威玩法状态、校验客户端意图、结算与存储（「会影响分数、奖励、胜负或所有玩家的结果，优先放服务端」）；`client/` = 读取本地输入、更新 HUD、相机、音效等本地表现（「只影响当前玩家看到或操作到的内容」）；`common/` = 双端共享常量/纯逻辑，不放权威可变状态。
  来源：manual《第 0 章》「先记住四个职责位置」；《第 3 章：统一世界、双端模型与逻辑帧》「统一世界」节：「服务端（server）：权威状态。计分、倒计时、结算、存储、命中判定。客户端（client）：本地表现。UI 显示、输入响应、相机、音效。」
- **F3【文档事实】** 权威必须在服务端的理由：「如果你把分数放在客户端，玩家可以修改本地数据来作弊。所以权威状态必须在服务端。」——该论述没有给单人玩法开口子；**不存在「单人可客户端仿真」的文档许可**（反证检索：`单人玩法 客户端权威 本地模拟` 无命中）。
  来源：manual《第 3 章》「统一世界」节。
- **F4【文档事实】** 入口与生命周期：`client/main.lua` 与 `server/main.lua` 各自在对应端**自动执行**；`main.lua` 只做 require 模块 + 调用 `Init()/Start()`。目录依赖方向：`client/` 不能引用 `server/`，反之亦然；`data/`、`common/` 双端可 require。
  来源：manual《第 1 章：脚本工程、目录结构与运行入口》「main.lua 应该做什么」「目录职责」；技能文件 `/mnt/c/Users/Lzx_8/.eggitor/codex/se/rules/eggy-se.mdc`「工作区主要目录结构」。
- **F5【文档事实】** **SE 没有 `GAME_INIT`/`LEVEL_BEGIN` 事件。** game-api 检索这两个名字只命中无关条目；`Game` 服务唯一文档化事件是 `Loaded()`（触发：`local`，「客户端初始单位与属性加载完成时触发」，示例全部 `@runtime client`）。`Players.PlayerAdded` 是 global 触发（服务端用于初始化玩家）。
  来源：game-api docset `Game.html`、`Players.mdx`（`$CLI docs search "GAME_INIT"/"LEVEL_BEGIN"`）。
- **F6【文档事实】** `GAME_INIT`/`LEVEL_BEGIN`/`REPEAT_TIMEOUT` 的真实出处 = FS 模式宿主事件表：`LuaAPI.global_register_trigger_event({EVENT.GAME_INIT,}, ...)`、`EVENT.LEVEL_BEGIN`（回调带 `level_key`）。monopoly 在用（`src/app/ui_bootstrap.lua:162`）。se-defense `CONTEXT.md` 里「GameTick 由 EVENT.REPEAT_TIMEOUT 驱动」一句引用的就是这套 FS 事件——**在 SE 状态同步地图里不存在，移植时 GameTick 驱动必须换 SE 的等价物（F7）**。
  来源：`/home/qinyuanj/dev/gitea/monopoly/EggyAPI.lua` L8746-8759；`/home/qinyuanj/dev/gitea/monopoly/src/app/ui_bootstrap.lua:162`；se-defense `CONTEXT.md`「GameTick」词条。
- **F7【文档事实】** SE 的逻辑帧：约 30fps，时序 `PreSimulation → 物理模拟 → PostSimulation → Heartbeat → FrameUpdate → PostFrameUpdate`；`RunService.Heartbeat` **客户端与服务端均可监听**（用户验证确认），服务端可用于驱动每帧逻辑（`deltaTime` 秒）；事件在订阅端本地触发，跨端不自动同步。帧间隔有波动，不得把一帧硬编码成固定秒数。
  来源：manual《第 2 章》（「逻辑帧 30fps」）、《第 3 章》「逻辑帧时序」；game-api `RunService.html`「注意事项」。
- **F8【确认事实】** monopoly **不是** SE 世界版工作区：仓库根只有单个 `main.lua`（无 `server/`+`client/` 双端结构），顶层文档无状态同步表述。**不得作为本票 realm 模型依据。**
  来源：`/home/qinyuanj/dev/gitea/monopoly/` 目录结构、`CONTEXT.md`（本地核查）。

### B. server→client 消息 API（问题 b）

- **F9【文档事实】** `RemoteEvent` 是双端通信的文档化通道，注入全局域。真实可用方法仅 5 个：`New(name)` / `FireServer(args?)` / `FireClient(player, args?)` / `FireAllClients(args?)` / `OnServerEvent`、`OnClientEvent`。**每次只发一个可选 `args: Any`**，多字段封装 table；服务端 `OnServerEvent` 回调第一参是框架注入的 `player`（客户端发送时不带）。
  来源：技能文件 `/mnt/c/Users/Lzx_8/.eggitor/codex/se/skills/eggy-se-lua-coding/references/features/eggy-se-lua-coding-server-client-msg/SKILL.md`；game-api `RemoteEvent.html` / `RemoteEvent.mdx`。
- **F10【文档事实】** 序列化边界：**当前版本不支持直接传 `CFrame`**，须拆 `Vector3` position + `Quaternion/Vector3` rotation 或转 table；「单元对象无法序列化跨网络」（只能传 UnitId）。服务端必须把 `OnServerEvent` 的 args 当不可信输入：校验类型/白名单/范围/频率后才可改权威状态。
  来源：game-api `RemoteEvent.mdx`「注意事项」；`20260820版本更新日志`（WeldConstraint 条目）。
- **F11【文档事实】** 可靠性边界：**文档未承诺送达、有序、频率上限**。文档给的补偿模式是应用层协议：客户端「先监听、再握手（client_ready）、后同步」；服务端保存权威回合并向已就绪客户端发**状态快照**（至少含阶段+结束时间）；新加入/重连再次请求最新快照。
  来源：manual《第 3 章》「客户端如何显示服务端倒计时」、《第 8 章：客户端与服务端通信》；可靠性本身【待探针】。
- **F12【demo 证据】** 官方双端 demo 的三类驱动形态：① 引导小游戏（单人向）：`gameStartRE:FireClient(player, {started, endTime})` + `updatePointRE` 推分数；② 战斗：`CombatInfo:SyncData()` 每 0.1s 只在 `NeedSync` 时 `FireClient` 可序列化快照（`ToClientData` 明确剥离方法/连接/Unit）；③ 钓鱼/1v1：`OpenScreenRE:FireClient(player, {screenName, passBy})` 让客户端开指定界面。**共性：逻辑状态走 RemoteEvent 快照，不依赖属性复制。**
  来源：技能文件 `references/demos/guide-minigame-demo.md`、`combat-demo.md`、`fishing-demo.md`、`1v1-arena-demo.md`（同目录）。
- **F13【文档事实】** `RemoteFunction` 仅在 `TagService.mdx` 注意事项中被顺带提及为「公开通信接口」，game-api 检索无独立页面与签名——**不要依赖**；RPC 一律用 RemoteEvent 请求/响应双事件对。
  来源：`$CLI docs search "RemoteFunction InvokeServer"`（无命中）；manual `TagService.mdx`。

### C. Unit 自动同步边界（问题 c）

- **F14【文档事实】** 服务端→客户端的复制是宿主机制（多处明文）：
  - `ReplicatedStorage`：「服务端与客户端共享的复制容器，其子单位会自动同步到客户端，但不会创建物理刚体或渲染模型」（反推：World 场景树的复制是带物理+渲染的正常通道）；
  - `Tool`：「服务端先…`World:CreateUnit("Tool", config)` 创建并持有工具实例。客户端…应从 World 查找**宿主已创建的** Tool，不要重新创建」——客户端在自己的 World 树里能找到服务端创建的单位；
  - `CustomAppearanceService:CreateCustomAppearance`：「⚙ **服务端创建会同步到所有客户端，客户端创建仅本端可见**」；
  - `PhysicsService`：碰撞组注册「属于服务端权威配置；客户端只读取已同步的碰撞关系」；
  - `20260820版本更新日志`（WeldConstraint）：「单元对象无法序列化跨网络，客户端仍通过 `ConnectUnitIdDict`/`RootUnitId` 同步接收」。
  来源：game-api docset `ReplicatedStorage.mdx`、`Tool.mdx`、`CustomAppearanceService.html`、`PhysicsService.mdx`、版本更新日志。
- **F15【demo 证据】** 服务端写 `Position`/`CFrame`、客户端直接可见：引导小游戏的碰撞得分循环里，方块随机变位（`cube.Position = ...`）、球体复位（`ball.CFrame = startCFrame`）全部发生在 `server/main.lua`，客户端代码只做 UI，没有任何镜像逻辑——玩家看到方块移动靠的就是复制。战斗 demo 服务端 `PivotTo` 摆战机模型同理。
  来源：技能文件 `references/demos/guide-minigame-demo.md`（server/main.lua 段）、`combat-demo.md`（FlyBaseUtil）。
- **F16【文档事实】** 客户端本地创建的可见性：仅本端。明文两处：`CustomAppearanceService`（见 F14）；`EffectService` 本地特效「在客户端本地播放一个特效，**仅对当前玩家可见**」。
  来源：game-api `EffectService.mdx`、`CustomAppearanceService.html`。
- **F17【文档事实】** 客户端写属性不产生权威：「当前公开契约没有承诺『客户端写入后如何跨端同步』。计分、归属、胜负等权威数据仍应由 server 维护」。
  来源：manual《第 5 章：Unit 与场景树》「自定义属性」节。
- **F18【待探针】** 服务端 `World:CreateUnit("WorldUnit")` 的**复制节奏**（是否每逻辑帧同步 `Position` 写入、创建/`Destroy()` 到达客户端的延迟、高频写位置的带宽上限）——一手文档只确认「会同步」，无定量描述。直接影响「每 tick 挪棋子/敌人」走复制还是走快照。
- **F19【demo 证据】** 销毁同样由服务端驱动且客户端无需配合：各 demo 的 `effectUnit:Destroy()`、`model:Destroy()` 均在创建端执行，无跨端清理消息。来源：`combat-demo.md`、`guide-minigame-demo.md`。

### D. EUI 归属（问题 d）

- **F20【文档事实】** EUI 入口只存在于客户端：`Players.LocalPlayer.PlayerGui`（`PlayerGui` 文档定位 =「当前玩家的**客户端** UI 入口」，提供 `EuiManager` 与 `ScreenGui`）；`ScreenGui` 明文「**仅客户端可用**（realm: client）」。`EuiManager` 获取链：`localPlayer.PlayerGui.EuiManager:GetRootNode()`。`Players.LocalPlayer` 是客户端属性。
  来源：game-api `PlayerGui.html`、`Players.html`；技能文件 `.../eggy-se-lua-coding-eui/references/api/api-services-managers.md`；manual《第 9 章：UI / EUI 与 CoreGui》（全部示例 `运行端：client`）。
- **F21【文档事实】** **公开契约没有服务端代理节点**：EUI 技能 API 文档明文「当前公开契约没有 `GetNodeByID` / `GetNodes` / **服务端代理节点** / `LoadCustomUIData`；不要调用」。普通 EUI 节点由 `game:GetService("World"):CreateUnit("EUIxxx", config)` 创建，挂到 `Parent = rootNode`（客户端）。
  来源：技能文件 `api-services-managers.md`；manual《第 9 章》。
- **F22【demo 证据】** 全部官方 demo 中服务端从不触碰 PlayerGui：服务端只 `FireClient`，客户端收事件后改自己的 EUI（`ScreenBattle`/`ScreenFishing`/HUD 等）；提示类走客户端 `screenGui:ShowTips(msg, duration)`（服务端要提示时经 `_G.Util:MsgNotice` → RemoteEvent → 客户端 ShowTips 的链路）。
  来源：技能文件 `demos/*`；`api-services-managers.md` ScreenGui 节。

---

## 可行的 realm 架构选项表（对「业务模块零改动」的破坏面）

前提：spoke-lua `examples/base_defence/` 业务模块经 **mock 替换**原样落地（`host.eui`/`host.entity`/`host.input`/`host.reset_scene` 四域由适配层实现，`require` 路径不变）。业务模块是纯 Lua、无宿主依赖——**它在哪个 realm 被 require，整个仿真就在哪个 realm**。

| 选项 | 仿真位置 | 机制 | 业务零改动破坏面 | 结论 |
|---|---|---|---|---|
| **A. server 仿真 + RemoteEvent 快照驱动 EUI（官方范式）** | `server/main.lua` | 服务端 Heartbeat（30fps 逻辑帧）内积累固定步长驱动 GameTick；`host.input`=RemoteEvent 意图入队；`host.eui`=`FireClient` 快照→客户端 EUI 渲染；`host.entity`=服务端 WorldUnit（靠复制呈现）或纯数据+快照 | **最小**：业务模块原样 require 于 `server/`；四域适配器全部是实现代码。代价：输入多一跳 RTT（单人自测无感）；`host.eui` 拆成「服务端出口 + 客户端渲染器」两半 | ✅ 与全部一手文档/官方 demo 一致；可平滑升级多人；**推荐** |
| **B. client 仿真（纯本地单人）** | `client/main.lua` | 客户端 Heartbeat 驱动 GameTick；entity/eui/input 全部本端，零网络 | 业务模块同样零改动（require 于 `client/`）；适配器最简单。**但**：① 违反文档权威模型（F2/F3），无任何文档背书；② 服务端权威服务（DataStore/成就/存档）要反向跨端；③ 未来上多人必须整体搬家；④ 编辑器摆放的场景对象仍是服务端复制来的，客户端本地单位混在其中需自行隔离 | ⚠️ 工程可行、非标准；仅当 A 的复制节奏探针失败且不打算多人时考虑 |
| **C. server 权威逻辑 + client 本地渲染实体（快照实体）** | `server/main.lua`（逻辑）+ `client/`（表现） | 服务端只算不发单位，棋盘/敌人/建筑全部由客户端按快照本地创建（客户端单位，仅本端可见——单人无碍）；不依赖 WorldUnit 复制节奏 | 业务模块零改动；**`host.entity` 双端拆两份**（服务端逻辑实体 + 客户端渲染实体），适配层复杂度最高；需自建 UnitId↔快照映射 | 备选：若 F18 探明复制节奏不满足每 tick 移动的表现要求，则从 A 退化到 C |

**对 GameTick 词条的修正建议**（供父票汇总）：CONTEXT.md「GameTick…真机由 `EVENT.REPEAT_TIMEOUT` 驱动」应改为「SE 由 `RunService.Heartbeat`（server realm，30fps 逻辑帧，F7）内做固定步长积累驱动」——`EVENT.REPEAT_TIMEOUT` 属 FS 模式宿主，SE 不存在（F6）。

## 需真机探针确认清单

1. **P1（对应 F18）**：服务端 `World:CreateUnit("WorldUnit")` 后每逻辑帧写 `Position`，客户端观察复制延迟/平滑度/丢帧；`Destroy()` 到达时延。
2. **P2（对应 F11）**：`RemoteEvent:FireClient` 高频（如每逻辑帧）发送的送达率、顺序与限流表现。
3. **P3**：单人试玩（1 人 Space）下 `Players.PlayerAdded` 与 `server/main.lua` 的执行先后、`game.Loaded` 时场景树是否已完整复制。
4. **P4**：客户端 `World:CreateUnit` 的本地单位是否真的对其他系统（射线/触发）不可见、是否与复制单位正常交互（选项 B/C 的前提）。

## 来源清单

| # | 来源 | 类型 |
|---|---|---|
| S1 | `$CLI docs search --docset manual`：《SE UGC Lua 作者文档》第 0/1/2/3/5/8/9/19 章（标题与片段经检索核验） | 官方手册 |
| S2 | `$CLI docs search --docset game-api`：`RemoteEvent.html/.mdx`、`RunService.html`、`Game.html`、`PlayerGui.html`、`Players.html`、`ReplicatedStorage.mdx`、`Tool.mdx`、`CustomAppearanceService.html`、`EffectService.mdx`、`PhysicsService.mdx`、`World.html/.mdx`、`EggyUnit.html`、`20260820版本更新日志`、`20260709版本更新日志`、`TimerService.html` | 官方 API 文档 |
| S3 | `/mnt/c/Users/Lzx_8/.eggitor/codex/se/rules/eggy-se.mdc` | 官方技能规则 |
| S4 | `/mnt/c/Users/Lzx_8/.eggitor/codex/se/skills/eggy-se-lua-coding/references/features/eggy-se-lua-coding-server-client-msg/SKILL.md` | 官方技能 |
| S5 | 同目录 `references/demos/`：`guide-minigame-demo.md`、`combat-demo.md`、`1v1-arena-demo.md`、`fishing-demo.md` | 官方双端示例 |
| S6 | `/mnt/c/Users/Lzx_8/.eggitor/codex/se/skills/eggy-se-lua-coding/references/features/eggy-se-lua-coding-eui/references/api/api-services-managers.md`、`.../eggy-se-lua-coding-unit/SKILL.md`、`references/create-unit-and-asset.md`、`references/lua-env.md` | 官方技能 |
| S7 | `/home/qinyuanj/dev/gitea/monopoly/EggyAPI.lua` L8700-8800、`monopoly/src/app/ui_bootstrap.lua` | FS 模式宿主（仅用于溯源 GAME_INIT/LEVEL_BEGIN） |
| S8 | `/home/qinyuanj/dev/gitea/se-defense/CONTEXT.md`、`/home/qinyuanj/dev/gitea/spoke-lua/CONTEXT.md` | 本仓库/依赖仓库上下文 |
