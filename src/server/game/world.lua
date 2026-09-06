-- src/server/game/world.lua — 世界数据表（规则真源 docs/gdd/00-world.md）。
-- 集中定义：棋盘、起始资金、首波倒计时、实体总表、初始布局（Core + 27 矿点）。
-- 纯数据模块：无状态、无宿主依赖，所有系统从这里取共享事实。

local M = {}

-- 棋盘 40 × 40，中心 (0, 0)，x 东为正、z 北为正。
M.board = { min = -20, max = 20 }

M.starting_money = 100
M.first_wave_countdown = 30
-- 通电/断电去抖（GDD 03 R8 / README「已知的移植差异」）。
M.power_debounce = 0.15
-- 采集：每个通电矿点非进攻期每 0.8 秒兑 1 单位为 $1（GDD 02 R3/R6）。
M.harvest_interval = 0.8
M.harvest_rate = 1.25
-- 建筑死亡后碎裂 2 秒离场（docs/gdd/README.md「已知的移植差异」）。
M.crumble_seconds = 2

-- 实体总表：血量 / 足迹半径 / 供电圈 / 收电圈 / 功能圈(range) / 价格。
-- 矿点（Site）无血量、不可建造；Core 不可建造。
M.specs = {
  Core   = { health = 10, footprint = 0.5, provide = 4, receive = 0.1 },
  Relay  = { health = 2,  footprint = 0.3, provide = 3, receive = 0.1, price = 10 },
  Radar  = { health = 10, footprint = 0.4, provide = 0, receive = 0.1, range = 8, price = 50 },
  Turret = { health = 5,  footprint = 0.4, provide = 0, receive = 0.1, range = 5, price = 50 },
  Repair = { health = 10, footprint = 0.5, provide = 0, receive = 0.1, range = 5, price = 100 },
  Site   = { footprint = 0.5, provide = 0, receive = 0.5 },
}

M.core = { x = 0, z = 0 }

-- 27 个矿点，每个剩余量 300（坐标照 GDD 00 表格）。
M.site_remaining = 300
M.sites = {
  { x = -0.98,  z = 13.91 },  { x = 14.07,  z = 14.95 },  { x = -13.73, z = 14.47 },
  { x = -0.18,  z = -16.47 }, { x = 13.96,  z = 13.38 },  { x = 1.08,   z = -15.16 },
  { x = -15.74, z = 0.87 },   { x = -13.91, z = -15.26 }, { x = 0.47,   z = 15.53 },
  { x = 15.12,  z = -14.40 }, { x = -15.20, z = -14.35 }, { x = -16.61, z = -0.35 },
  { x = 13.58,  z = -15.62 }, { x = 1.71,   z = 0.06 },   { x = 15.48,  z = -15.81 },
  { x = -8.10,  z = -7.85 },  { x = 7.61,   z = 7.26 },   { x = -1.30,  z = -1.26 },
  { x = 15.76,  z = 14.21 },  { x = -7.84,  z = 7.67 },   { x = -15.22, z = -16.03 },
  { x = -15.64, z = 14.73 },  { x = 15.13,  z = 0.75 },   { x = 13.97,  z = -0.54 },
  { x = -15.31, z = 13.35 },  { x = 6.15,   z = -7.75 },  { x = -1.99,  z = -0.10 },
}

return M
