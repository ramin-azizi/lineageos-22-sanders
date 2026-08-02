#!/bin/bash
# Launch the sanders LineageOS 22.2 (Android 15) build fully detached.
#
#   setsid nohup bash start_build.sh >/dev/null 2>&1 </dev/null & disown
#
# A plain `&` background job dies to SIGHUP when the parent shell exits -- that
# killed the zenlte build 80 seconds in on 2026-08-01, silently, with no error
# in the log.
#
# NOTE: no `set -u` -- build/envsetup.sh references an unbound TOP and aborts
# under nounset, silently producing an rc=127 no-op build that looks like it ran.

ROOT=/mnt/rom-data/sanders-los22-build
SRC=$ROOT/src
TS=$(date -u +%Y%m%dT%H%M%SZ)
LOG=$ROOT/logs/build_$TS.log

mkdir -p "$ROOT/logs"
ln -sfn "build_$TS.log" "$ROOT/logs/build_latest.log"
trap '' HUP

export PATH=~/bin:~/.local/bin:$PATH
# NO ccache: it is not installed on this machine. Setting USE_CCACHE=1 with
# CCACHE_EXEC pointing at a non-existent binary makes soong prefix every compile
# with it, and every single one dies with
#   /bin/sh: 1: /usr/bin/ccache: not found
# That killed the first sanders build attempt at 0% (12 FAILED targets).
# If ccache is installed later, re-enable with USE_CCACHE=1 + CCACHE_EXEC set to
# its real path, and verify with `which ccache` FIRST.

cd "$SRC" || exit 1

{
  echo "=== sanders build start $(date -u +%FT%TZ) (detached, -j16) ==="

  # Re-warm repo's mtime-keyed cache of ~/.gitconfig BEFORE the build starts.
  # The build runs `repo manifest` inside a sandbox that mounts / read-only; if
  # the cache is stale there, it dies with
  #   OSError: [Errno 30] Read-only file system: '~/.repo_.gitconfig.json'
  # This must happen out here, outside the sandbox. It bit the zenlte build.
  echo "--- warming repo config cache ---"
  python3 .repo/repo/repo manifest -o - -r >/dev/null 2>&1
  echo "--- cache warmed (rc=$?) ---"


  source build/envsetup.sh
  breakfast sanders          # -> lunch lineage_sanders-bp1a-userdebug
  mka -j16 bacon
  rc=$?
  echo "=== sanders build end $(date -u +%FT%TZ) rc=$rc ==="
} > "$LOG" 2>&1
