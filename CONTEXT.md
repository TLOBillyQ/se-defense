# CONTEXT — se-defense

本仓库领域词汇表。只收录术语，不收录实现细节与决策（决策在 wayfinder 票与 ADR 里）。

## 本 effort

- **Base Defence** — 被移植的游戏：上游为 Spoke 仓库的 `Examples/05_BaseDefence`（Unity RTS-lite/塔防）。玩法：Core 播种电网，四种建筑（relay 扩展电网 / radar 标记敌人 / turret 攻击被标记敌人 / repair 维修）+ 矿点经济 + 递增波次敌人；采空全部资源获胜，Core 被毁失败。
- **spoke-lua** — Spoke 运行时的 Lua 5.4 移植（`http://lzxsvn:3000/qinyuanj/spoke-lua`），本仓库以 git submodule 引入；其 `examples/base_defence/` 是 Base Defence 的无头忠实移植（业务模块），本仓库**不重写**它。
- **目的地（Destination）** — Base Defence 在蛋仔 SE 编辑器里完整可玩：SE 地图 `BaseDefence`，上帝视角，完整游戏流（Pregame→Playing→多波次→Victory/GameOver→Restart），原语级 3D 表现，GM 面板 + 真机集成测试验证。

## SE 编辑器（宿主）

- **SE 编辑器** — 蛋仔派对状态同步地图编辑器；`编辑`与`试玩`（playtest）两种模式；本仓库以 `editor-cli.exe`（`$CLI`）驱动。
- **工作区（workspace）** — `$CLI code init` 为某张地图生成/绑定的本地 Lua 工程（`eggy.json` 含 projectID）；`code push/pull` 的双端之一，本地磁盘上的真源。
- **Unit / Asset / Resource** — 宿主基础概念：Resource=素材（图片/网格/动画）；Unit=单个逻辑物件单元（如 `WorldUnit` 同时带物理与渲染）；Asset=若干 Unit 的集合（可 `LoadUnitAsset` 实例化）。
- **EUI** — 宿主界面节点树（`EUINodeBase` 系），带触摸开始/移动/结束/点击事件；本仓库用它承载 HUD 与棋盘输入捕获。
- **realm** — SE 状态同步双端：`server/` 与 `client/` 各有 `main.lua` 入口；仿真归属由 wayfinder 票决定。

## 移植机制

- **宿主适配层（host adapter）** — 本仓库 `src/` 的代码：在真 SE API 之上实现 spoke-lua 业务模块依赖的四个宿主域——`host.eui` / `host.entity` / `host.input` / `host.reset_scene`。
- **mock 替换（mock swap）** — 部署机制：把 `examples/base_defence/host_mock.lua`、`eui_mock.lua`、`input_mock.lua` 与 `examples/host_mock.lua` 在部署树里**同路径**替换为真适配实现；业务模块的 `require` 路径不变，这是业务零改动的机制。
- **部署树** — 推送进编辑器前的文件树：`src/spoke/`（spoke-lua 运行时）+ `examples/base_defence/`（业务，mock 已替换）+ 本仓库适配代码，经 byte 镜像进入工作区。
- **GameTick** — 游戏固定步长节拍；真机由 `EVENT.REPEAT_TIMEOUT`（`LuaAPI.global_register_trigger_event`）驱动。
- **上帝视角（god-view）** — 交互范式：固定俯视棋盘，玩家点击/触摸棋盘放置与选择；输入经 EUI 捕获层 + `CameraService` 屏幕坐标→射线与**棋盘平面（board plane）**求交。
