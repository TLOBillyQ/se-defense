# 真机探针脚本（#19）

客户端注入：`$CLI exec --platform client --file '<Windows 路径>'`，结果用 `$CLI log grep CAMPROBE2|TOUCHPROBE --play-session <id>` 读回。
文件需放在 Windows 侧路径（CLI 是 Windows 进程）。

- `cam_axes_probe.lua`：扫 Pitch/Yaw 组合，打印 ScreenPointToRay / ViewportPointToRay / WorldToScreenPoint，用来标定相机轴约定与屏幕像素空间。
- `touch_space_probe.lua`：在 EUI 位置放一个小节点，用 ScreenGui:SimulateTap 打不同坐标，验证触摸回调坐标与 EUI 位置空间是否同一套。

结论见 `src/client/main.lua` 文件头「真机标定事实」。
