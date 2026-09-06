# 14 悬停信息

## 规则

- V1 悬停命中：落点为半径 0 的点，与足迹圆相交的单位中取最近者；无命中则无悬停。
- V2 放置态中不悬停。
- V3 描述文本（英文原文，首行为建筑名大写）：
  - CORE：Seeds the power grid, all buildings must trace a path to it for receiving power. / Game is over if this building is destroyed.
  - RELAY：Extends the power grid, relaying power to any building inside its coverage. / Buildings lose power when their path to the Core is broken.
  - RADAR：Reveals enemies inside its coverage to turrets. / Turrets cannot fire at enemies that no radar has revealed.
  - TURRET：Fires at enemies inside its coverage that radar has revealed. / Pair with radar coverage — a turret alone sees nothing.
  - REPAIR：Repairs the most damaged building inside its coverage, one at a time. / Repair buildings can mend each other, but never themselves.
  - RESOURCE：Generates $1.25/s while powered. Harvesting pauses during an attack. / `<剩余量> remaining.`；采空后文本为空。
- V4 目的地无鼠标：悬停 = 触摸按住/点击空闲单位，见 16。

## 必须覆盖的场景

1. 悬停 Relay 显示 RELAY 描述。
2. 悬停矿点显示剩余量，采集后数字变化。
3. 放置态中不产生悬停。
