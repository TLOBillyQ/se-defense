# CONTEXT — se-defense

本仓库领域词汇表。只收录术语，不收录实现细节与决策（决策在 wayfinder 票与 ADR 里）。

## 本 effort

- **Base Defence** — 被移植的游戏：上游为 Spoke 仓库的 `Examples/05_BaseDefence`（Unity RTS-lite/塔防）。玩法：Core 播种电网，四种建筑（relay 扩展电网 / radar 标记敌人 / turret 攻击被标记敌人 / repair 维修）+ 矿点经济 + 递增波次敌人；采空全部资源获胜，Core 被毁失败。
- **spoke-lua** — Spoke 运行时的 Lua 5.4 移植（上游 `http://lzxsvn:3000/qinyuanj/spoke-lua`）。运行时内联到本仓库 `common/spoke/`（require 前缀 `common.spoke`，SE 工作区只认 client/common/data/server 四个根目录），其测试内联到 `tests/spoke/`（上游追踪见 `docs/spoke-upstream.md`），子模块已移除；上游的 `examples/base_defence/` 示例树已迁入本仓库 `server/game/`（require 前缀 `server.game`），上游随后删除了示例，业务代码从此在本仓库维护。
- **目的地（Destination）** — Base Defence 在蛋仔 SE 编辑器里完整可玩：SE 地图 `BaseDefence`，上帝视角，完整游戏流（Pregame→Playing→多波次→Victory/GameOver→Restart），原语级 3D 表现，GM 面板 + 真机集成测试验证。

## SE 编辑器（宿主）

- **SE 编辑器** — 蛋仔派对状态同步地图编辑器；`编辑`与`试玩`（playtest）两种模式；本仓库以 `editor-cli.exe`（`$CLI`）驱动。
- **工作区（workspace）** — `$CLI code init` 为某张地图生成/绑定的本地 Lua 工程（`eggy.json` 含 projectID）；`code push/pull` 的双端之一，本地磁盘上的真源。
- **Unit / Asset / Resource** — 宿主基础概念：Resource=素材（图片/网格/动画）；Unit=单个逻辑物件单元（如 `WorldUnit` 同时带物理与渲染）；Asset=若干 Unit 的集合（可 `LoadUnitAsset` 实例化）。
- **EUI** — 宿主界面节点树（`EUINodeBase` 系），带触摸开始/移动/结束/点击事件；本仓库用它承载 HUD 与棋盘输入捕获。
- **ugc 白模不吃颜色** — 官方白模族（`mesh/59268` / `59269` / `59273` / `59291`）对 `ModelColor1` 无反应（含设纯黑），`ModelColor2/3/4` 同样无效；`FileMesh` 的 `VertexColor` 无论挂 `WorldUnit`、挂 `RenderUnit` 还是独立创建都无效（独立创建的 `FileMesh` 干脆不渲染）。所有 `pcall` 都返回成功、不报错，**失败是静默的**。真机实测 2026-09-08（#42）。用白模的表现一律按单色设计；要按状态变色得换可染色资源。
- **白模 Size 是直径** — 官方资源表给出的 `Size` 是包围盒的**直径**，不是半长。`mesh/59269`（ugc_圆环）标 `(3,1,3)`，Raycast 实测 Scale=1 时外缘直径就是 3.0（外缘半径 1.5）。按字面读成半径会得到 2 倍误差。
- **realm** — SE 状态同步双端：`server/` 与 `client/` 各有 `main.lua` 入口（自动执行）。生命周期锚点：服务端 `Players.PlayerAdded`、客户端 `game.Loaded`。SE 文档定位：server=权威状态、client=本地表现；EUI 归 client 端；服务端创建的 Unit 复制到客户端。

## 移植机制

