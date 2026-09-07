# ADR 0001：服务端权威 spoke 树 + Heartbeat 固定步长节拍

状态：已采纳（源自 Gitea 票 #7 决议、#10 真机验证）

## 背景

SE 状态同步地图有 `server/` 与 `client/` 两个 realm，各自 `main.lua` 自动执行。业务（Base Defence）是一棵 spoke 响应式树，需要固定步长的 GameTick 驱动。SE 文档中没有 `EVENT.REPEAT_TIMEOUT` 这类周期事件（见 `docs/research/realm-model-facts.md`），也没有关卡级生命周期事件。

曾评估的替代方案：客户端本地仿真（零网络，业务同样零改动），但违反文档权威模型，服务端服务要反向跨端，未来多人必须整体搬家。

## 决策

1. 业务 spoke 树只在服务端存在，且只有一棵 Auto 树（组合根 `GameRootFull`）。客户端零 spoke 树，是哑镜像。
2. 服务端用 `RunService.Heartbeat` 积累时间驱动 `GameTick`，步长 1/30 秒，对齐宿主 30fps 逻辑帧。
3. 每帧最多追赶 4 步，超出的积累时间直接丢弃，不做追赶。
4. 一帧内的所有步进包在 `SpokeRuntime.batch` 里，合并成一次 flush。
5. 输入反向通道：客户端捕获层 → `FireServer` 意图 → `host.input` 队列；tap 意图在下一步举为一帧边沿，"按下只持续一帧"。

## 后果

- 真机实测 30fps 稳定，jitter 为 0。
- 业务模块零改动即可在无头桩（`tools/headless/se_stub.lua`）与真机之间切换，因为节拍与输入都经适配层。
- 卡顿时丢步而非追赶，游戏时间会慢于墙钟。这是有意取舍，避免一帧内大量步进造成雪崩。
