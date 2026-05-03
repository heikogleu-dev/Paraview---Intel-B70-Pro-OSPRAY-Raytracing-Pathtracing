# Rendering tips & known quirks

Practical settings and gotchas observed when using the OSPRay GPU
backend in ParaView 6.1 on Intel Arc Pro B70. Updated as we hit them.

## Workflow: interactive vs final-quality

The OSPRay path tracer is gorgeous but slow. Typical setup for CFD
animation export:

| Task | Back End | Samples/pixel | Denoiser |
|---|---|---|---|
| Interactive scene setup, camera placement, colormap tuning | **OSPRay raycaster** | 1 (default) | off |
| Single high-quality screenshot | OSPRay pathtracer | 64–256 | on |
| Animation/video frames | OSPRay pathtracer | 16–64 per frame | **on** (denoiser saves orders of magnitude) |

The raycaster is only ~2× slower than the GL backend on the B70 and gives
you real shadows and ambient occlusion. Use it for everything except the
final beauty render.

## "My geometry turned solid green / solid grey when I enabled Ray Tracing"

OSPRay needs an explicit material on each surface. If none is set,
ParaView falls back to a default material that ignores the color map.

Checklist:

1. **Pipeline Browser** → click your filter (e.g. "Car")
2. **Properties Panel** → scroll to **Coloring** → confirm the array
   you wanted (e.g. `wallShearStress` / `Magnitude`) is selected.
   Switching to OSPRay sometimes resets it to "Solid Color".
3. **Properties Panel** → scroll to **Ray Tracing** → **Material**
   dropdown → set to **`None`**. "None" means "use the colormap as
   pseudo‑material", which is what you want for false‑colour CFD vis.
4. If you DO want a physical look (e.g. matte clay car body to highlight
   only the surface‑pressure colormap on top): set Material to
   `OBJMaterial` or one of the presets, and check the related sub‑properties.

## "Switching to OSPRay locks ParaView for 30+ seconds"

First-time JIT compile of the SYCL kernels for your GPU. The launcher
script ([`scripts/30-paraview-gpu-launcher.sh`](../scripts/30-paraview-gpu-launcher.sh))
sets `OIDN_DEVICE_SYCL_JIT_CACHE` so subsequent launches reuse cached
binaries from `~/.cache/oidn-sycl-jit/`. Note that OSPRay itself also
caches in `~/.cache/intel/cache_dir/` (managed by the SYCL runtime).

Workaround for the first launch:

- Wait it out — once.
- Or click "Wait" in the "ParaView nicht antwortend" dialog instead of
  "Force quit".
- Future launches with the same scene topology should be near-instant.

## "GPU usage spikes to 100% but performance still feels slow"

Several possible causes:

- **Samples per pixel too high** for interactive use → drop to 1
  (Properties → Ray Tracing → Samples per Pixel)
- **Path tracer when raycaster would do** → switch Back End to
  raycaster for scene navigation
- **PCIe bandwidth limited**: the screenshot in our case showed
  `PCIe 1.0 ×1` (!). On a desktop board the slot should advertise
  PCIe 5.0 ×16. Check via `lspci -vvs 04:00.0 | grep -E "LnkSta|LnkCap"`.
  If it links at lower speed than the slot advertises, reseat the card
  / check BIOS PCIe slot config.
- **VRAM swap**: if your scene needs more than 32 GB the GPU has to
  page over PCIe — every interaction stalls. Check in Mission Center
  / nvtop how close you are to the 32 GB ceiling.

## Verifying GPU is actually used

See [`verification.md`](verification.md). Quickest visual check is the
**Mission Center** app (apt: `mission-center`) — its GPU panel shows
real‑time utilization with the device name "Battlemage G31 [Intel
Graphics]" or similar.

`nvtop` works too (apt: `nvtop`). It correctly reads the `xe` driver
where the older `intel_gpu_top` (i915 PMU only) does not.

## Known issues currently being investigated

- **Silent crash of `ospInit` when GPU device is selected** — observed
  intermittently outside of ParaView (`ospTutorial --osp:device=gpu`
  exits 3 with no output). When it occurs, both env‑var and
  command‑line device selection are affected; CPU device works fine.
  Suspected GPU/driver state issue — usually clears after kernel
  module reload (`sudo modprobe -r xe && sudo modprobe xe`) or a
  reboot. If you can reproduce reliably, please open an issue.
