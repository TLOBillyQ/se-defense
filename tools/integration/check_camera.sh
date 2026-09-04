#!/usr/bin/env bash
# 真机相机朝向回归检查：客户端挂载后相机应立刻且持续为「+z(北) 在屏幕上方、Yaw 恰为 0」。
#
#   tools/integration/check_camera.sh [--no-deploy] [N]     KEEP=1 保留试玩；N = 采样张数（默认 8，约 1 张/s）
#
# 流程：restart 试玩 → 服务端一挂载就在世界 (0,0,+22) 放一个大立方体（北侧标记）→ 客户端挂载起每 ~1s
#       抓一张桌面视窗截图 + 读一次 CurrentCamera.Yaw/Pitch → 每张图数上/下 1/3 区的粉色像素。
# 判定：每张图标记都只在上 1/3 区，且每次 Yaw 回读都恰为 0 → PASS（退出 0）；否则 FAIL（退出 1）。
# 背景：首次写相机（与 Mode 切换同帧）Yaw 不生效，曾出现 yaw=180（南北颠倒）/ 歪 20° 达 4s，5s 重申才归正。
# 前提：编辑器窗口在桌面可见、视窗区不被遮挡（同 run_full.sh）。裁切区 SHOT_RECT="x,y,w,h" 可覆盖。
set -uo pipefail
CLI=${CLI:-/mnt/c/Users/Lzx_8/.eggitor/cli/editor-cli.exe}
WORKSPACE=${EGGY_WORKSPACE:-/mnt/c/Users/Lzx_8/Desktop/dev/eggy/LuaSource_BaseDefence}
STAGE=$(dirname "$WORKSPACE")/se-defense-it; STAGE_WIN=$(wslpath -w "$(dirname "$WORKSPACE")")\\se-defense-it
REPO=$(cd "$(dirname "$0")/../.." && pwd)
SHOT_RECT=${SHOT_RECT:-818,165,1100,841}
DEPLOY=1; N=8
for a in "$@"; do case "$a" in --no-deploy) DEPLOY=0 ;; *) N=$a ;; esac; done
say() { printf '[check_camera] %s\n' "$*"; }
[ $DEPLOY = 0 ] || (cd "$REPO" && lua5.4 tools/deploy.lua) >/dev/null || { say "deploy 失败"; exit 2; }
mkdir -p "$STAGE/shots"; cp "$REPO/tools/integration/capture_viewport.ps1" "$STAGE/"; rm -f "$STAGE"/shots/cam_*.png
"$CLI" play restart --json --timeout 60 >/dev/null 2>&1
SESSION=""
for _ in $(seq 1 60); do
  SESSION=$("$CLI" status --json 2>/dev/null | jq -r 'select(.in_game_runtime==true) | .play_session // empty'); [ -n "$SESSION" ] && break; sleep 1
done
[ -n "$SESSION" ] || { say "拿不到 play session"; exit 2; }
grep_log() { "$CLI" log grep "$1" --play-session "$SESSION" --context 0 --max-matches 2000 --max-bytes 50000000 --json 2>/dev/null | jq -r '.matches[]?.text // empty'; }
shot() { powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$STAGE_WIN\\capture_viewport.ps1" -Out "$STAGE_WIN\\shots\\$1.png" -Rect "$SHOT_RECT" >/dev/null 2>&1; }
for _ in $(seq 1 100); do [ -n "$(grep_log '服务端挂载完成' | head -1)" ] && break; sleep 0.3; done
"$CLI" exec --platform server --json "game:GetService('World'):CreateUnit('WorldUnit',{Name='cam_check_marker',RenderMeshId='official://mesh/59268',BodyType=Enums.BodyType.Static,CanCollide=false,Scale=Vector3.New(6,6,6),Position=Vector3.New(0,6,22)})" | jq -e '.success==true' >/dev/null || { say "放标记失败"; exit 2; }
for _ in $(seq 1 100); do [ -n "$(grep_log '客户端挂载完成' | head -1)" ] && break; sleep 0.2; done
for i in $(seq 1 "$N"); do
  "$CLI" exec --platform client --json "local c=game:GetService('World').CurrentCamera print(string.format('[bd][camchk] shot%02d yaw=%s pitch=%s pos=(%.1f,%.1f,%.1f)', $i, tostring(c.Yaw), tostring(c.Pitch), c.Position.x, c.Position.y, c.Position.z))" >/dev/null 2>&1 &
  shot "$(printf cam_%02d $i)"
  wait
done
FAIL=0
YAWS=$(grep_log 'bd\]\[camchk\] shot' | sed 's/^.*\[camchk\] //')
printf '%s\n' "$YAWS"
printf '%s\n' "$YAWS" | grep -q 'shot' || { say "读不到相机状态"; FAIL=1; }
printf '%s\n' "$YAWS" | grep -v 'yaw=0\(\.0\)\? ' | grep -q shot && { say "FAIL：有采样 Yaw ≠ 0"; FAIL=1; }
for f in "$STAGE"/shots/cam_*.png; do
  [ -s "$f" ] || { say "截图缺失 $f"; FAIL=1; continue; }
  H=$(identify -format %h "$f"); W=$(identify -format %w "$f")
  pink() { convert "$f" -crop "${W}x$((H/3))+0+$1" -fuzz 12% -fill white +opaque '#F2A6B8' -fill black -opaque '#F2A6B8' -negate -colorspace gray -format '%[fx:mean*w*h]' info: 2>/dev/null; }
  TOP=$(pink 0); BOT=$(pink $((2*H/3)))
  printf '%s 北标记像素 上=%.0f 下=%.0f\n' "$(basename "$f")" "$TOP" "$BOT"
  [ "${TOP%.*}" -gt 500 ] && [ "${BOT%.*}" -lt 50 ] || { say "FAIL：$(basename "$f") 北标记不在顶部"; FAIL=1; }
done
[ "${KEEP:-0}" = 1 ] || "$CLI" play stop --json >/dev/null 2>&1
if [ $FAIL = 0 ]; then say "PASS（$N 张全部 +z 在上、Yaw=0）"; exit 0; else say "FAIL（截图在 $STAGE/shots/cam_*.png）"; exit 1; fi
