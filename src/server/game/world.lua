-- src/server/game/world.lua — 世界数据表（规则真源 docs/gdd/00-world.md）。
-- 集中定义：棋盘、起始资金、首波倒计时、实体总表、初始布局（Core + 27 矿点）。
-- 纯数据 + 纯函数：无状态、无宿主依赖，所有系统从这里取共享事实。

local M = {}

-- 棋盘 40 × 40，中心 (0, 0)，x 东为正、z 北为正。
M.board = { min = -20, max = 20 }

-- 棋盘平面上的欧氏距离（放置相交判定、电网相交判定共用）。
function M.dist(ax, az, bx, bz)
  local dx, dz = ax - bx, az - bz
  return math.sqrt(dx * dx + dz * dz)
end

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


-- 波次（GDD 07 W1–W7）：平静期、方向公布阈值、预算、间隔、层级门槛、生成点。
M.wave = {
  calm = 30,               -- W2 平静期秒数
  reveal_at = 5,           -- W2 倒计时 ≤ 5 公布来袭方向
  budget_base = 2,         -- W3 预算 = 2 + (N − 1)
  interval_base = 1,       -- W4 间隔 = max(0.25, 1 − 0.1(N−1))
  interval_step = 0.1,
  interval_min = 0.25,
  tier2_wave = 4,          -- W5 N ≥ 4 解锁 2 型
  tier3_wave = 8,          -- W5 N ≥ 8 解锁 3 型
  tier3_budget = 2.5,      -- W5 剩余 < 2.5 上限降为 2
  tier2_budget = 1.5,      -- W5 剩余 < 1.5 上限降为 1
  spawn_offboard = 6,      -- W7 边界外 6 单位生成
  route_spread = 10,       -- E2 航线指向中心 ± 10 区域内一点
}

-- 来袭方向表（W2）：索引序即随机抽取序，固定最大值时取北。
M.directions = {
  { name = "东", x = 1,  z = 0 },
  { name = "南", x = 0,  z = -1 },
  { name = "西", x = -1, z = 0 },
  { name = "北", x = 0,  z = 1 },
}

-- 按方向名查向量（东/南/西/北）；未知名返回 nil。
function M.direction(name)
  for _, d in ipairs(M.directions) do
    if d.name == name then return d end
  end
  return nil
end

-- 敌人（GDD 07 E1/E4/E5）：三层级血量/足迹/成本，速度 1/s，停止距离 1.2，
-- 停稳后每 1 秒投一枚炸弹，引信 0.3 秒，半径 1.2 内建筑 −0.5。
M.enemy_tiers = {
  [1] = { health = 4,  footprint = 0.3, cost = 1 },
  [2] = { health = 8,  footprint = 0.4, cost = 1.5 },
  [3] = { health = 16, footprint = 0.5, cost = 2.5 },
}
M.enemy_speed = 1
M.enemy_stop_distance = 1.2
M.enemy_separation = 0.6 -- E6 间距下限
M.bomb_interval = 1
M.bomb_fuse = 0.3
M.bomb_radius = 1.2
M.bomb_damage = 0.5

-- 火力（GDD 05 R4/R5）：转速 180°/s、开火夹角 ≤ 2°、伤害 0.5、
-- 射速 2/s、光束 0.05 秒后结算。探测圈/射程圈见实体总表 range。
M.fire_damage = 0.5
M.fire_interval = 0.5
M.fire_beam = 0.05
M.turret_turn_rate = math.pi -- 弧度/秒
M.turret_fire_angle = math.rad(2)

-- 维修（GDD 06 R3）：速率 0.5 血/秒；维修圈见实体总表 range。
M.repair_rate = 0.5

return M
