#!/usr/bin/env bash
#
# SPDX-License-Identifier: Apache-2.0
#
# Build Evolution X 12.2 (Android 17) for the Xiaomi Redmi 9A (dandelion).
#
# Usage:
#   ./build.sh [options]
#
# Options:
#   -d, --dir DIR        Source directory (default: ./evolution)
#   -j, --jobs N         Parallel build jobs (default: RAM / 2.5 GB, max nproc)
#   -v, --variant VAR    user | userdebug | eng (default: userdebug)
#   -s, --sync-only      Only sync sources, don't build
#   -b, --build-only     Skip sync, only build
#   -c, --clean          Run 'm installclean' before building
#   -h, --help           Show this help
#
# Re-running is safe: sync is incremental and an interrupted build resumes
# where it stopped.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/evolution"
JOBS=""
VARIANT="userdebug"
DO_SYNC=1
DO_BUILD=1
DO_CLEAN=0

EVO_BRANCH="cnb"
DEVICE="dandelion"

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==> WARNING:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m==> ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

usage() { sed -n '5,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--dir)        SRC_DIR="$(realpath -m "$2")"; shift 2 ;;
        -j|--jobs)       JOBS="$2"; shift 2 ;;
        -v|--variant)    VARIANT="$2"; shift 2 ;;
        -s|--sync-only)  DO_BUILD=0; shift ;;
        -b|--build-only) DO_SYNC=0; shift ;;
        -c|--clean)      DO_CLEAN=1; shift ;;
        -h|--help)       usage ;;
        *) die "Unknown option: $1 (see --help)" ;;
    esac
done

[[ "$VARIANT" =~ ^(user|userdebug|eng)$ ]] || die "Invalid variant: $VARIANT"

check_host() {
    log "Checking host requirements"
    local missing=()
    for t in repo git git-lfs python3 ccache zip unzip bc bison flex rsync xxd lz4 zstd make gcc openssl m4; do
        command -v "$t" >/dev/null || missing+=("$t")
    done
    [[ ${#missing[@]} -eq 0 ]] || die "Missing tools: ${missing[*]}"

    local ram_gb swap_gb free_gb
    ram_gb=$(awk '/MemTotal/ {printf "%d", $2/1048576}' /proc/meminfo)
    swap_gb=$(awk '/SwapTotal/ {printf "%d", $2/1048576}' /proc/meminfo)
    mkdir -p "$SRC_DIR"
    free_gb=$(df -BG --output=avail "$SRC_DIR" | tail -1 | tr -dc '0-9')

    if (( ram_gb + swap_gb < 56 )); then
        warn "RAM+swap is ${ram_gb}+${swap_gb} GB; soong analysis may get OOM-killed. 32 GB RAM + 32 GB swap recommended."
    fi
    if [[ ! -d "$SRC_DIR/.repo" ]] && (( free_gb < 300 )); then
        warn "Only ${free_gb} GB free; a full sync + build needs ~300 GB."
    fi

    if [[ -z "$JOBS" ]]; then
        # ~2.5 GB of RAM per job. Swap doesn't count: with more jobs, several
        # 4 GB R8/D8 java processes run at once and get OOM-killed.
        JOBS=$(( ram_gb * 10 / 25 ))
        if (( JOBS > $(nproc) )); then JOBS=$(nproc); fi
        if (( JOBS < 1 )); then JOBS=1; fi
    fi
}

sync_sources() {
    cd "$SRC_DIR"
    if [[ ! -d .repo ]]; then
        log "Initialising Evolution X ($EVO_BRANCH) in $SRC_DIR"
        repo init -u https://github.com/Evolution-X/manifest -b "$EVO_BRANCH" \
            --git-lfs --depth=1 --no-clone-bundle
    fi

    log "Installing local manifest"
    mkdir -p .repo/local_manifests
    cp "$SCRIPT_DIR/manifests/dandelion.xml" .repo/local_manifests/dandelion.xml

    log "Syncing sources (this takes a while the first time)"
    local sync_args=(-c --no-tags --no-clone-bundle --optimized-fetch --force-sync)
    if ! repo sync "${sync_args[@]}" -j8; then
        warn "Sync had failures, retrying with -j2"
        repo sync "${sync_args[@]}" -j2 || die "repo sync failed twice"
    fi
}

# Apply patches/<project path>/*.patch; skips ones already applied, so a
# re-run after a sync (which resets the projects) re-applies cleanly.
apply_patches() {
    local p proj
    while IFS= read -r p; do
        proj=$(dirname "${p#"$SCRIPT_DIR/patches/"}")
        [[ -d "$SRC_DIR/$proj/.git" || -f "$SRC_DIR/$proj/.git" ]] || die "Patch target $proj not found"
        if git -C "$SRC_DIR/$proj" apply --reverse --check "$p" 2>/dev/null; then
            continue
        fi
        log "Applying $(basename "$p") to $proj"
        git -C "$SRC_DIR/$proj" apply "$p" || die "Patch $p does not apply"
    done < <(find "$SCRIPT_DIR/patches" -name '*.patch' | sort)
}

build() {
    cd "$SRC_DIR"
    [[ -f build/envsetup.sh ]] || die "No source tree in $SRC_DIR (run without --build-only first)"

    apply_patches

    export USE_CCACHE=1
    export CCACHE_EXEC="$(command -v ccache)"
    ccache -M 50G >/dev/null
    # Incremental analysis keeps extra state in soong_build's heap
    export SOONG_INCREMENTAL_ANALYSIS=false

    # envsetup.sh must be sourced from bash; nounset breaks it
    set +u
    # shellcheck disable=SC1091
    source build/envsetup.sh
    # shellcheck disable=SC1091
    source vendor/lineage/vars/aosp_target_release
    lunch "lineage_${DEVICE}-${aosp_target_release}-${VARIANT}"
    set -u

    if (( DO_CLEAN )); then
        log "Running installclean"
        m installclean
    fi

    log "Building with -j$JOBS"
    m evolution -j"$JOBS"

    local out="$SRC_DIR/out/target/product/$DEVICE"
    local zip
    zip=$(ls -t "$out"/EvolutionX-*-"$DEVICE"-*.zip 2>/dev/null | head -1)
    [[ -n "$zip" ]] || die "Build finished but no zip found in $out"

    local rel="$SCRIPT_DIR/releases"
    mkdir -p "$rel"
    ln -f "$zip" "$rel/" 2>/dev/null || cp "$zip" "$rel/"
    ln -f "$out/recovery.img" "$rel/" 2>/dev/null || cp "$out/recovery.img" "$rel/"
    (cd "$rel" && sha256sum "$(basename "$zip")" recovery.img > SHA256SUMS)

    log "Done:"
    ls -lh "$rel"
}

check_host
if (( DO_SYNC ));  then sync_sources; fi
if (( DO_BUILD )); then build; fi
exit 0
