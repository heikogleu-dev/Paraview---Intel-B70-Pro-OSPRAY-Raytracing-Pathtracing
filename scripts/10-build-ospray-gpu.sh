#!/usr/bin/env bash
# Build OSPRay 3.2.0 with GPU (SYCL) support against Intel Arc Pro B70 (BMG-G31)
# on Ubuntu 26.04 + oneAPI 2026.0 + DPC++.
#
# Output: $PREFIX with libospray.so.3.2.0 + libospray_module_gpu.so.3.2.0
set -euo pipefail

PREFIX="${PREFIX:-$HOME/opt/ospray-gpu}"
SRCDIR="${SRCDIR:-$HOME/build/ospray}"
BUILDDIR="${BUILDDIR:-$HOME/build/ospray-superbuild/build}"
PATCHES="${PATCHES:-$(dirname "$(readlink -f "$0")")/../patches}"
JOBS="${JOBS:-$(nproc)}"

ICX=/opt/intel/oneapi/compiler/2026.0/bin/icx
ICPX=/opt/intel/oneapi/compiler/2026.0/bin/icpx

[[ -x "$ICX" && -x "$ICPX" ]] || { echo "oneAPI 2026.0 compiler not found" >&2; exit 1; }

# 1. Get OSPRay source (only its superbuild scripts/ tree, but easier to clone the whole thing)
if [[ ! -d "$SRCDIR" ]]; then
  git clone --depth=1 --branch v3.2.0 https://github.com/RenderKit/ospray.git "$SRCDIR"
fi

# 2. Apply patches 03 + 04 to the OSPRay superbuild scripts BEFORE configuring
( cd "$SRCDIR" && git apply --check "$PATCHES/03-oidn-disable-aot-for-non-supported-gpu.patch" 2>/dev/null \
  && git apply "$PATCHES/03-oidn-disable-aot-for-non-supported-gpu.patch" || true )
# Patch 04 must be applied to several dep_*.cmake + build_ospray.cmake.
# Sed-based application (works on installed CMake 4.x, doesn't need git apply -p logic).
for f in "$SRCDIR"/scripts/superbuild/dependencies/dep_{embree,oidn,openvkl,openpgl,rkcommon}.cmake \
         "$SRCDIR"/scripts/superbuild/build_ospray.cmake ; do
  [[ -f "$f" ]] || continue
  if ! grep -q "CMAKE_POLICY_VERSION_MINIMUM" "$f"; then
    awk '/-DCMAKE_PREFIX_PATH=\$\{CMAKE_PREFIX_PATH\}/ \
         {print; print "      -DCMAKE_POLICY_VERSION_MINIMUM=3.5"; next} {print}' \
         "$f" > "$f.new" && mv "$f.new" "$f"
    echo "patched (policy 3.5): $(basename "$f")"
  fi
done

# 3. Configure superbuild
mkdir -p "$BUILDDIR" "$PREFIX"
cd "$BUILDDIR"
cmake -G Ninja "$SRCDIR/scripts/superbuild" \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_GPU_SUPPORT=ON \
  -DBUILD_EMBREE_FROM_SOURCE=ON \
  -DBUILD_OPENVKL_FROM_SOURCE=ON \
  -DBUILD_OIDN_FROM_SOURCE=ON \
  -DBUILD_GLFW=OFF \
  -DBUILD_OSPRAY_APPS=ON \
  -DBUILD_OSPRAY_MODULE_MPI=OFF \
  -DCMAKE_C_COMPILER="$ICX" \
  -DCMAKE_CXX_COMPILER="$ICPX" \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5

# 4. First ninja run -- will fail at Embree (sub_group::shuffle)
#    and OpenVKL (rkcommon nan macro) -- expected.
ninja -j "$JOBS" || true

# 5. Apply patch 01 to the JUST-INSTALLED rkcommon header
( cd "$PREFIX/rkcommon/include" && \
  git apply --directory=rkcommon/math --unsafe-paths -p2 "$PATCHES/01-rkcommon-math-ih-nan.patch" 2>/dev/null || \
  patch -p2 -d rkcommon/math < "$PATCHES/01-rkcommon-math-ih-nan.patch" )

# 6. Apply patch 02 to Embree source in the build tree
patch -p1 -d "$BUILDDIR/embree/src" < "$PATCHES/02-embree-sycl-subgroup-api.patch" || true

# 7. Force rebuild of the affected stamps and continue
rm -rf "$BUILDDIR/embree/stamp/embree-build" \
       "$BUILDDIR/openvkl/stamp/openvkl-build" \
       "$BUILDDIR/openvkl/build/openvkl/devices/gpu/CMakeFiles/openvkl_module_gpu_device.dir"
ninja -j "$JOBS"

echo
echo "=== OSPRay GPU build complete ==="
echo "Library:  $PREFIX/ospray/lib/libospray_module_gpu.so.3.2.0"
echo "Test:     LD_LIBRARY_PATH=... $PREFIX/ospray/bin/ospTutorial --osp:load-modules=gpu --osp:device=gpu"
