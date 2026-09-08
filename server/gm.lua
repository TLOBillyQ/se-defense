-- server/gm.lua — GM 面（`$CLI exec --platform server` / 无头 harness 驱动）。
--
-- 位置：不属于业务包也不属于宿主层（server/host/），它站在
-- 两者之上做编排与读回，因此与 main.lua 同级；host 层不得反向依赖业务模块。
--
-- 职责：把编排与读回动作翻译成对业务的调用并打日志。领域问题（谁在场、按
-- 坐标找建筑）一律问 server/match/roster.lua，这里只做转发与格式化，不重做规则。
--
-- ctx 由 server/main.lua 提供（root/panel 每次重开都换对象，全部经访问器取）：
--   host          宿主接缝
--   root()        当前组合根
--   panel()       当前放置面板（server/ui/build_panel.lua）
--   restart(why)  整局重开（拆树 → 清场 → 重建 → 重挂每局挂件 → 广播 reset）
--   stats()       { ticks, uptime, seq } 驱动器计数（status 日志用）
--   log(fmt, ...) 日志
--
-- 返回的表挂到 _G.bd；bd.root 由 main.lua 在重开后回填（harness 直读）。

local Roster = require("server.match.roster")
local WorldData = require("server.kernel.world_data")
local BuildPanel = require("server.ui.build_panel")

local M = {}

local KILL = 99999

