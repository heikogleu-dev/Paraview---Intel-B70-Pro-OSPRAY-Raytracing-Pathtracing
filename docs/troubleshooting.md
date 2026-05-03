# Troubleshooting / Errors we hit

A catalog of every error encountered while bringing up this stack on
Ubuntu 26.04 + DPC++ 2026.0 + Arc Pro B70, what causes them, and how
they are fixed (most fixes are in [`../patches/`](../patches/)).

---

## 1. RenderKit superbuild builds OSPRay *without* GPU module

**Symptom:** Build succeeds end‑to‑end, but
`<prefix>/lib/libospray_module_gpu.so` is missing. `CMakeCache.txt` in
the OSPRay build dir shows:

```
BUILD_GPU_SUPPORT:UNINITIALIZED=ON
OSPRAY_MODULE_GPU:BOOL=OFF
```

**Cause:** RenderKit's superbuild forwards `-DBUILD_GPU_SUPPORT=ON` to
OSPRay's main CMakeLists. That flag is only recognized by OSPRay's
*own* superbuild script (`scripts/superbuild/`); the main build
expects `OSPRAY_MODULE_GPU=ON`.

**Fix:** Use OSPRay's own superbuild instead of RenderKit's. See
[`../scripts/10-build-ospray-gpu.sh`](../scripts/10-build-ospray-gpu.sh).

---

## 2. RenderKit superbuild + Embree 4.4 → OSPRay GPU kernels fail to compile

**Symptom:** even with `OSPRAY_MODULE_GPU=ON`, OSPRay's GPU kernel
compilation fails with:

```
error: use of undeclared identifier 'rtcIntersect1'
error: use of undeclared identifier 'rtcGetGeometryTransformFromScene'
```

inside files like `modules/cpu/common/World.ispc.o`,
`modules/cpu/camera/PerspectiveCamera.ispc.o`.

**Cause:** Embree 4.4 made the host `*FromScene` functions unavailable
on the SYCL device side (`#if !defined(__SYCL_DEVICE_ONLY__)` guard);
they were replaced by `*FromTraversable` variants. OSPRay 3.2.0
predates this change and still calls the old names.

**Fix:** Use Embree **4.3.3** (the version OSPRay 3.2.0 pins via its
own superbuild) — combined with patch
[`02-embree-sycl-subgroup-api.patch`](../patches/02-embree-sycl-subgroup-api.patch)
to build that version against current DPC++.

---

## 3. Embree 4.3.3 fails to compile against DPC++ 2026.0

**Symptom:**
```
error: no member named 'shuffle' in 'sycl::sub_group'
error: no member named 'shuffle_down' in 'sycl::sub_group'
error: no member named 'shuffle_up' in 'sycl::sub_group'
```

in `common/sys/sycl.h`. Affects most files that include `sycl.h`
(many of them — error count goes into the hundreds).

**Cause:** SYCL 2020 final removed the `sycl::sub_group` member
versions of these functions in favor of free functions in
`<sycl/group_algorithm.hpp>`.

**Fix:** Patch [`02-embree-sycl-subgroup-api.patch`](../patches/02-embree-sycl-subgroup-api.patch).

| Old member | New free function |
|---|---|
| `g.shuffle(x, id)` | `sycl::select_from_group(g, x, id)` |
| `g.shuffle_down(x, d)` | `sycl::shift_group_left(g, x, d)` |
| `g.shuffle_up(x, d)` | `sycl::shift_group_right(g, x, d)` |

---

## 4. OpenImageDenoise SYCL build segfaults

**Symptom:**
```
[N/M] Building CXX object devices/sycl/CMakeFiles/.../sycl_conv_xehpc.cpp.o
llvm-foreach: Segmentation fault (core dumped)
icpx: error: gen compiler command failed with exit code 254
```

**Cause:** OIDN's default `OIDN_DEVICE_SYCL_AOT=ON` triggers
ahead‑of‑time compilation for a hard‑coded list of GPU targets
including Ponte Vecchio (`pvc-sdv,pvc`). The AOT backend crashes when
asked to compile for a target the system can't validate against.
Battlemage is not in the AOT list at all.

