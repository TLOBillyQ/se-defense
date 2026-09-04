local World = game:GetService("World")
local CS = game:GetService("CameraService")
local RS = game:GetService("RunService")
local Players = game:GetService("Players")
local function v3(v) if not v then return "nil" end return string.format("(%.2f,%.2f,%.2f)", v.x or v.X, v.y or v.Y, v.z or v.Z) end
local function P(...) print("[CAMPROBE2] " .. string.format(...)) end
local res = Players.LocalPlayer.PlayerGui.EuiManager:GetDeviceResolution()
local cx, cy = res.X / 2, res.Y / 2
local configs = { {90,0}, {0,0}, {0,90}, {-45,0}, {-90,0} }
local idx, wait = 0, 0
local conn
local function read(tag)
  local cam = World.CurrentCamera
  P("%s readback pitch=%s yaw=%s pos=%s", tag, tostring(cam.Pitch), tostring(cam.Yaw), v3(cam.Position))
  for _, p in ipairs({ {"scr0", 0, 0}, {"scrC", cx, cy}, {"scrC+x200", cx+200, cy} }) do
    local r = CS:ScreenPointToRay(p[2], p[3], 0)
    P("%s ray %s origin=%s dir=%s", tag, p[1], v3(r.Origin), v3(r.Direction))
  end
  local r = CS:ViewportPointToRay(0.5, 0.5, 0); P("%s vp(.5,.5) dir=%s", tag, v3(r.Direction))
  r = CS:ViewportPointToRay(0, 0, 0); P("%s vp(0,0) dir=%s", tag, v3(r.Direction))
  r = CS:ViewportPointToRay(1, 1, 0); P("%s vp(1,1) dir=%s", tag, v3(r.Direction))
  for _, w in ipairs({ {0,0,0}, {10,0,0}, {0,0,10} }) do
    local s, on = CS:WorldToScreenPoint(Vector3.New(w[1], w[2], w[3]))
    local v, onv = CS:WorldToViewportPoint(Vector3.New(w[1], w[2], w[3]))
    P("%s w2s (%d,%d,%d) scr=%s on=%s vp=%s onv=%s", tag, w[1], w[2], w[3], v3(s), tostring(on), v3(v), tostring(onv))
  end
end
conn = RS.Heartbeat:Connect(function()
  if wait > 0 then wait = wait - 1; if wait == 0 then read(string.format("P%d/Y%d", configs[idx][1], configs[idx][2])) end; return end
  idx = idx + 1
  if idx > #configs then conn:Disconnect(); P("done"); return end
  local cam = World.CurrentCamera
  cam.Mode = Enums.CameraMode.NONE
  cam.Position = Vector3.New(0, 60, 0)
  cam.Pitch = configs[idx][1]; cam.Yaw = configs[idx][2]
  CS:ManualRefresh()
  wait = 3
end)