function M.create(ctx)
  local host, root, panel, log = ctx.host, ctx.root, ctx.panel, ctx.log

  local function num(v) return tonumber(v) end

  local function building_or_log(what, kind, x, z)
    local b, rec = Roster.building_at(root(), tostring(kind), num(x), num(z))
    if not b then log("GM %s：(%s,%s) 处没有 %s", what, tostring(x), tostring(z), tostring(kind)) end
    return b, rec
  end

  local bd = {
    root = root(), -- 无头 harness / 自动化直读（tools/headless/run_server.lua）
  }

  function bd.status()
    local gs = root().game_state
    local st = ctx.stats()
    log("STATUS mode=%s ticks=%d uptime=%.1fs money=%s core_hp=%.2f entities=%d eui_nodes=%d seq=%d gen=%d",
      tostring(gs.mode:now()), st.ticks, st.uptime,
      tostring(gs.money:now()),
      gs.core and gs.core.health.hp_fraction:now() or -1,
      #host.entity.all(), #host.eui.order, st.seq, host.eui.generation)
  end

  -- GDD 01 R2：与客户端 start 意图同一守卫（只在 Pregame 受理）。
  function bd.start()
    local gs = root().game_state
    if gs.mode:now() == "Pregame" then
      gs:start_game()
      log("GM start_game")
    else
      log("GM start 被拒（mode=%s）", tostring(gs.mode:now()))
    end
  end

  -- 重开（#28）：与客户端 restart 意图同一路径，但不限终局（集成测试/救场用）
  function bd.restart()
    ctx.restart("gm")
  end

  -- 全部矿点直接采空 → 业务判 Victory（不经供电/采集，秒到终局）
  function bd.mine_out()
    local n = 0
    for _, r in ipairs(root().resources) do
      if r.remaining:now() > 0 then r.remaining:set(0); n = n + 1 end
    end
    log("GM mine_out → %d 个矿点置空", n)
  end

  -- 采空前 n 个未采空矿点（验收编排「采空N个矿点」）
  function bd.mine_n(n)
    n = num(n) or 0
    local done = 0
    for _, r in ipairs(root().resources) do
      if done >= n then break end
      if r.remaining:now() > 0 then r.remaining:set(0); done = done + 1 end
    end
    log("GM mine_n(%d) → %d", n, done)
  end

  -- 设定某坐标矿点剩余量（0 即离场；验收编排）
  function bd.set_site(x, z, remaining)
    local site = Roster.site_at(root(), num(x), num(z))
    if not site then log("GM set_site：(%s,%s) 处没有矿点", tostring(x), tostring(z)); return end
    site.remaining:set(num(remaining) or 0)
  end

  -- 打死 Core → 碎裂 2 秒离场后业务判 GameOver（GDD 01 R5）
  function bd.kill_core()
    local core = root().game_state.core
    core.health:damage(KILL)
    log("GM kill_core → alive=%s", tostring(core.health.is_alive:now()))
  end

  -- 「X死亡」编排：杀死场上第一个存活的该类型建筑
  function bd.kill(kind)
    kind = tostring(kind)
    if kind == "Core" then return bd.kill_core() end
    local b = Roster.first_alive(root(), kind)
    if not b then log("GM kill(%s)：场上没有该类型建筑", kind); return end
    b.health:damage(KILL)
  end

  -- 「一座已建好的 X 位于 (x,z)」编排：直接造好（不扣费、不经放置校验），
  -- 可选 hp 把血量置为指定值（验收「一座血量为 N 的 X」）。
  function bd.spawn_building(kind, x, z, hp)
    local r = root()
    local spec = r.building_specs and r.building_specs[Roster.key_of(kind)]
    if not spec then log("GM spawn_building：未知类型 %s", tostring(kind)); return end
    local inst = r.pool:spawn(spec, { x = num(x), y = 0, z = num(z) })
    local b = inst.epoch and inst.epoch.building
    if b then
      b.pool_instance = inst
      if hp then
        local max_hp = b.health.max_hp:now()
        b.health:damage(math.max(0, max_hp - num(hp)))
      end
    end
    log("GM spawn_building(%s, %s, %s, %s)", tostring(kind), tostring(x), tostring(z), tostring(hp))
  end

  -- 「位于 (x,z) 的 X 被摧毁」编排：摧毁即离场（不经碎裂、不扣费）。
  function bd.destroy_at(kind, x, z)
    local b, rec = building_or_log("destroy_at", kind, x, z)
    if not b then return end
    if rec then
      root().pool:despawn(rec)
    elseif b.entity and b.entity.destroy then
      b.entity:destroy()
    end
  end

  -- 「位于 (x,z) 的 X 受到炸弹伤害 N」编排：直接扣血（死亡走 2 秒碎裂）。
  function bd.bomb_damage(kind, x, z, dmg)
    local b = building_or_log("bomb_damage", kind, x, z)
    if b then b.health:damage(num(dmg) or 0) end
  end

  -- 「设定当前波次为 N」编排：波号置 N、倒计时 30、方向未知（重抽）。
  function bd.set_wave(n)
    root().wave_director:set_wave(num(n) or 1)
  end

  -- 「随机源固定为最大值」编排：每次随机抽取都取上界，并重抽未公布的方向。
  function bd.fix_rng_max()
    local wd = root().wave_director
    wd.rng01 = function() return 1 end
    wd:reroll_direction()
  end

  -- 「进入进攻期」编排：直接切换进攻期标志（不生成敌人）。
  function bd.enter_assault()
    root().wave_director:set_assault(true)
  end

  -- 「本波全灭」编排：杀死本波全部敌人并退出进攻期。
  function bd.wave_cleared()
    local wd = root().wave_director
    wd:kill_all()
    wd:set_assault(false)
  end

  -- 「在 (x,z) 生成一个航线朝<方向>的<T>型敌人」编排：计入本波。
  function bd.spawn_enemy_at(x, z, dir_name, tier)
    local dir = WorldData.direction(tostring(dir_name))
    if not dir then log("GM spawn_enemy_at：未知方向 %s", tostring(dir_name)); return end
    root().wave_director:spawn({
      x = num(x), z = num(z),
      tier = num(tier) or 1,
      heading = { x = dir.x, z = dir.z },
    })
  end

  -- 「第 N 个敌人死亡」编排。
  function bd.kill_enemy_nth(n)
    local e = root().enemies[num(n)]
    if e and e.health then e.health:damage(KILL) end
  end

  -- 「位于 (x,z) 的 Turret 枪口朝<方向>」编排：立即设定枪口朝向
  -- （entity 朝向与 target_direction 同步；验收设定初始朝向用）。
  function bd.aim_turret(x, z, dir_name)
    local dir = WorldData.direction(tostring(dir_name))
    if not dir then log("GM aim_turret：未知方向 %s", tostring(dir_name)); return end
    local b, rec = building_or_log("aim_turret", "Turret", x, z)
    if not b or not rec then return end
    local turret = rec.epoch
    turret.target_direction = { x = dir.x, z = dir.z }
    turret.muzzle_pinned = true -- 编排设定的朝向保持到首次接敌（见 TurretBehaviour.idle）
    turret.entity:set_rotation(math.atan(dir.z, dir.x))
    log("GM aim_turret(%s,%s) → %s", tostring(x), tostring(z), tostring(dir_name))
  end

  -- 注入一次棋盘点 tap（绕过网络的自动化输入；等价客户端 tap 意图）
  function bd.tap(x, z)
    local ok = host.input.intent_tap(num(x), num(z))
    log("GM tap(%s,%s) → %s", tostring(x), tostring(z), tostring(ok))
  end

  function bd.cancel()
    host.input.intent_cancel()
    log("GM cancel")
  end

  -- 进入放置模式（与客户端按钮的 place 意图同一入口）
  function bd.place(key)
    local ok, why = BuildPanel.place(panel(), tostring(key))
    log("GM place(%s)：%s", tostring(key), ok and "placing 已置位" or tostring(why))
  end

  -- 放置流状态一览（集成测试读回）
  function bd.placing()
    local bi = root().board_interactions
    local p = bi.placing:now()
    local m = host.input.get_mouse_world_point()
    log("PLACING key=%s valid=%s mouse=%s",
      p and p.key or "nil", tostring(bi.placement_valid:now()),
      m and string.format("(%.2f,%.2f)", m.x, m.z) or "nil")
  end

  -- 直接设余额（集成测试铺建筑用）
  function bd.money(n)
    local gs = root().game_state
    gs.money:set(num(n) or 0)
    log("GM money=%s", tostring(gs.money:now()))
  end

  -- 对某建筑（按实体 id）造成伤害；测试「relay 被毁 → 下游断电」
  function bd.damage(id, amount)
    local rec = root().pool and root().pool:live_record(num(id))
    local b = rec and rec.epoch and rec.epoch.building
    if not b then log("GM damage：实体 %s 不是 live 建筑", tostring(id)); return end
    b.health:damage(num(amount) or 999)
    log("GM damage(%s,%s) → alive=%s", tostring(id), tostring(amount), tostring(b.health.is_alive:now()))
  end

  -- live 建筑一览：id / 类型 / 供电 / 血量
  function bd.buildings()
    Roster.each_building(root(), function(b, rec)
      local p = rec.entity.position
      log("building #%d %s @(%.1f,%.1f) powered=%s hp=%.2f",
        rec.entity.id, tostring(rec.spec and rec.spec.key), p.x, p.z,
        b.power and tostring(b.power.has_power:now()) or "n/a",
        b.health.hp_fraction:now())
      return false
    end)
  end

  -- 形状单位（覆盖圈/连线/光束）一览
  function bd.dump_shapes()
    for _, sh in ipairs(host.eui.shapes()) do
      -- ring 走快照、没有特效资源，所以打的是「怎么渲的」而不是特效 id。
      log("shape %s kind=%s via=%s visible=%s%s", sh.path, sh.kind, tostring(sh.effect or sh.route),
        tostring(sh.visible), sh.radius and string.format(" r=%.2f", sh.radius) or "")
    end
  end

  -- 当前波次一览（GDD 07 状态：倒计时/方向/进攻期/预算/生成簿记）
  function bd.wave()
    local w = root().wave_director.wave:now()
    log("WAVE number=%d countdown=%.2f assault=%s front=%s budget_left=%.2f spawned=%d cost_sum=%.2f",
      w.number, w.countdown, tostring(w.assault), tostring(w.front),
      w.budget_left, w.spawned, w.cost_sum)
  end

  -- 存活敌人一览
  function bd.enemies()
    local alive = Roster.alive_enemies(root())
    for _, en in ipairs(alive) do
      local p = en.entity.position
      log("enemy #%d %s @(%.1f,%.1f) hp=%.2f", en.entity.id, en.prefab, p.x, p.z, en.health.hp_fraction:now())
    end
    log("ENEMIES alive=%d", #alive)
  end

  -- 清场：击杀全部存活敌人（触发 wave_defeated → 下一波倒计时）
  function bd.kill_enemies()
    local alive = Roster.alive_enemies(root())
    for _, en in ipairs(alive) do en.health:damage(KILL) end
    log("GM kill_enemies → %d", #alive)
  end

  -- 矿点一览：id / 位置 / 剩余 / 供电
  function bd.resources()
    local r = root()
    for _, site in ipairs(r.resources) do
      local p = site.entity.position
      log("resource #%d @(%.1f,%.1f) remaining=%d powered=%s", site.entity.id, p.x, p.z,
        site.remaining:now(), site.power and tostring(site.power.has_power:now()) or "n/a")
    end
    log("RESOURCES remaining_sites=%d money=%s rate=%.2f", r.game_state.resources_remaining:now(),
      tostring(r.game_state.money:now()), r.game_state.collect_rate:now())
  end

  function bd.dump_entities()
    for _, e in ipairs(host.entity.all()) do
      local p = e.position
      log("entity #%d %s @(%.1f,%.1f,%.1f) active=%s", e.id, tostring(e.prefab), p.x, p.y, p.z, tostring(e.active))
    end
  end

  -- 已知接口偏宽（#43 记录不改）：这里读的 _shape_only 是 eui 的私有字段，
  -- 快照面（shapes/order/nodes）没暴露「是不是纯形状节点」这个问题的答案。
  -- 加只读访问器还是让 shapes() 自带该标记，留待后续评估。
  function bd.dump_nodes()
    for _, path in ipairs(host.eui.order) do
      local n = host.eui.nodes[path]
      if n then
        log("node %s text=%q visible=%s fill=%.2f shape=%s",
          path, n.text, tostring(n.visible), n.fill, tostring(n._shape_only == true))
      end
    end
  end

  return bd
end

return M
