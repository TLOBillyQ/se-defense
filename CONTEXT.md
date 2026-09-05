# CONTEXT — se-defense

本仓库领域词汇表。只收录术语，不收录实现细节与决策（决策在 wayfinder 票与 ADR 里）。

## 本 effort

- **Base Defence** — 被移植的游戏：上游为 Spoke 仓库的 `Examples/05_BaseDefence`（Unity RTS-lite/塔防）。玩法：Core 播种电网，四种建筑（relay 扩展电网 / radar 标记敌人 / turret 攻击被标记敌人 / repair 维修）+ 矿点经济 + 递增波次敌人；采空全部资源获胜，Core 被毁失败。
- **spoke-lua** — Spoke 运行时的 Lua 5.4 移植（上游 `http://lzxsvn:3000/qinyuanj/spoke-lua`）。运行时与其测试已内联到本仓库 `vendor/spoke/` 与 `vendor/tests/`（require 前缀 `vendor.spoke`），子模块已移除；上游的 `examples/base_defence/` 示例树已迁入本仓库 `src/server/game/`（require 前缀 `server.game`），上游随后删除了示例，业务代码从此在本仓库维护。
- **目的地（Destination）** — Base Defence 在蛋仔 SE 编辑器里完整可玩：SE 地图 `BaseDefence`，上帝视角，完整游戏流（Pregame→Playing→多波次→Victory/GameOver→Restart），原语级 3D 表现，GM 面板 + 真机集成测试验证。

## SE 编辑器（宿主）

- **SE 编辑器** — 蛋仔派对状态同步地图编辑器；`编辑`与`试玩`（playtest）两种模式；本仓库以 `editor-cli.exe`（`$CLI`）驱动。
- **工作区（workspace）** — `$CLI code init` 为某张地图生成/绑定的本地 Lua 工程（`eggy.json` 含 projectID）；`code push/pull` 的双端之一，本地磁盘上的真源。
- **Unit / Asset / Resource** — 宿主基础概念：Resource=素材（图片/网格/动画）；Unit=单个逻辑物件单元（如 `WorldUnit` 同时带物理与渲染）；Asset=若干 Unit 的集合（可 `LoadUnitAsset` 实例化）。
- **EUI** — 宿主界面节点树（`EUINodeBase` 系），带触摸开始/移动/结束/点击事件；本仓库用它承载 HUD 与棋盘输入捕获。
- **realm** — SE 状态同步双端：`server/` 与 `client/` 各有 `main.lua` 入口（自动执行）。生命周期锚点：服务端 `Players.PlayerAdded`、客户端 `game.Loaded`。SE 文档定位：server=权威状态、client=本地表现；EUI 归 client 端；服务端创建的 Unit 复制到客户端。

## 移植机制

- **宿主适配层（host adapter）** — 本仓库 `src/server/adapter/` 的代码：在真 SE API 之上实现 `src/server/game/` 业务模块依赖的四个宿主域——`host.eui` / `host.entity` / `host.input` / `host.reset_scene`。
- **宿主接缝（host seam）** — 业务模块只依赖 `server.adapter.{host_base,host,eui,input}` 四个接口；无头测试用 `tools/headless/se_stub.lua` 提供 SE 全局，适配层原样运行，没有 mock 替换。（历史：迁入前业务住在上游，靠 mock 同路径替换接入，已废除。）
- **部署树** — 推送进编辑器前的文件树：`vendor/spoke/`（spoke 运行时）+ `src/server/`（业务 `game/` + 适配层 `adapter/` + 服务端入口）+ `src/client/`（客户端入口 + 渲染器）；`src/` 一级目录即 SE 工作区根，require 名以 `src/` 为根（如 `server.game.core`），经 byte 镜像进入工作区同名根目录。
- **GameTick** — 游戏固定步长节拍。SE 真机由服务端 `RunService.Heartbeat`（30fps 逻辑帧）驱动固定步长；`EVENT.REPEAT_TIMEOUT` 是旧宿主 ECA 周期事件、SE 文档中不存在（调研修正，见 `research/realm-model` 分支）。
- **RemoteEvent** — SE 中 server→client 的唯一文档化消息通道（`FireClient`/`FireAllClients` → `OnClientEvent`）；仿真快照驱动客户端 EUI 的载体。送达/有序无文档承诺。
- **快照（snapshot）** — 服务端经 RemoteEvent 发给客户端的 UI 状态表：节点路径 → `{text, visible, color, fill}`。协议为混合制：平时节点级增量（带单调 `seq`），握手（`client_ready`）与序号缺口（`resync`）时全量重同步。ring/line 形状**不进快照**（见双路由）。
- **双路由（dual routing）** — 服务端 `host.eui` 适配器内部的分流：`text/fill/color/visible` 进快照跨网络；`set_ring`/`set_line` 形状在服务端就地渲为 EffectUnit，随 Unit 复制可见，不跨网络。
- **recipe 表** — 客户端渲染器的静态注册表：快照节点 path 前缀模式 → 真节点配方（EUI 类型、布局、样式、世界锚定方式）。快照只携状态，表现知识全在 recipe 表。
- **哑镜像（dumb mirror）** — 客户端 v1 形态：零 spoke 树，订阅快照并差分应用到真 EUI/SceneGui 节点（`src/client/eui_render.lua`）。
- **探针（probe）** — 文档查不到、需真机实测确认的事实项；三份调研分支各附探针清单（`research/realm-model`、`research/input-camera`、`research/visual-primitives`）。
- **上帝视角（god-view）** — 交互范式：固定俯视棋盘，玩家点击/触摸棋盘放置与选择；输入经 EUI 捕获层 + `CameraService` 屏幕坐标→射线与**棋盘平面（board plane）**求交。
