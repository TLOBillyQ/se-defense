# 真机整局验收截图（#30）

`tools/integration/run_full.sh` 每次跑完自动覆盖这三张图，是 HITL 目视留待项的统一对照物（最近一次通过的运行）。

| 文件 | 检查点 | 目视要点 |
|---|---|---|
| `victory.png` | 矿点采空 → Victory banner | banner 文案、Restart 按钮位置/可读性、四建筑与覆盖圈 |
| `pregame.png` | 客户端点 Restart 后回 Pregame | 旧单位无残留、7 个实体重建、Pregame banner |
| `gameover.png` | 第二局 Core 被毁 → GameOver banner | banner 文案、Core 消失、Restart 按钮 |

截图来源：`editor-cli screenshot game/editor` 在本环境视窗恒全白（GPU 画面不走 PrintWindow），
故用 `tools/integration/capture_viewport.ps1` 抓桌面合成并裁切编辑器视窗区（默认 1920×1080 下 `818,165,1100,841`，
`SHOT_RECT` 可覆盖）。**前提：跑测时编辑器窗口在桌面可见、视窗区不被其他窗口遮挡。**

## 相机朝向回归

`tools/integration/check_camera.sh [--no-deploy] [N]`：开局在世界 +z（North）放大立方体，客户端挂载起每秒抓屏 + 读 `CurrentCamera.Yaw`，
要求每张图标记都在顶部且 Yaw 恰为 0。锁定的 bug：首次写相机与 Mode 切换同帧时 Yaw 不生效，
开局 1s～5s 画面随机为南北颠倒（yaw=180）或歪 20°，5s 重申才归正（修复：首写后连写 2 帧）。

## 目视留待（打磨阶段）

首轮截图（2026-09-04）看到但未处理、留给打磨的观感问题：

- Restart 按钮（白色胶囊）压在 Core 血条位置附近，按钮文字对比度低，几乎读不出 "Restart"。
- 建筑/矿点/Core 目视均为粉色，与 entity.lua 期望的建筑配色不符（延续 #21「圆盘显蓝而非红/绿」的 ModelColor1 未解问题）。
- 棋盘地面（深色矩形）没有以 Core 为中心，向左上偏。
- 终局后 HUD 仍显示下一波倒计时（"Wave 4: East in 2s"），业务文案，打磨时决定是否隐藏。
