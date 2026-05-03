#!/usr/bin/env bash
# System dependencies for building OSPRay (with GPU module) + ParaView 6.1
# from source on Ubuntu 26.04 LTS (Resolute).
#
# oneAPI 2026.0 (icx/icpx, Level Zero, compute-runtime, libze-intel-gpu-raytracing)
# is assumed to be already installed via Intel's apt repository.
set -euo pipefail

sudo apt-get update
sudo apt-get install -y \
  ninja-build \
  git \
  libxrandr-dev libxinerama-dev libxcursor-dev libxi-dev libxmu-dev libxkbcommon-dev \
  libgl1-mesa-dev libglu1-mesa-dev libglew-dev mesa-common-dev \
  libglfw3-dev \
  libtbb-dev libpng-dev libjpeg-dev libtiff-dev libhdf5-dev \
  libbenchmark-dev libgtest-dev libgmock-dev \
  qt6-base-dev qt6-base-private-dev qt6-tools-dev qt6-tools-dev-tools \
  qt6-svg-dev qt6-multimedia-dev qt6-5compat-dev qt6-wayland-dev \
  libqt6opengl6-dev \
  python3-dev python3-numpy \
  xsltproc docbook-xsl