- **宿主适配层（host adapter）** — 本仓库 `server/adapter/` 的代码：在真 SE API 之上实现 `server/game/` 业务模块依赖的四个宿主域——`host.eui` / `host.entity` / `host.input` / `host.reset_scene`。
- **入口期装配件（entry-time adapter piece）** — 也住在 `server/adapter/` 但**不是**宿主域、没有任何业务模块依赖的适配层代码：`scene.lua`（静态场景装饰，纯视觉，由 `server/main.lua` 在加载时调一次，不进 `entity.by_id`、不参与 `host:reset_scene()`）、`build_panel.lua`（放置面板）、`convert.lua`（0..1 浮点 RGB → SE 0..255 Color 的换算 + 坐标/颜色归一化拷贝，entity 与 scene 共用）。它们需要的业务事实（如棋盘半径）由组合根 `server/main.lua` 注入——适配层（L4）不得反向依赖业务（L3）。_避免_：把 `server/adapter/` 里的东西一律当成宿主域接口。
- **宿主接缝（host seam）** — 业务模块只依赖 `server.adapter.{host,eui,input}` 三个接口；无头测试用 `tools/headless/se_stub.lua` 提供 SE 全局，适配层原样运行，没有 mock 替换。（历史：迁入前业务住在上游，靠 mock 同路径替换接入，已废除。）
- **部署树** — 推送进编辑器前的文件树：仓库根的 `common/spoke/`（spoke 运行时）+ `server/`（业务 `game/` + 适配层 `adapter/` + 服务端入口）+ `client/`（客户端入口 + 渲染器）。仓库根直接对齐 SE 工作区根，没有 `src/` 中间层；部署采用白名单 `client/ common/ server/`（官方强制的工作区根目录，本项目跟随），仓库根其余内容（`docs/`、`tools/`、`data/` 等）不部署，`data/` 为编辑器导出物只回同步；require 名以仓库根为根（如 `server.game.core`），经 byte 镜像进入工作区同名根目录。
- **部署接缝（deploy seam）** — 部署的目的地是否住在 Windows 侧。`wslpath -w` 给出盘符路径（`C:\…`）才算跨接缝：只有这一侧值得起 `cmd.exe` 走 robocopy 增量镜像，也只有这一侧能做 `editor-cli` 收尾（WSL 侧二进制解析不了 `eggy.json` 里的 `C:\` 地图目录）。目的地在 Linux 侧时（`\\wsl…` 或不在 WSL，如验收用的临时工作区）一律本地 `cp`：那种情况下 robocopy 要 Windows 反过来走 9P 回读 Linux 侧，凭空造出一次本来不存在的跨系统往返。判定在 `tools/deploy_plan.crosses_seam`，与宿主接缝无关。_避免_：把 robocopy 当作「总是更快的镜像方式」。
- **保留服务名（reserved service name）** — SE 内置服务占用的一组名字（已知 `world`）。任何 Lua 文件的**文件名**（不含扩展名）撞上它，编辑器同步时会被静默跳过、不进地图包：`code diff` 里永远显示 `only-local`，`code push` 也补不回来，只在编辑器日志出一条"与SE内置服务名冲突，已跳过同步，不会生效"。目录层级不构成隔离，`server/game/world.lua` 照样中招（故改名 `world_data.lua`；`coroutine.lua` → `spoke_coroutine.lua` 为预防性同类改名）。_避免_：把 `only-local` 一律当作"push 一下就好"。
- **spoke 原语约束（spoke-first）** — 长期架构约束：`server/` 的业务逻辑（`server/game/`，以及日后的 `server/present/` 等业务目录）必须建立在 `common/spoke` 的响应式原语之上构建——`spoke.reactive`（State / Memo / Effect / Trigger / Reaction / Phase）与 `spoke.runtime`（Epoch / Dock / SpokeTree）——不允许改写成不依赖 spoke 的普通 Lua 实现，也不允许在仓库内另造一套平行的响应式内核。业务目录下只有纯函数/纯数据的辅助模块（自身不 require 模块，或只 require `server.` 前缀模块）可以不引用 `common.spoke`，且必须在 `features/engineering/spoke-primitives.feature` 的豁免清单里点名。任何分支迁移或重写（如 `greenfield/rewrite` 那种去 spoke 的 `src/`）都不得绕过此约束；该 feature 随 `run_acceptance.sh` 自动执行。_避免_：把 spoke 称作"可替换的依赖"。
- **GameTick** — 游戏固定步长节拍。SE 真机由服务端 `RunService.Heartbeat`（30fps 逻辑帧）驱动固定步长；`EVENT.REPEAT_TIMEOUT` 是旧宿主 ECA 周期事件、SE 文档中不存在（调研修正，见 `research/realm-model` 分支）。
- **RemoteEvent** — SE 中 server→client 的唯一文档化消息通道（`FireClient`/`FireAllClients` → `OnClientEvent`）；仿真快照驱动客户端 EUI 的载体。送达/有序无文档承诺。
- **快照（snapshot）** — 服务端经 RemoteEvent 发给客户端的 UI 状态表：节点路径 → `{text, visible, color, fill}`。协议为混合制：平时节点级增量（带单调 `seq`），握手（`client_ready`）与序号缺口（`resync`）时全量重同步。`line` 形状**不进快照**（见形状路由），`ring` 进快照（只带圆心与半径）。
- **形状路由（shape routing）** — 服务端 `host.eui` 适配器内部的分流：`text/fill/color/visible/shape` 进快照跨网络，`ring` 的几何由客户端按 `client/ring_geometry` 换算生成；`set_line` 形状仍在服务端就地渲为 EffectUnit，随 Unit 复制可见，不跨网络。原为 ring/line 都就地渲染的「双路由」，#42 把 ring 改回快照（ADR 0003 → ADR 0006）。
- **recipe 表** — 客户端渲染器的静态注册表：快照节点 path 前缀模式 → 真节点配方（EUI 类型、布局、样式、世界锚定方式）。快照只携状态，表现知识全在 recipe 表。一个例外：带 `shape` 的节点按状态而非 path 分派（覆盖圈的 path 千变万化，见 ADR 0006）。
- **哑镜像（dumb mirror）** — 客户端 v1 形态：零 spoke 树，订阅快照并差分应用到真 EUI/SceneGui 节点（`client/eui_render.lua`）。
- **探针（probe）** — 文档查不到、需真机实测确认的事实项；三份调研分支各附探针清单（`research/realm-model`、`research/input-camera`、`research/visual-primitives`）。
- **上帝视角（god-view）** — 交互范式：固定俯视棋盘，玩家点击/触摸棋盘放置与选择；输入经 EUI 捕获层 + `CameraService` 屏幕坐标→射线与**棋盘平面（board plane）**求交。

## 玩法（Base Defence 规则层）

规则真源为上游 Unity 源码；数值进 feature 的例子表，不进本词汇表。

- **对局阶段（game mode）** — Pregame / Playing / Victory / GameOver 四态。只有 Playing 时模拟推进；其余阶段波次、采集、敌人全部冻结。_避免_：状态、模式（单独出现时）。
- **开始对局** — 玩家主动把 Pregame 切到 Playing 的动作；进入 Playing 时资金重置为起始资金。
- **重开** — 从 Victory/GameOver 回到 Pregame 并重建全图。
- **资金（money）** — 玩家唯一货币；只由采集增加，只由放置扣减。无退款、无击杀收入。_避免_：金钱、钱。
- **矿点（resource site）** — 场景预置、玩家不可建造的资源来源；有剩余量，采空后离场。矿点没有血量，不受炸弹伤害。_避免_：资源、资源点。
- **采集（harvest）** — 矿点每隔固定时间把 1 单位剩余量兑成 $1。前提：矿点自身接入电网，且当前不在进攻期。
- **停采（harvest pause）** — 进攻期内全图采集暂停。
- **电网（power grid）** — 以 Core 为根的树：每个节点只有一个供电者，链路必须能上溯到 Core 才算通电。
- **供电圈（provide range）** — Core/Relay 向外供电的圆；其他建筑与矿点供电圈为零，只收不转。
- **收电圈（receive range）** — 节点接收供电的判定圆；收电圈与某个通电供电圈相交即可接入。
- **通电（powered）** — 节点存在一条经若干 Relay 到 Core 的链。未通电的建筑不做任何事，但仍有血量、仍会被炸。
- **断电传播** — 供电者失电或离场时，其下游整条分支随之失电。
- **供电者抢占** — 已接入的节点只在更近的供电者出现、且不会成环时才换供电者。
- **足迹圆（footprint）** — 建筑或矿点占地的圆；用于放置重叠判定与炸弹命中判定。
- **合法落点** — 足迹圆不与任何已有足迹圆重叠，且落点位于某个通电供电圈内。
- **放置（place）** — 在合法落点建造建筑并扣其价格。资金不足的建筑不可选。无选中、无拆除。
- **Core / Relay / Radar / Turret / Repair** — 五种建筑，保留英文名。Core 是唯一根供电者且不可建造。
- **揭示（tracked）** — 敌人处于任一通电 Radar 的探测圈内的状态。Turret 只对已揭示的敌人开火。_避免_：标记、锁定。
- **探测圈 / 射程圈 / 维修圈** — Radar / Turret / Repair 各自的功能圆。
- **维修** — Repair 在维修圈内一次只修一个目标：血量比例最低且未满的建筑，不含自己。
- **敌人（enemy）** — 三个层级的飞行单位，只有血量与体积不同。无死亡奖励。
- **航线（heading）** — 敌人出生时随机指向基地中心区域的方向；目标选择按"偏离航线距离 + 0.5 × 直线距离"取最小建筑。
- **炸弹（bomb）** — 敌人在目标位置投下的范围伤害：引信后对半径内所有建筑造成伤害。
- **波次（wave）** — 编号从 1 起的一轮进攻；预算 = 2 + (N−1)，每个敌人层级有固定成本，预算耗尽停止生成。
- **平静期（lull）** — 两波之间的倒计时；倒计时结束前公布来袭方向。
- **进攻期（assault）** — 从本波开始生成到本波敌人全部死亡；下一波只在本波全灭后才开始计时。
- **来袭方向** — 东/南/西/北四边之一，敌人从该边界外生成。
- **解锁波次** — 2 型敌人第 4 波起可出现，3 型第 8 波起。
- **胜利** — 全部矿点采空并离场。**失败** — Core 离场。两者只在 Playing 中判定。
