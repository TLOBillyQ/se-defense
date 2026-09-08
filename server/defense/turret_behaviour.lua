-- 05_BaseDefence 炮塔行为（Turret 的转向/闲逛/攻击部分）。
--
-- 对应上游 Turret.cs 的 Update/IdleBehaviour/AttackBehaviour：通电运转期间
-- 每 tick 把 entity rotation 朝 target_direction 插值；无目标时随机闲逛，
-- 有目标时转向并在进入射界后以 EUI line 光束开火。Turret 组件在
-- server.defense.turret 中按 is_running 切换挂载这些行为。

local TurretBehaviour = {}

local function clamp(x, lo, hi)
  if x < lo then return lo end
  if x > hi then return hi end
  return x
end

local function normalize_angle(a)
  while a > math.pi do a = a - 2 * math.pi end
  while a < -math.pi do a = a + 2 * math.pi end
  return a
end

local function angle_diff(current, target)
  return normalize_angle(target - current)
end

-- 转向：把 entity rotation 朝 target_direction 插值（每 tick dt 步进）。
function TurretBehaviour.rotate(turret, dt)
  local entity = turret.entity
  local dir = turret.target_direction
  if not dir then
    return
  end
  local dx, dz = dir.x, dir.z
  local sq = dx * dx + dz * dz
  if sq < 1e-8 then
    return
  end
  local target_angle = math.atan(dz, dx)
  local current = entity:get_rotation()
  local diff = angle_diff(current, target_angle)
  local step = turret.rotation_speed * dt
  if math.abs(diff) <= step then
    entity:set_rotation(target_angle)
  else
    entity:set_rotation(current + (diff > 0 and step or -step))
  end
end

-- 闲逛：无目标时每隔 rng(1, 3) 秒随机换一个朝向（GDD 05 R8：纯表现层，
-- 不影响规则）。编排设定过枪口朝向（muzzle_pinned）时不改向——验收
-- 「枪口朝<方向>」约定设定后保持到首次接敌。
function TurretBehaviour.idle(turret, s)
  s:coroutine(turret.game_tick, function(yield, wait_seconds)
    while true do
      wait_seconds(turret.rng(1, 3))
      if not turret.muzzle_pinned then
        local angle = turret.rng(0, 2 * math.pi)
        turret.target_direction = { x = math.cos(angle), z = math.sin(angle) }
      end
    end
  end)
end

-- 攻击：跟踪目标位置、在射界内按 fire_rate 开火（光束 flash 后伤害落地）。
-- target 为 Turret.target memo 选出的最近被追踪敌人。
function TurretBehaviour.attack(turret, s, target)
  local entity = turret.entity
  -- 复用 init 阶段创建并捕获的光束节点。
  local beam_node = turret.beam_node

  s:coroutine(turret.game_tick, function(yield, wait_seconds)
    local cooldown = 0
    local last_time = turret.game_tick:time()
    while true do
      local now = turret.game_tick:time()
      local dt = now - last_time
      last_time = now

      local target_entity = target.entity
      if not target_entity then
        break
      end

      local target_pos = target_entity:get_position()
      local pos = entity:get_position()
      local dx = target_pos.x - pos.x
      local dz = target_pos.z - pos.z
      turret.target_direction = { x = dx, z = dz }

      cooldown = cooldown - dt
      local current_rot = entity:get_rotation()
      local muzzle_x = math.cos(current_rot)
      local muzzle_z = math.sin(current_rot)
      local aim_sq = dx * dx + dz * dz
      local aim_x, aim_z
      if aim_sq > 1e-8 then
        local inv = 1 / math.sqrt(aim_sq)
        aim_x = dx * inv
        aim_z = dz * inv
      else
        aim_x, aim_z = muzzle_x, muzzle_z
      end
      local dot = muzzle_x * aim_x + muzzle_z * aim_z
      -- clamp for acos safety
      dot = clamp(dot, -1, 1)
      local angle = math.acos(dot)

      if cooldown <= 0 and angle <= turret.fire_angle then
        cooldown = 1 / turret.fire_rate
        beam_node:set_line(pos, target_pos)
        beam_node:set_visible(true)
        wait_seconds(turret.beam_flash_time)
        beam_node:set_visible(false)
        if target.health then
          target.health:damage(turret.damage)
        end
      end
      yield()
    end
  end)

  s:on_cleanup(function()
    if beam_node then
      beam_node:set_visible(false)
    end
  end)
end

return TurretBehaviour
