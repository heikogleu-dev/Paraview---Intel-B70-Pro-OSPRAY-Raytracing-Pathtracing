# ParaView 6.1 with OSPRay GPU Pathtracing on Intel Arc Pro B70

Reproducible build instructions for **ParaView 6.1.0** with hardware
ray‑tracing / pathtracing on **Intel Arc Pro B70** (Big Battlemage,
BMG‑G31, 32 GB ECC GDDR6) on **Ubuntu 26.04 LTS** with **oneAPI 2026.0**.

The official Kitware ParaView 6.1.0 binary release ships only CPU‑only
OSPRay 2.7.1. This repo documents how to replace it with **OSPRay 3.2.0
+ the GPU module (`libospray_module_gpu.so.3.2.0`)** built against
Intel's SYCL/Level‑Zero stack, so that the OSPRay path tracer in
ParaView actually runs on the GPU instead of the CPU.

Tested on:

| Component | Version |
|---|---|
| GPU | Intel Arc Pro **B70** (BMG‑G31), 32 GB ECC GDDR6 |
| CPU | Intel Core Ultra 9 285K (Arrow Lake‑S) |
| OS | Ubuntu **26.04 LTS** (Resolute), kernel 7.0 |
| Intel oneAPI | **2026.0** (DPC++/icx/icpx) |
| Level Zero | 1.28 + `libze-intel-gpu-raytracing` 1.2.3 |
| compute‑runtime | 26.05 |
| OSPRay | **3.2.0** with `BUILD_GPU_SUPPORT=ON` |
| Embree | **4.3.3** (with patch, see below) |
| OpenVKL | 2.0.1 (with patch) |
| OpenImageDenoise | 2.4.0 (JIT only on Battlemage) |
| ParaView | **6.1.0** |
| CMake | 4.2.x |

---

## TL;DR

```bash
git clone https://github.com/heikogleu-dev/Paraview---Intel-B70-Pro-OSPRAY-Raytracing-Pathtracing.git
cd Paraview---Intel-B70-Pro-OSPRAY-Raytracing-Pathtracing
chmod +x scripts/*.sh
./scripts/00-apt-deps.sh        # ~3 min
./scripts/10-build-ospray-gpu.sh # ~30-60 min, ends with libospray_module_gpu.so
./scripts/20-build-paraview.sh   # ~60-180 min, ends with paraview executable
./scripts/30-paraview-gpu-launcher.sh /path/to/your/case.foam
```

---

## Why this is needed

OSPRay GPU rendering is officially "beta" (per the OSPRay README) but
production‑ready in practice. The bottleneck for using it on Battlemage
hardware is that **none of the upstream binaries ship a working stack**:

