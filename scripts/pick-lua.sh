#!/usr/bin/env bash
# Locate a Lua 5.4 interpreter: PATH candidates first (verified by version),
# then brew's keg-only lua@5.4.
#
# Sourced by the bash wrappers under tools/acceptance/.
pick_lua() {
  local cand
  for cand in lua5.4 lua-5.4 lua; do
    if command -v "$cand" >/dev/null 2>&1 \
       && "$cand" -e 'assert(_VERSION == "Lua 5.4")' 2>/dev/null; then
      command -v "$cand"
      return 0
    fi
  done
  local keg
  for keg in /opt/homebrew/opt/lua@5.4/bin/lua5.4 /usr/local/opt/lua@5.4/bin/lua5.4; do
    if [ -x "$keg" ]; then
      echo "$keg"
      return 0
    fi
  done
  echo "error: no Lua 5.4 interpreter found (brew install lua@5.4)" >&2
  return 1
}
