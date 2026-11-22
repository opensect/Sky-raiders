#!/bin/bash
GODOT=/home/hatch/workspace/godot47/Godot_v4.7.2-stable_linux.x86_64
cd /home/hatch/workspace/mini-militia-lan
for m in $(seq 0 4); do
  out=$(timeout 120 xvfb-run -a "$GODOT" --path . -- --auto-host --collision-test --map=$m 2>&1)
  echo "collision map $m: $(echo "$out" | grep -E 'COLLISIONTEST DONE' | tail -1) errors=$(echo "$out" | grep -ciE 'SCRIPT ERROR')"
done
run() { local label="$1"; shift; local out; out=$(timeout 180 xvfb-run -a "$GODOT" --path . -- "$@" 2>&1); echo "[$label] errors=$(echo "$out" | grep -ciE 'SCRIPT ERROR') :: $(echo "$out" | grep -E 'DONE:' | tail -1)"; echo "$out" > "/home/hatch/workspace/mini-militia-lan/log4_${label// /_}.txt"; }
run "joystick" --auto-host --joystick-test
run "fire" --auto-host --fire-test
run "scale" --auto-host --scale-test
run "physics-map0" --auto-host --physics-test --map=0
run "physics-map1" --auto-host --physics-test --map=1
run "physics-map2" --auto-host --physics-test --map=2
run "physics-map3" --auto-host --physics-test --map=3
run "physics-map4" --auto-host --physics-test --map=4
run "features" --auto-host --features-test
run "features-skyfall" --auto-host --features-test --map=4
run "multiplayer" --auto-host --net-test
run "menu-net" --auto-host --menu-net-test
run "flow" --auto-host --flow-test
for m in $(seq 0 4); do
  out=$(timeout 120 xvfb-run -a "$GODOT" --path . -- --auto-host --smoke-test --map=$m 2>&1)
  echo "smoke map $m: $(echo "$out" | grep -E 'SMOKE DONE' | tail -1) errors=$(echo "$out" | grep -ciE 'SCRIPT ERROR')"
done
