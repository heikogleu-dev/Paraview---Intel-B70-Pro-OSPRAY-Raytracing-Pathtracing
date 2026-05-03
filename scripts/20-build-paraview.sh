#!/usr/bin/env bash
# Build ParaView 6.1.0 from source against the OSPRay-GPU stack built by
# 10-build-ospray-gpu.sh. Result: $PV_PREFIX/bin/paraview can use the
# GPU pathtracer/raytracer on Intel Arc Pro B70 via "OSPRay path tracer"
# rendering backend.
set -euo pipefail

OSP_PREFIX="${OSP_PREFIX:-$HOME/opt/ospray-gpu}"
PV_PREFIX="${PV_PREFIX:-$HOME/opt/paraview-gpu}"
PV_SRC="${PV_SRC:-$HOME/build/paraview/src}"
PV_BUILD="${PV_BUILD:-$HOME/build/paraview/build}"
JOBS="${JOBS:-$(nproc)}"

# 1. Get ParaView source (with submodules: VTK, IceT, QtTesting, VisItBridge)
if [[ ! -d "$PV_SRC" ]]; then
  git clone --recurse-submodules --shallow-submodules --depth=1 \
    --branch v6.1.0 https://gitlab.kitware.com/paraview/paraview.git "$PV_SRC"
fi

# 2. Configure (system Qt6, system Python3, our OSPRay)
mkdir -p "$PV_BUILD"
cd "$PV_BUILD"
cmake -G Ninja "$PV_SRC" \
  -DCMAKE_INSTALL_PREFIX="$PV_PREFIX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DPARAVIEW_USE_QT=ON \
  -DPARAVIEW_USE_PYTHON=ON \
  -DPARAVIEW_ENABLE_RAYTRACING=ON \
  -DPARAVIEW_BUILD_SHARED_LIBS=ON \
  -DCMAKE_PREFIX_PATH="$OSP_PREFIX/ospray;$OSP_PREFIX/embree;$OSP_PREFIX/openvkl;$OSP_PREFIX/oidn;$OSP_PREFIX/rkcommon;$OSP_PREFIX/tbb;$OSP_PREFIX/openpgl" \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5

# 3. Build (this is the long one, ~30-90 min on a 24-thread CPU)
ninja -j "$JOBS"

# 4. Install
ninja install

echo
echo "=== ParaView GPU build complete ==="
echo "Run via the wrapper script:"
echo "  ./scripts/30-paraview-gpu-launcher.sh"
