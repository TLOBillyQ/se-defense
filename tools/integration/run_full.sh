#!/usr/bin/env bash
# #30 真机整局验收一键入口（WSL 侧）。打磨阶段每次改动的回归门。
#
#   tools/integration/run_full.sh [--no-deploy] [--keep] [--timeout <s>]
#
# 流程：deploy → play restart → 等运行时 + 客户端标定 → 注入 full_server.lua →
#       轮询日志：WAIT 行 → 做客户端点击/截图 → go()；DONE 行 → 收尾 →
#       汇总 CHECK ok/FAIL + log trace 错误/告警 → 截图落 docs/acceptance/ → 退出码。
# 退出码 0 = 全部 CHECK ok 且 0 错误 0 告警；否则 1。
#
# WAIT 协议见 full_server.lua 文件头：client:button <path> / client:board <x> <z> / shot:<name>。
# 截图：优先 `screenshot game`；本环境视窗恒全白（#19 捕获限制）时回退 PowerShell 桌面抓屏裁切视窗区
#       （tools/integration/capture_viewport.ps1，前提：编辑器窗口在桌面可见）。裁切区可用 SHOT_RECT="x,y,w,h" 覆盖。

set -uo pipefail

CLI=${CLI:-/mnt/c/Users/Lzx_8/.eggitor/cli/editor-cli.exe}
REPO=$(cd "$(dirname "$0")/../.." && pwd)
WORKSPACE=${EGGY_WORKSPACE:-$(cd "$REPO" && lua5.4 -e 'package.path="./?.lua;"..package.path; print(require("tools.eggy_workspace").resolve())')}  # 默认值真源：tools/eggy_workspace.lua
# 注入文件必须在 Windows 侧（CLI 是 Windows 进程）：放工作区旁的 staging 目录，不进工作区（避免被同步进编辑器）
STAGE=$(dirname "$WORKSPACE")/se-defense-it
STAGE_WIN=$(wslpath -w "$(dirname "$WORKSPACE")")\\se-defense-it
OUT_DIR=$REPO/docs/acceptance
SHOT_RECT=${SHOT_RECT:-818,165,1100,841}

DEPLOY=1; KEEP=0; TIMEOUT=420
while [ $# -gt 0 ]; do
  case "$1" in
    --no-deploy) DEPLOY=0 ;;
    --keep) KEEP=1 ;;
    --timeout) TIMEOUT=$2; shift ;;
    *) echo "未知参数 $1" >&2; exit 2 ;;
  esac
  shift
done

say() { printf '[run_full] %s\n' "$*"; }
die() { say "$*"; exit 1; }

# ── 1. 部署 ────────────────────────────────────────────────────────
if [ $DEPLOY = 1 ]; then
  (cd "$REPO" && lua5.4 tools/deploy.lua) || die "deploy 失败"
fi
mkdir -p "$STAGE/shots" "$OUT_DIR"
cp "$REPO/tools/integration/full_server.lua" "$REPO/tools/integration/capture_viewport.ps1" "$STAGE/"

# ── 2. 重启试玩 ─────────────────────────────────────────────────────
say "play restart …"
RESTART_JSON=$("$CLI" play restart --json --timeout 60 2>&1)
SESSION=$(printf '%s' "$RESTART_JSON" | jq -r '.session // .play_session // .data.session // empty' 2>/dev/null)
if [ -z "$SESSION" ]; then
  # 回退：轮询 status 拿 play_session
  for _ in $(seq 1 30); do
    SESSION=$("$CLI" status --json 2>/dev/null | jq -r 'select(.in_game_runtime==true) | .play_session // empty')
    [ -n "$SESSION" ] && break
    sleep 1
  done
fi
[ -n "$SESSION" ] || die "拿不到 play session：$RESTART_JSON"
say "session=$SESSION"

for _ in $(seq 1 60); do
  "$CLI" status --json 2>/dev/null | jq -e '.in_game_runtime==true' >/dev/null && break
  sleep 1
done
"$CLI" status --json | jq -e '.in_game_runtime==true' >/dev/null || die "运行时未就绪"

grep_log() { # <regex> [extra args]
  local re=$1; shift
  "$CLI" log grep "$re" --play-session "$SESSION" --context 0 --max-matches 2000 --max-bytes 50000000 --json "$@" 2>/dev/null \
    | jq -r '.matches[]?.text // empty' | sed 's/"$//'
}
wait_log() { # <regex> <seconds> <desc>
  local re=$1 secs=$2 desc=$3
  for _ in $(seq 1 "$secs"); do
    [ -n "$(grep_log "$re" | head -1)" ] && { say "就绪：$desc"; return 0; }
    sleep 1
  done
  die "等待超时：$desc"
}
wait_log '服务端挂载完成' 60 '服务端挂载'
wait_log '客户端挂载完成' 60 '客户端挂载'
wait_log '相机标定：' 30 '客户端相机标定'
sleep 1

