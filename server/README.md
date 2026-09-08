# server — Base Defence 业务与宿主适配层

Unity 原型：`Examples/05_BaseDefence`（`/Users/billyq/Dev/UnityProjects/Spoke`）。
目标不是像素级复刻，而是**忠实移植架构与游戏流，替换表现层**：
GameObject/prefab/粒子等表现层换成宿主 EUI 节点、实体状态与 `print` 消息。

历史：本目录原为 spoke 上游仓库的 `examples/base_defence/`（最后版本
`4bdcf06`，上游随后删除了示例树）。se-defense 是它的正式版，业务代码
从此在这里维护，不再跟随上游。

## 分层

server/ 按玩法系统分包，依赖只能从高层（小数字）流向低层（大数字）；**host = 面向宿主的层**：

| 包 | 层 | 职责 |
| --- | --- | --- |
| `match/` | 3 | 组合根与对局流程（GameRootFull / GameState / Session / Roster） |
| `ui/` | 4 | 表现层（Sidebar / Announcer / BoardDisplay / CoverageDisplay / LinkDisplay / RenderUtil / BuildPanel / OperationLog / StatusUI） |
| `board/` | 5 | 棋盘输入与建造规格 |
| systems（`power/` `economy/` `defense/` `waves/`） | 6 | 玩法系统，同层互相可依赖 |
| `units/` | 7 | 被系统操作的实体（Health / HealthBar / Building） |
| `kernel/` | 8 | 底座：机制与共享事实（GameTick / SpokeCoroutine / Collision / CollisionBody / Pool / WorldData） |
| `host/` | 9 | 面向宿主的层：host 表（eui / input / entity / reset_scene）+ scene / convert |

## 宿主接缝

业务模块只依赖 `require("server.host")` 一个接缝；host 表挂 `host.eui` / `host.input` / `host.entity` / `host.reset_scene`。`server/host/eui.lua`、`server/host/input.lua` 等是 host 层内部子模块，业务不直接 require。

`host.eui` 是服务端 UI 状态出口：text/fill/color/visible 与 ring 的圆心/半径进快照经 RemoteEvent 下发，ring 几何由客户端 `client/ring_geometry` 生成；只有 line 就地渲成 EffectUnit（形状路由，ADR 0006 取代 0003 中 ring 那半）。

无头测试不需要 mock：`tools/headless/se_stub.lua` 提供 SE 全局，host 层原样
运行。验收：`tools/acceptance/run_acceptance.sh`；冒烟：`lua5.4 tools/headless/run_server.lua`。

## 明确取舍

- `health_bar` 留在 `units/` 不进 `ui/`：building / enemy / resource 直接 attach 血条，翻方向要给 Building 加血条工厂注入接缝。
- `world_data` 进 `kernel/`：它是 GDD 00 共享事实而非机制，但零依赖、全员读；kernel 定义为「底座：机制与共享事实，不含系统规则」。
- `entity.unit_name` 是双端契约（`client/eui_render.lua` 复刻），评估是否进 `common/`，本单只记录。
- `game_root_full` 惰性 require Enemy 不再清 `package.loaded`；模块缓存复位归无头 harness（`tools/acceptance/headless.lua`），真机 SE 沙盒没有 package 库。
- `status_ui` 已被 SideBar 接替，删除候选，另议。

## 游戏流

`Pregame → Playing → Victory | GameOver`，胜负条件集中在
`game_state.lua`（对应上游 `GameState.Init`）：

- **Victory**：`Playing` 期间 `resources_remaining == 0`（所有矿点采空）。
- **GameOver**：`Playing` 期间 Core 死亡。
- 非 `Playing` 时模拟冻结：`Resource.can_harvest` 显式要求
  `game_state.mode == "Playing"`（上游等价物是 `Time.timeScale = 0`）。
- 波次清场只推进 `wave.number`，不再直接判胜。

`session.lua` 提供无场景重载的 **Restart**（组合根缺省 `GameRootFull`，`Session.spawn(config, mode, root_class)` 可换成无头测试用的组合根）：

```
旧树 tree:dispose()  →  host:reset_scene()  →  用同一 config 新建 GameRootFull + SpokeTree
```

真机部署时，宿主自己的“退出/重进玩法”流程就是场景重载；`session.lua` 只是
headless 验证与单局重开的薄壳。

## 架构对照表

