# ADR 0006：覆盖圈走快照，几何在客户端生成

状态：已采纳（源自 Gitea 票 #42）。取代 ADR 0003 中关于 `ring` 的部分。

## 背景

ADR 0003 把 `set_ring` 和 `set_line` 都留在服务端就地渲染，理由是形状数量随建筑增长、进快照会让每帧增量膨胀。代价是形状无法 resync，且尺寸知识锁死在服务端适配层。

#42 暴露了这条路的真实成本。覆盖圈画出来的大小和逻辑范围完全对不上（放置预览圆大了 3 倍），而这个 bug 一路藏到真机才被发现：headless host-mock 记的是逻辑半径，看不见服务端那一步 `半径 → Scale` 的换算，链路上没有任何自动缝能盯住它。同时，服务端唯一可用的圆形特效（`effect/6044`）既没有 `Size` 也没有物理，无法标定原生半径——那条注释自承「探针待定」的常数根本没法定下来。

用有物理的白模 `mesh/59269` 代替特效就能标定（Raycast 实测 Scale=1 时外缘半径 1.5）。剩下的问题是：这个白模 WorldUnit 由谁创建。SE 是服务端权威、单位靠复制，客户端能否自己 `World:CreateUnit` 并正常渲染未经验证。

**探针结论（2026-09-08，编辑器实例 BaseDefence）**：可以。客户端 `World:CreateUnit("WorldUnit", {RenderMeshId = "official://mesh/59269", ...})` 返回单位、能被 `FindFirstChild` 找到，截图确认画面上正常渲染。

## 决策

`ring` 改走快照：

- 节点状态增加 `shape` 字段（`{kind="ring", center, radius}`，整体更新，不拆分量）。网络上只传圆心与半径。
- 客户端 `eui_render.lua` 增加 `kind = "ring"` 配方，用 `client/ring_geometry` 的换算本地生成几何。
- `set_line` 与光束路径不动，继续按 ADR 0003 就地渲 EffectUnit。

换算落在零依赖纯函数模块 `client/ring_geometry.lua`，常数带实测出处，由 `tests/ring_geometry_test.lua` 钉死。

## 后果

- 形状恢复 resync 能力：`full` / `reset` 会把圈一起带回来，不再只靠 Unit 复制节奏。
- 尺寸正确性有了一条 headless 能跑的缝。`server/host/eui.lua` 里 ring 的两条渲染分支（EffectUnit 环 / WorldUnit 圆盘）合并成一条，只剩状态记录。
- 每帧增量会多出跟随鼠标的预览圆一条 `shape`。`set_ring` 对同值写入不置脏，静态覆盖圈因此不产生流量；一圈仍只对应 1 个 Unit，量级与 ADR 0003 时期相同。
- 白模不吃颜色（见 CONTEXT），覆盖圈因此是单色。业务侧的颜色语义（`board_display.coverage_colour`）保留并继续传递，渲染层忽略——将来换到可染色资源时无需回补。代价是 ring 节点的 `color` 也随快照上网：放置预览圆的合法性每翻转一次，就多发一条渲染层必然忽略的 color 增量（每次翻转一条，非每帧）。
- 只有水平缩放经过标定。垂直方向用固定的 `RING_FLATTEN = 0.2` 把环压平贴地，这是个凭观感选的值，不是实测值：半径越大，环的截面被压得越扁。半径正确性不受影响。
- 真机目视验收（2026-09-08，编辑器实例 BaseDefence）：通电 Turret 落在 (0,2)，悬停出圈，按截图像素粗估外缘半径 ≈4.87，逻辑值 5。「射程圈边缘与被击中敌人位置吻合」未能验收——`spawn_enemy_at` 的方向名不被接受，当场没刷出敌人。