exec_lua() { # <platform> <lua>
  "$CLI" exec --platform "$1" --json "$2" | jq -e '.success==true' >/dev/null || say "exec $1 失败：$2"
}
shot() { # <name>
  local name=$1 win ok=0
  win="$STAGE_WIN\\shots\\$name.png"
  rm -f "$STAGE/shots/$name.png"
  "$CLI" screenshot game --output "$win" --json 2>/dev/null | jq -e '.success==true' >/dev/null && ok=1
  if [ $ok = 0 ]; then
    say "screenshot game 不可用（视窗全白），改抓桌面视窗区 $SHOT_RECT（$name）"
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$STAGE_WIN\\capture_viewport.ps1" -Out "$win" -Rect "$SHOT_RECT" >/dev/null 2>&1 && ok=1
  fi
  if [ $ok = 1 ] && [ -s "$STAGE/shots/$name.png" ]; then
    cp "$STAGE/shots/$name.png" "$OUT_DIR/$name.png" && say "截图 → docs/acceptance/$name.png"
  else
    say "截图失败：$name"
  fi
}
dispatch() { # "<action>; <action>"
  local acts act
  IFS=';' read -r -a acts <<<"$1"
  for act in "${acts[@]}"; do
    act=$(printf '%s' "$act" | sed 's/^ *//;s/ *$//')
    set -- $act
    case "$1" in
      client:button) exec_lua client "_G.bd_client.tap_button('$2')" ;;
      client:board)  exec_lua client "_G.bd_client.tap_board($2, $3)" ;;
      shot:*)        shot "${1#shot:}" ;;
      *) say "未知动作：$act" ;;
    esac
    sleep 0.5
  done
}

# ── 3. 注入服务端剧本并编排 ─────────────────────────────────────────
say "注入 full_server.lua"
"$CLI" exec --platform server --file "$STAGE_WIN\\full_server.lua" --json | jq -e '.success==true' >/dev/null || die "注入失败"

HANDLED=0; DONE_LINE=""; T0=$(date +%s)
while :; do
  MARKS=$(grep_log '\[bd\]\[itf\] (WAIT |ITF DONE)')
  N=$(printf '%s\n' "$MARKS" | grep -c 'itf\] WAIT ' || true)
  if [ "$N" -gt "$HANDLED" ]; then
    LINE=$(printf '%s\n' "$MARKS" | grep 'itf\] WAIT ' | sed -n "$((HANDLED + 1))p")
    ACTIONS=${LINE#*itf\] WAIT }
    say "WAIT → $ACTIONS"
    dispatch "$ACTIONS"
    exec_lua server "_G.bd_it.go()"
    HANDLED=$((HANDLED + 1))
    continue
  fi
  DONE_LINE=$(printf '%s\n' "$MARKS" | grep 'ITF DONE' | head -1)
  [ -n "$DONE_LINE" ] && break
  [ $(( $(date +%s) - T0 )) -gt "$TIMEOUT" ] && { say "整局超时 ${TIMEOUT}s"; break; }
  sleep 1
done

# ── 4. 汇总 ─────────────────────────────────────────────────────────
echo
grep_log '\[bd\]\[itf\] ' | sed 's/^.*\[bd\]\[itf\] //'
echo
CHECKS=$(grep_log 'itf\] CHECK ')
OKS=$(printf '%s\n' "$CHECKS" | grep -c 'CHECK ok' || true)
FAILS=$(printf '%s\n' "$CHECKS" | grep -c 'CHECK FAIL' || true)
ERRS=$(grep_log 'STEP ERROR' | wc -l)
TRACE=$("$CLI" log trace --play-session "$SESSION" 2>/dev/null)
TRACE_ERR=$(printf '%s' "$TRACE" | jq -r '[.errors // [], .issues // [] | length] | add' 2>/dev/null); TRACE_ERR=${TRACE_ERR:-?}
TRACE_WARN=$(printf '%s' "$TRACE" | jq -r '(.warnings // []) | length' 2>/dev/null); TRACE_WARN=${TRACE_WARN:-?}
count_level() { "$CLI" log grep '.' --level "$1" --play-session "$SESSION" --context 0 --max-matches 5000 --max-bytes 50000000 --json 2>/dev/null | jq -r '.summary.matchCount // 0'; }
WARN_LINES=$(( $(count_level warn) + $(count_level error) ))

say "session=$SESSION  CHECK ok=$OKS FAIL=$FAILS  STEP ERROR=$ERRS  log trace errors=$TRACE_ERR warnings=$TRACE_WARN  warn/error 行=$WARN_LINES"
[ -n "$DONE_LINE" ] || say "未见 ITF DONE（剧本未跑完）"
ls "$OUT_DIR"/*.png 2>/dev/null | sed 's/^/[run_full] 截图 /'

[ $KEEP = 1 ] || "$CLI" play stop --json >/dev/null 2>&1

if [ -n "$DONE_LINE" ] && [ "$FAILS" = 0 ] && [ "$ERRS" = 0 ] && [ "$WARN_LINES" = 0 ]; then
  say "PASS"; exit 0
else
  say "FAIL"; exit 1
fi
