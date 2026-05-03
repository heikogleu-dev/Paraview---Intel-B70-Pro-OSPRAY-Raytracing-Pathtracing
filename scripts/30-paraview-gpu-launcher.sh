#!/usr/bin/env bash
# Launcher: starts ParaView with all OSPRay+SYCL runtime libraries on
# LD_LIBRARY_PATH and pins SYCL device selection to the discrete Intel
# GPU (level_zero:0 on a system with iGPU + Arc Pro B70).
#
# Forward all arguments to paraview, e.g.:
#   ./30-paraview-gpu-launcher.sh /path/to/state.pvsm
set -euo pipefail

OSP_PREFIX="${OSP_PREFIX:-$HOME/opt/ospray-gpu}"
PV_PREFIX="${PV_PREFIX:-$HOME/opt/paraview-gpu}"
ONEAPI=/opt/intel/oneapi/compiler/2026.0

export LD_LIBRARY_PATH="\
$OSP_PREFIX/ospray/lib:\
$OSP_PREFIX/embree/lib:\
$OSP_PREFIX/openvkl/lib:\
$OSP_PREFIX/oidn/lib:\
$OSP_PREFIX/rkcommon/lib:\
$OSP_PREFIX/tbb/lib:\
$OSP_PREFIX/openpgl/lib:\
$ONEAPI/lib:\
$ONEAPI/lib/clang/22/lib/x86_64-unknown-linux-gnu:\
${LD_LIBRARY_PATH:-}"

# Pin to the discrete Arc Pro B70 (drop this line to use whatever
# SYCL picks by default).
export ONEAPI_DEVICE_SELECTOR="level_zero:0"

# JIT cache for OIDN (no AOT for Battlemage) -- keeps first-frame delay low
# after the initial run.
export OIDN_DEVICE_SYCL_JIT_CACHE="${HOME}/.cache/oidn-sycl-jit"
mkdir -p "$OIDN_DEVICE_SYCL_JIT_CACHE"

exec "$PV_PREFIX/bin/paraview" "$@"