- The **Intel® Rendering Toolkit Superbuild**'s default config builds
  OSPRay without the GPU module (it passes `BUILD_GPU_SUPPORT` to
  OSPRay's main CMakeLists, where the actual flag is
  `OSPRAY_MODULE_GPU` — they don't translate). It also pins Embree
  **4.4.0**, which broke the SYCL device‑side API that OSPRay 3.2.0
  uses (the `*FromScene` functions became host‑only, replaced by
  `*FromTraversable`).
- **OSPRay's own superbuild** uses the right version pins
  (Embree 4.3.3) and the right flag, but Embree 4.3.3's source uses
  removed SYCL methods (`sycl::sub_group::shuffle*`) that were dropped
  in DPC++ 2026.0.
- **OpenImageDenoise**'s default AOT compilation only targets older
  iGPUs, Alchemist Arc, and Ponte Vecchio data‑center GPUs —
  Battlemage is not on the list, and the AOT compiler segfaults if
  asked to do PVC on a non‑PVC system.
- **CMake 4.0+** removed compatibility with `cmake_minimum_required(VERSION < 3.5)`,
  which several upstream subprojects in the build chain still declare.
- **glibc ≥ 2.43** declares `nan(...)` as a function, which collides
  with rkcommon's `#define nan floatbits(0x7FBFFFFF)` macro when
  `rkcommon/math/math.ih` is included from C++ code (which OpenVKL's
  GPU module does).

The four patches in [`patches/`](patches/) fix exactly these issues.
The build scripts apply them at the right point in the build process.

## What works after this build

- ✅ ParaView 6.1.0 GUI launches with `-DPARAVIEW_ENABLE_RAYTRACING=ON`
- ✅ "OSPRay path tracer" and "OSPRay raycaster" available as render
  backends in the Render View properties panel under
  **Ray Traced Rendering → Back End**
- ✅ Default device is GPU (driven by `OSPRAY_LOAD_MODULES=gpu` +
  `OSPRAY_DEVICE=gpu` env vars set by the launcher script — the GUI
  itself has no CPU/GPU switch)
- ✅ SYCL device 0 (the discrete Arc Pro B70 = `Intel(R) Graphics [0xe223]`)
  is selected at runtime — confirm via:
  ```
  SYCL_UR_TRACE=1 ospTutorial --osp:load-modules=gpu --osp:device=gpu
  ```
- ✅ Path tracing of automotive‑scale CFD scenes (10⁷–10⁸ cells) for
  high‑quality video export
- ✅ OpenImageDenoise (JIT) on the GPU as well

## What does NOT work / is not in this build

- ❌ ANARI plugin (Kitware doesn't ship it in source builds enabled by
  default; it's a separate effort and the Intel ANARI backend would
  itself sit on top of OSPRay anyway, so for Intel hardware the direct
  OSPRay path is more efficient).
- ❌ MPI / cluster rendering — set `BUILD_OSPRAY_MODULE_MPI=ON` and
  install `libopenmpi-dev` if you need it.
- ❌ AOT compilation of OIDN kernels for Battlemage — Intel needs to
  add `bmg-g21,bmg-g31` to the OIDN AOT target list. Until then, JIT
  + persistent JIT cache (which we enable via the launcher script)
  handles the small first‑frame overhead.

## Repository layout

```
.
├── README.md                     ← you are here
├── patches/                      ← four upstream patches, applied by the build scripts
│   ├── 01-rkcommon-math-ih-nan.patch
│   ├── 02-embree-sycl-subgroup-api.patch
│   ├── 03-oidn-disable-aot-for-non-supported-gpu.patch
│   └── 04-cmake-policy-version-minimum.patch
├── scripts/
│   ├── 00-apt-deps.sh            ← apt one‑liner for build deps (Qt6, Python3, GLFW, …)
│   ├── 10-build-ospray-gpu.sh    ← OSPRay 3.2.0 + GPU module (uses OSPRay's own superbuild)
│   ├── 20-build-paraview.sh      ← ParaView 6.1.0 from source against the new OSPRay
│   └── 30-paraview-gpu-launcher.sh ← runtime wrapper (LD_LIBRARY_PATH + ONEAPI_DEVICE_SELECTOR)
└── docs/
    ├── verification.md           ← how to confirm the GPU is actually being used
    ├── rendering-tips.md         ← OSPRay material gotchas, perf settings, known runtime quirks
    └── troubleshooting.md        ← every error we hit, with logs & fixes
```

## Prerequisites (not installed by `00-apt-deps.sh`)

- **Intel oneAPI Base Toolkit 2025.3+** (we used 2026.0): provides
  `icx` / `icpx` (DPC++) and the SYCL runtime.
  Install via Intel's apt repo:
  https://www.intel.com/content/www/us/en/docs/oneapi/installation-guide-linux/2024-2/apt-005.html
- **Intel Level Zero + GPU runtime + ray‑tracing extension**:
  ```
  sudo apt install libze-dev libze-intel-gpu1 libze-intel-gpu-dev libze-intel-gpu-raytracing intel-opencl-icd
  ```
- A working `clinfo` and `sycl-ls` should report your B70 as e.g.
  `[level_zero:gpu] Intel(R) Graphics [0xe223]`. If they don't,
  the build will succeed but rendering will fall back to CPU silently.

## Verification

After install, run:

```bash
SYCL_UR_TRACE=1 ONEAPI_DEVICE_SELECTOR=level_zero:0 \
  ~/opt/ospray-gpu/ospray/bin/ospTutorial \
    --osp:load-modules=gpu --osp:device=gpu 2>&1 | grep "device:"
```

Expected output:

```
SYCL_UR_TRACE:   device: Intel(R) Graphics [0xe223]
```

`0xe223` is the PCI device ID of the BMG‑G31 silicon used in the Arc
Pro B70 (and B65). If you see a different device ID, you're rendering
on a different GPU than you think you are. See
[docs/verification.md](docs/verification.md).

## License & contributions

The patches in this repo are derivative changes to upstream projects
released under Apache 2.0 (rkcommon, Embree, OpenVKL, OIDN, OSPRay) —
they are licensed under the same terms.

If you reproduce this build on different hardware (Arc Pro B50/B60,
older Alchemist Arc, etc.) and any of the patches need adjustment,
please open an issue or PR.

## Acknowledgements

Built and documented while debugging the build interactively with
[Claude Code](https://claude.com/claude-code) (Claude Opus 4.7).
