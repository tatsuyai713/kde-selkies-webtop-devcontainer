#!/bin/bash
# wsl-resume-watchdog.sh - recover the desktop stream after a Windows sleep
#
# Windows sleep pauses the whole WSL2 VM. This service only reports such a
# pause by default. It was added while chasing a "desktop at ~0.1 FPS"
# problem that turned out NOT to be caused by sleep (the real cause was KWin
# blocking on GL timer queries under Mesa d3d12, fixed in startwm_wayland.sh).
# Restarting svc-selkies after resume (WSL_RESUME_RESTART=true) rebuilds the
# compositor and the Plasma session from scratch - open applications are
# closed - so it stays opt-in for cases where the GPU device really is lost.
#
# Detection: the VM pause stops CLOCK_BOOTTIME (/proc/uptime) but not the wall
# clock, which WSL resyncs on resume. When the wall clock advanced more than
# WSL_RESUME_GAP_SEC beyond the boot clock between two checks, the VM was
# suspended.
#
# Settings (container environment):
#   WSL_RESUME_RESTART=true    restart svc-selkies (and the session) after resume (default false: log only)
#   WSL_RESUME_GAP_SEC=60      minimum pause that counts as a sleep
#   WSL_RESUME_INTERVAL_SEC=5  check interval
set -u
GAP="${WSL_RESUME_GAP_SEC:-60}"
INTERVAL="${WSL_RESUME_INTERVAL_SEC:-5}"
ACTION="${WSL_RESUME_RESTART:-false}"
log() { echo "[wsl-resume] $*"; }

boot_s() { cut -d. -f1 /proc/uptime; }
wall_s() { date +%s; }

log "watching for WSL2 VM suspend/resume (gap > ${GAP}s, restart=${ACTION})"
prev_wall=$(wall_s); prev_boot=$(boot_s)
while true; do
  sleep "${INTERVAL}"
  wall=$(wall_s); boot=$(boot_s)
  paused=$(( (wall - prev_wall) - (boot - prev_boot) ))
  prev_wall=${wall}; prev_boot=${boot}
  [ "${paused}" -gt "${GAP}" ] || continue
  log "resume detected: the VM was paused for about ${paused}s (Windows sleep)"
  if [ "${ACTION,,}" != "true" ]; then
    log "WSL_RESUME_RESTART=${ACTION}: log only (set WSL_RESUME_RESTART=true to rebuild the desktop after resume)"
    continue
  fi
  # Let WSL finish resyncing (clock, dxg, network) before tearing down.
  sleep 5
  log "restarting svc-selkies so pixelflux gets a fresh D3D12 device (the Plasma session restarts with it)"
  s6-svc -r /run/service/svc-selkies
  # Skip the clock jump caused by our own settle time.
  prev_wall=$(wall_s); prev_boot=$(boot_s)
done
