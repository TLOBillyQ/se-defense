local World = game:GetService("World")
local RS = game:GetService("RunService")
local Players = game:GetService("Players")
local function P(...) print("[TOUCHPROBE] " .. string.format(...)) end
local lp = Players.LocalPlayer
local root = lp.PlayerGui.EuiManager:GetRootNode()
local sg = lp.PlayerGui.ScreenGui
P("ScreenGui=%s", tostring(sg))
local node = World:CreateUnit("EUIImage", {
  Parent = root, Name = "bd_touchprobe",
  Position = Vector2.New(200, 1300), Size = Vector2.New(100, 100),
  Opacity = 1, Color = Color.New(255, 0, 0, 255),
  TouchEnabled = true, SwallowTouchEnabled = true, LocalZOrder = 500,
})
node.OnTouchBegan:Connect(function(info)
  P("NODE began id=%s began=(%.1f,%.1f)", tostring(info.TouchID), info.BeganPosition.X, info.BeganPosition.Y)
end)
node.OnTouchEnded:Connect(function(info)
  P("NODE ended id=%s began=(%.1f,%.1f) ended=(%.1f,%.1f)", tostring(info.TouchID), info.BeganPosition.X, info.BeganPosition.Y, info.EndedPosition.X, info.EndedPosition.Y)
end)
node.OnClicked:Connect(function() P("NODE clicked") end)
local taps = { {200,1300}, {200,168}, {960,734} }
local i, wait = 0, 5
local conn
conn = RS.Heartbeat:Connect(function()
  wait = wait - 1
  if wait > 0 then return end
  i = i + 1
  if i > #taps then conn:Disconnect(); P("done"); return end
  wait = 10
  local ok, err = pcall(function() sg:SimulateTap(Vector2.New(taps[i][1], taps[i][2])) end)
  P("SimulateTap(%d,%d) ok=%s %s", taps[i][1], taps[i][2], tostring(ok), tostring(err or ""))
end)
