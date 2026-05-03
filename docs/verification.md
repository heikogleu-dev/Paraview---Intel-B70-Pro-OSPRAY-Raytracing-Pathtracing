# Verifying the B70 is actually rendering

ParaView's rendering backend menu doesn't tell you which GPU is doing
the work — it just says "OSPRay path tracer". If the runtime
configuration is wrong, OSPRay silently falls back to CPU and you'll
wonder why your GPU fans aren't spinning up.

This doc lists three independent ways to confirm GPU usage.

## 1. SYCL device selection trace

Easiest, no extra tools. The DPC++ runtime can print every SYCL device
selection event:

```bash
SYCL_UR_TRACE=1 ONEAPI_DEVICE_SELECTOR=level_zero:0 \
  ~/opt/ospray-gpu/ospray/bin/ospTutorial \
    --osp:load-modules=gpu --osp:device=gpu 2>&1 | grep -E "device:|platform:"
```

Expected, on a B70 system:

```
SYCL_UR_TRACE:   platform: Intel(R) oneAPI Unified Runtime over Level-Zero V2
SYCL_UR_TRACE:   device: Intel(R) Graphics [0xe223]
```

PCI device IDs:

| Chip | PCI ID | Used in |
|---|---|---|
| BMG‑G21 | `0xe20b`, `0xe20c` | Arc B570, B580, Pro B50/B60 |
| BMG‑G31 | `0xe222`, `0xe223` | Arc Pro B65, **B70** |

If your trace shows a `0xa7…` ID (Arrow Lake iGPU) or no GPU device at
all, the runtime selected the wrong device — set `ONEAPI_DEVICE_SELECTOR`
explicitly. The launcher script
[`30-paraview-gpu-launcher.sh`](../scripts/30-paraview-gpu-launcher.sh)
does this for you.

## 2. `intel_gpu_top` while rendering

Open a second terminal and run:

```bash
sudo intel_gpu_top -d pci:card=1     # card=0 is the iGPU, card=1 is the discrete GPU
```

Trigger a render in ParaView (rotate the camera, change a colormap).
You should see the **Render/3D** engine spike to >50 %. If it stays at
0 %, OSPRay is on the CPU.

`intel_gpu_top` is in the `intel-gpu-tools` apt package.

## 3. CPU vs GPU timing comparison

Render the same scene twice with `--osp:device=cpu` and `--osp:device=gpu`,
compare frame times. On the B70 with a 1 M‑triangle automotive mesh the
ratio should be 5–15× in favor of the GPU.

```bash
ROOT=~/opt/ospray-gpu
LIBS="$ROOT/ospray/lib:$ROOT/embree/lib:$ROOT/openvkl/lib:$ROOT/oidn/lib:$ROOT/rkcommon/lib:$ROOT/tbb/lib:$ROOT/openpgl/lib:/opt/intel/oneapi/compiler/2026.0/lib"

LD_LIBRARY_PATH=$LIBS $ROOT/ospray/bin/ospBenchmark --benchmark_filter=PathTracer.* \
  --osp:device=cpu --osp:load-modules=cpu

LD_LIBRARY_PATH=$LIBS $ROOT/ospray/bin/ospBenchmark --benchmark_filter=PathTracer.* \
  --osp:device=gpu --osp:load-modules=gpu
```

## 4. ParaView itself

ParaView 6.1's GUI has **no CPU/GPU switch**. The choice is driven by
two OSPRay environment variables that the launcher script sets before
calling the `paraview` binary:

```
OSPRAY_LOAD_MODULES=gpu
OSPRAY_DEVICE=gpu
```

ParaView's RTWrapper calls `ospInit(nullptr, nullptr)`, which reads
those env vars and creates a GPU OSPRay device. The GUI controls only
the "Enable Ray Tracing" toggle and the "Back End" choice (raycaster vs
path tracer):

- Click on the Render View, then in the **Properties panel** (lower
  left, NOT Tools → Settings) scroll to **Ray Traced Rendering**.
- Tick **Enable Ray Tracing**.
- **Back End** dropdown → choose `OSPRay raycaster` or `OSPRay pathtracer`.

To verify the GPU device was actually picked, use methods 1–3 above —
the GUI itself doesn't tell you. Easiest cross‑check: rotate the camera
with `intel_gpu_top` open in another terminal and watch the Render/3D
engine spike.
