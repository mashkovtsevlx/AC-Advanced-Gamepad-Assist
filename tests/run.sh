#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

runtime="${LUAJIT:-luajit}"
for source in \
    "Advanced Gamepad Assist/extension/lua/joypad-assist/Advanced Gamepad Assist/"*.lua \
    "Advanced Gamepad Assist/apps/lua/Advanced Gamepad Assist Config/"*.lua; do
    "$runtime" -b "$source" /dev/null
done
echo "PASS: all production Lua files compile"

"$runtime" tests/test_clutch.lua
"$runtime" tests/test_airborne.lua
"$runtime" tests/test_rumble.lua
