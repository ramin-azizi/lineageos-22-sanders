#!/bin/bash
# Sync the LineageOS 22.2 (Android 15) tree for Moto G5S Plus (sanders, XT1804).
#
# Run detached, the same way as the zenlte build -- a plain background job dies
# to SIGHUP when the parent shell exits:
#   setsid nohup bash setup_sanders.sh >/dev/null 2>&1 </dev/null & disown
#
# Do NOT run this while the zenlte build is compiling: both hit the same
# 5400rpm spindle and the contention is superlinear.
#
# NOTE: no `set -u` -- build/envsetup.sh references an unbound TOP and aborts
# under nounset, which silently yields an rc=127 no-op.

ROOT=/mnt/rom-data/sanders-los22-build
SRC=$ROOT/src
TS=$(date -u +%Y%m%dT%H%M%SZ)
LOG=$ROOT/logs/sync_$TS.log

mkdir -p "$ROOT/logs" "$SRC"
ln -sfn "sync_$TS.log" "$ROOT/logs/sync_latest.log"
trap '' HUP

# repo lives in ~/.local/bin on this machine; git-lfs in ~/bin. Both are needed --
# without git-lfs on PATH, repo sync silently writes LFS pointer stubs instead of
# real prebuilts (that is what failed the zenlte build at 51%).
export PATH=~/bin:~/.local/bin:$PATH

{
  echo "=== sanders sync start $(date -u +%FT%TZ) ==="
  cd "$SRC" || exit 1

  # --git-lfs is required on modern LineageOS branches.
  repo init -u https://github.com/LineageOS/android.git -b lineage-22.2 \
            --git-lfs --no-clone-bundle

  mkdir -p "$SRC/.repo/local_manifests"
  cp "$ROOT/local_manifest.xml" "$SRC/.repo/local_manifests/sanders.xml"

  # -j4: this storage is slow; higher concurrency thrashes rather than helps.
  repo sync -c -j4 --force-sync --no-clone-bundle --no-tags
  rc=$?
  echo "=== sanders sync end $(date -u +%FT%TZ) rc=$rc ==="
} > "$LOG" 2>&1