| 上游 C# 文件 | Lua 模块 | 说明 |
| --- | --- | --- |
| `BaseDefence.unity` 场景接线 | `game_root_full.lua` | 唯一组合根：GameState、Core、矿点、WaveDirector、Pool、BuildingSpecs、InputSignals、BoardInteractions、UI 挂同一棵树；敌人常驻 Dock |
| `GameState.cs` | `game_state.lua` | Mode/Money/CollectRate/ResourcesRemaining、六碰撞区、胜负条件、Core（GameRootFull 中改由 `core.lua` 完整组件注入） |
| `GameState.Restart()`（场景重载） | `session.lua` | 拆树 → 清场景 → 重建树 |
| `SpokeExtensions.cs` | `spoke_coroutine.lua` | `s:coroutine(game_tick, body)`；`yield()` 等一 tick，`wait_seconds(n)` 定时 |
| `WaveDirector.cs` | `wave_director.lua` | lull 倒计时/揭示 → `wave_started` → 逐个 spawn → 全灭 `wave_defeated` → 下一波；tier/budget 简化为 `enemy_count`/`spawn_interval` |
| `Controls/InputSignals.cs` | `input_signals.lua` | 每 tick 轮询 host.input，发布 left/right click 与 `view.mouse_point` |
| `Controls/CameraControls.cs` | 裁掉 | 只保留 `View.MousePoint` 语义并并入 `input_signals.lua`；相机运动不是无头验证目标 |
| `Pool.cs` | `pool.lua` | 按 spec.key 分 idle 栈；实体复用 + epoch 重新挂载；despawn 自回收 |
| `Spatial/Circle.cs` + `Spatial/CollisionWorld.cs` | `collision.lua` | 2D 圆碰撞，空间哈希（格子分桶 + dirty 增量），对外契约与上游一致 |
| `Units/Health.cs` | `health.lua` | `Health.attach(s, {max_hp})`；hp memo、damaged trigger、detach 回满血 |
| `Units/Buildings/Building.cs` | `building.lua` | 组合式基类：Health、血条、footprint、受击变色、断电变暗、死亡回收 |
| `Units/Buildings/Core.cs` | `core.lua` | 电网根（真 PowerNode）+ Building 组合；GameRootFull 中 `game_state.core` 指向它 |
| `Units/Buildings/PowerNode.cs` | `power_node.lua` | 电网树：root/叶子、parent 窃取 + 防环、0.15s debounce、断电传播 |
| `Units/Buildings/Resource.cs` | `resource.lua` | 剩余资源/血条/悬浮提示；通电且非空袭时按 collect_time 产钱；采空消失 |
| `Units/Buildings/Relay.cs` | `relay.lua` | 纯电力中继（PowerNode provider） |
| `Units/Buildings/Radar.cs` | `radar.lua` | 雷达覆盖圈 + 天线旋转；Enemy 被覆盖时 `is_tracked` |
| `Units/Buildings/Turret.cs` | `turret.lua` | 索敌/限速转向/光束闪现后伤害；无单独 pivot，旋转在 entity 上 |
| `Units/Buildings/Repair.cs` | `repair.lua` | 选射程内 HP 占比最低友方建筑持续回血；EUI line 表达光束 |
| `Units/Enemies/Enemy.cs` | `enemy.lua` | 目标固定 Core（裁 heading-line 选楼/separation/bob）、移动/攻击、可选 radar track |
| `Units/Enemies/BombBlast.cs` | 裁掉 | 攻击直接扣 Core Health，不生成爆炸物 |
| `Units/MeshFX.cs` | 裁掉 | 命中闪烁 → 实体变色（`building.lua`）；碎裂 → 死亡直接消失 + `print` |
| `UI/SideBar.cs` | `sidebar.lua` | GameMode → 四面板 EUI 路由；金钱/波次/资源/消息反应式文本；BuildItem 按钮/hotkey 由 BoardInteractions 鼠标流取代 |
| `UI/Announcer.cs` | `announcer.lua` | 波次警告 + 屏幕消息（Dock 替换、定时消失、边缘闪烁） |
| `UI/HealthBar.cs` | `health_bar.lua` | fill/text/阈值颜色；死亡/满血隐藏，Resource 空值隐藏 |
| `UI/BoardInteractions.cs` | `board_interactions.lua` | 悬停/放置/校验；左键购买放置、右键取消；离开 Playing 清 placing |
| `UI/CoverageDisplay.cs` | `coverage_display.lua` | 覆盖圈 → EUI ring |
| `UI/LinkDisplay.cs` | `link_display.lua` | 电网树/链路 → EUI line |
| —（#20 最简 HUD） | `status_ui.lua` | `hud/*` 五节点文本，保留垂直切片 e2e 路径；SideBar 是其完整后继 |
| —（Unity `Time.deltaTime` / LateUpdate 驱动器） | `game_tick.lua` | 累计游戏时间 + 每 tick 监听器派发 dt；真机由服务端 `RunService.Heartbeat` 固定步长积累驱动（1/30，见 `server/main.lua`） |
| —（内部辅助） | `render_util.lua` | CoverageDisplay/LinkDisplay 共用：颜色归一化/信号读取、effect 卸载时销毁已建 EUI 节点 |

## 真机部署要点

1. 物理落位：`lua5.4 tools/cli.lua deploy`（`tools/deploy.lua`） 把仓库根白名单各端子树（`common/spoke/`、`server/host/`、
   `server/match/` 等业务包）镜像进宿主脚本根（宿主沙盒没有 `package.path`，
   require 只能按 script 目录解析）。
2. 宿主接缝见上节；业务模块只依赖 `require("server.host")`。
3. 游戏节拍：真机由服务端 `RunService.Heartbeat` 驱动，`server/main.lua` 按 1/30
   固定步长积累（每帧最多追赶 4 步，超出丢弃）调用 `tick:tick(STEP)`，整帧包在
   `SpokeRuntime.batch` 里合并成一次 flush。SE 文档里不存在 `EVENT.REPEAT_TIMEOUT`
   这类周期事件（见 CONTEXT.md「GameTick」）。
4. 重开：`session.lua` 的 dispose → 重建模式可直接搬；若宿主有真正的
   场景/玩法退出流程，则用该流程替代 `host:reset_scene()`。
5. 对象池与实体生命周期：建筑死亡走 `pool:despawn` 或 `entity:destroy`；
   `tree:dispose()` 负责逆序清理 epoch 子树，宿主侧不要重复销毁同一实体。