**Fix:** Patch
[`03-oidn-disable-aot-for-non-supported-gpu.patch`](../patches/03-oidn-disable-aot-for-non-supported-gpu.patch)
sets `OIDN_DEVICE_SYCL_AOT=OFF`. JIT compilation works on every Intel
GPU the runtime can see, with the JIT cache (still enabled via
`OIDN_DEVICE_SYCL_JIT_CACHE=ON`) eliminating the per‑run startup
overhead after the first launch.

---

## 5. CMake 4.x rejects subproject `cmake_minimum_required(VERSION < 3.5)`

**Symptom:**
```
CMake Error at CMakeLists.txt:6 (cmake_minimum_required):
  Compatibility with CMake < 3.5 has been removed from CMake.
  Or, add -DCMAKE_POLICY_VERSION_MINIMUM=3.5 to try configuring anyway.
```

Hits OpenVKL, OpenPGL, glfw, and others when built as ExternalProjects
under CMake 4.0+.

**Cause:** CMake 4.0 removed the compatibility shim. The
`-D` flag works, but ExternalProject doesn't propagate it
automatically — each subproject must receive it in its `CMAKE_ARGS`.

**Fix:** Patch
[`04-cmake-policy-version-minimum.patch`](../patches/04-cmake-policy-version-minimum.patch).
The build script applies it via `awk` to every dep CMake file.

---

## 6. OpenVKL GPU module: `floatbits` redefinition errors against glibc 2.43

**Symptom:**
```
error: redefinition of 'floatbits' as different kind of symbol
error: pasting formed ')f', an invalid preprocessing token
error: redeclaration of '__floatbits' with a different type
```

at `/usr/include/x86_64-linux-gnu/bits/mathcalls.h:257`, while building
`openvkl_module_gpu_device.dir/api/DeviceAPI.cpp.o`.

**Cause:** rkcommon's `math.ih` defines `nan` as a preprocessor macro:
```c
#define nan floatbits(0x7FBFFFFF)
```
This file is included into C++ code (e.g. by OpenVKL's GPU device).
glibc ≥ 2.43 declares `nan(...)` as a function via `__MATHCALL`; the
preprocessor expansion of `nan` then mangles the declaration with
`floatbits`, producing the cascade of errors above.

**Fix:** Patch
[`01-rkcommon-math-ih-nan.patch`](../patches/01-rkcommon-math-ih-nan.patch)
guards the `nan` macro under `#ifdef ISPC`. The `nan` macro is not
used in C++ context (only `inf`, `pos_inf`, `neg_inf` are referenced
from C++ code in OpenVKL).

---

## 7. ParaView CMake: missing `xmlpatterns` / `xsltproc`

**Symptom:**
```
CMake Error at CMake/ParaViewClient.cmake:609 (message):
  Cannot find the `xmlpatterns` or `xsltproc` executables.
```

**Fix:** `sudo apt install xsltproc docbook-xsl` (already in
[`../scripts/00-apt-deps.sh`](../scripts/00-apt-deps.sh)).

## 8. ParaView CMake: missing `Qt6Core5Compat`

**Symptom:**
```
Failed to find required Qt component "Core5Compat"
Could not find the Qt6 external dependency
```

**Fix:** `sudo apt install qt6-5compat-dev`.

## 9. OSPRay apps fail at configure: missing GTest, Google Benchmark, glfw3

**Symptom:** Configure stops with `Could not find GTest` /
`Could not find benchmark` / `Could not find glfw3`.

**Cause:** OSPRay's example/test apps need these. They're optional but
ON by default. Quickest fix is to install them rather than turning
the apps off — they're useful for verification.

**Fix:** `sudo apt install libgtest-dev libgmock-dev libbenchmark-dev libglfw3-dev`.

---

## How to confirm a runtime fall‑back to CPU

If after a successful build, ParaView "feels slow" with the OSPRay path
tracer enabled, it may be silently using the CPU device. See
[`verification.md`](verification.md) for confirmation steps.
