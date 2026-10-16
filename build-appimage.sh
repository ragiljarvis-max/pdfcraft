#!/bin/bash
# Build PdfCraft (desktop + cli) dan AppImage di dalam ubuntu:20.04 (glibc 2.31).
# Dijalankan DI DALAM container; jalankan dari host dengan perintah podman di
# docs/ubuntu-20.04-glibc-2.31.md (script ini di-mount ke /build-appimage.sh).
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive
export HOME=/root

echo "=== glibc ==="
/lib/x86_64-linux-gnu/libc.so.6 --version | head -1

echo "=== install build deps ==="
apt-get update -qq
# Deps egui/winit/rfd (dari .github/workflows/ci.yml) + appimagetool/zsync/squashfs.
apt-get install -y --no-install-recommends \
  build-essential pkg-config libxkbcommon-dev libwayland-dev libx11-dev \
  libxcursor-dev libxrandr-dev libxi-dev libgl1-mesa-dev libgtk-3-dev \
  libfontconfig1-dev libfreetype-dev curl ca-certificates \
  git file zsync squashfs-tools

echo "=== install rust ==="
if [ ! -x /root/.cargo/bin/cargo ]; then
  curl -fsSL https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal
fi
# shellcheck disable=SC1091
source /root/.cargo/env
rustc --version
cargo --version

echo "=== build (release, locked) ==="
cd /src
export CARGO_TARGET_DIR=/target
cargo build --release --locked -p pdfcraft -p pdfcraft-cli

echo "=== check glibc version pada binary hasil build ==="
for b in pdfcraft pdfcraft-cli; do
  echo "--- $b"
  objdump -p "/target/release/$b" | grep -A20 'required from libc' || true
done

echo "=== package: appimage (juga unduh model OCR, butuh jaringan) ==="
export DIST=/dist
./packaging/linux/package.sh --skip-build --formats "appimage"

echo "=== hasil ==="
ls -lh /dist/
echo "=== DONE ==="
