# Ubuntu 20.04 / glibc 2.31 support (AppImage)

> **Status:** verified on 2026-10-16 · **Fork:** `ragiljarvis-max/pdfcraft` · **Base:** `5fdd820b` (v0.8.0)
> **Scope:** the Linux AppImage (and deb/rpm metadata) must run on Ubuntu 20.04, which ships glibc 2.31.

## Summary

PdfCraft's Linux binaries are built against the build host's glibc. The stock release build runs on
CI's `ubuntu-22.04` (see [releasing.md](releasing.md)) and therefore requires glibc ≥ 2.35, so it
**fails** on Ubuntu 20.04 with `version 'GLIBC_2.32' not found` (and 2.33/2.34/2.35). This fork
builds the Linux release **inside an `ubuntu:20.04` container**, which guarantees the lowest common
glibc (2.31), and packages it as an AppImage with `packaging/linux/package.sh`.

## Verified (2026-10-16)

Environment: podman 5.8.2, image `docker.io/library/ubuntu:20.04`
(`GNU C Library (Ubuntu GLIBC 2.31-0ubuntu9.17)`), Rust 1.99.1 (rustup, `stable`),
build flags: `cargo build --release --locked -p pdfcraft -p pdfcraft-cli`.

| Check | Result |
|---|---|
| `pdfcraft-cli --version` in ubuntu:20.04 | `pdfcraft-cli 0.8.0` ✅ |
| ELF `NEEDED` (desktop + cli) | `libdl.so.2`, `libgcc_s.so.1`, `libpthread.so.0`, `libm.so.6`, `libc.so.6`, `ld-linux-x86-64.so.2` only |
| Highest glibc symbol required | **`GLIBC_2.30`** (≤ 2.31) ✅ |
| OCR models inside the AppImage | `text-detection.rten`, `text-recognition.rten` + licences + `ATTRIBUTION.txt` ✅ |
| AppImage `--appimage-extract` in ubuntu:20.04 | OK ✅ |
| App run in ubuntu:20.04 (Xvfb, 12 s) — default renderer | wgpu refused by llvmpipe → app **falls back to OpenGL by itself**, stayed alive, exit 124 ✅ |
| App run with `WGPU_BACKEND=gl` | stayed alive, exit 124 ✅ |
| App run from the extracted `AppRun` | stayed alive, exit 124 ✅ |
| AppImage executed directly (no `APPIMAGE_EXTRACT_AND_RUN`) | needs `fusermount`; absent in a container — see Limitations |

Artifact produced by the container build:

```
pdfcraft-0.8.0-linux-x86_64.AppImage       (51 MB)
sha256 4b695ccbc57433ea08e1ab18e8da6c6863a5aaa5befb03c44cf57a5979e9786b
pdfcraft-0.8.0-linux-x86_64.AppImage.zsync (176 KB, delta updates)
```

## Repo changes in this fork

- `build-appimage.sh` (new): the script that runs **inside** the container (deps, rustup, build,
  glibc check, `package.sh --formats appimage`). `packaging/linux/` itself is untouched upstream
  code, so the script keeps working across merges.
- `.gitignore`: added `/target-*/` for the container's target directory (`target-linux2004/`).
- `packaging/linux/nfpm.yaml` (cherry-pick friendly):

```diff
 overrides:
   deb:
     depends:
-      - libc6 (>= 2.35)
+      # 2.31 (Ubuntu 20.04): the release binary is built in an ubuntu:20.04 container, so the
+      # package must not demand a newer libc or 20.04 refuses to install it.
+      - libc6 (>= 2.31)
       - libgcc-s1
       - libxkbcommon0
+      # xkbcommon-dl loads it on X11; without it the app panics on minimal Ubuntu 20.04 installs.
+      - libxkbcommon-x11-0
       - libvulkan1 | libegl1
   rpm:
     depends:
-      - libm.so.6(GLIBC_2.35)(64bit)
+      - libm.so.6(GLIBC_2.31)(64bit)
       - libxkbcommon.so.0()(64bit)
+      - libxkbcommon-x11.so.0()(64bit)
```

- `libc6 (>= 2.31)`: the deb must not demand 2.35 or Ubuntu 20.04 refuses to install it.
- `libxkbcommon-x11-0`: found by testing on gridcraft — without it the app panics at start with
  `Library libxkbcommon-x11.so could not be loaded` (Ubuntu 20.04 minimal installs).
- The rpm `libm.so.6(GLIBC_*)` floor follows the same build: binaries built in the 20.04 container
  carry no symbol newer than `GLIBC_2.30`.

## How to build (reproduce)

Build **must** run inside an ubuntu:20.04 container (any container runtime). From the repo root:

```sh
mkdir -p dist target-linux2004
podman run --rm \
  -v "$PWD":/src:ro -v "$PWD"/target-linux2004:/target -v "$PWD"/dist:/dist \
  docker.io/library/ubuntu:20.04 bash /src/build-appimage.sh
```

`build-appimage.sh` then: prints the container's glibc, installs the build deps (the egui/winit/rfd
set from `.github/workflows/ci.yml` plus `zsync`/`squashfs-tools` for appimagetool), installs
rustup `stable`, runs `cargo build --release --locked -p pdfcraft -p pdfcraft-cli`, prints
`objdump -p`'s `required from libc` table for both binaries, and finishes with
`DIST=/dist ./packaging/linux/package.sh --skip-build --formats "appimage"`.

Requirements: network (crates.io + git deps, the OCR models that `package.sh` stages through
`cargo xtask models`, and the appimagetool download) and writable `target-linux2004/` and `dist/`.
`zsyncmake` is optional (writes the `.zsync`); `package.sh` runs `appimagetool` with
`APPIMAGE_EXTRACT_AND_RUN=1`, so no FUSE is needed inside the container. The source tree is mounted
read-only; everything the build writes goes to `CARGO_TARGET_DIR=/target`.

The first build downloads and compiles the whole workspace (~3 GB of `target-linux2004/`, ~16 min
on this machine, measured end to end: apt + rustup + build + package); later runs reuse the cache.

Sanity check before shipping any Linux build:

```sh
objdump -p <binary> | grep -A20 'required from libc'   # highest GLIBC_x.y must be <= 2.31
```

## Testing on Ubuntu 20.04

```sh
apt-get install -y xvfb libxkbcommon0 libxkbcommon-x11-0 libgl1 libegl1 libgl1-mesa-dri \
  libvulkan1 mesa-vulkan-drivers libwayland-client0 libx11-6 libx11-xcb1 \
  libxcursor1 libxi6 libxrandr2 libgtk-3-0
./pdfcraft-0.8.0-linux-x86_64.AppImage --appimage-extract        # no FUSE needed
squashfs-root/usr/bin/pdfcraft-cli --version                     # pdfcraft-cli 0.8.0
Xvfb :99 -screen 0 1280x800x24 &
DISPLAY=:99 timeout 12 ./pdfcraft-0.8.0-linux-x86_64.AppImage    # stays alive = pass
```

In a container (or any install without `fusermount`), run the AppImage itself with
`APPIMAGE_EXTRACT_AND_RUN=1` instead of mounting it through FUSE. On a real desktop, just
double-click / `chmod +x && ./pdfcraft-*.AppImage` — Ubuntu 20.04 desktops ship the `fuse` package.

## Limitations (not yet done)

1. **CI still builds on `ubuntu-22.04`** (`.github/workflows/ci.yml`, see [releasing.md](releasing.md)).
   Artifacts produced by the stock release workflow again require glibc ≥ 2.35. Ubuntu 20.04 builds
   must go through `build-appimage.sh` (or the release job must be changed to run in an
   `ubuntu:20.04` container).
2. **Software-renderer Vulkan:** llvmpipe (mesa 21.2 on focal) exposes only
   `max_color_attachments = 2` while the app requests 8, so the wgpu path exits. Unlike gridcraft,
   pdfcraft logs the failure and **restarts itself on OpenGL** (`PDFCRAFT_RENDERER=gl` skips the
   wgpu attempt), which stayed alive for the full 12 s test. Real Intel/AMD/NVIDIA Vulkan drivers
   on Ubuntu 20.04 are not affected (not testable here: headless container).
3. **FUSE path not tested on a desktop:** a plain `./pdfcraft-*.AppImage` run inside the container
   fails with `No suitable fusermount binary found`, because the container has no `fuse`. The
   container tests above use `--appimage-extract` / `APPIMAGE_EXTRACT_AND_RUN=1`. A normal Ubuntu
   20.04 desktop has `fusermount`; that path was not re-tested here.
4. **deb/rpm not packaged in the test run** (`--formats "appimage"` only); the `nfpm.yaml` changes
   are YAML-validated but the produced `.deb` was not installed in a 20.04 VM.
5. **Network is mandatory:** rustup, crates.io + the `storytold/craft-libs` git deps, the OCR models
   (`cargo xtask models`) and appimagetool are all fetched during the build.

## Checklist when merging upstream (`storytold/pdfcraft`)

- [ ] `packaging/linux/nfpm.yaml`: upstream keeps `libc6 (>= 2.35)` and `libm.so.6(GLIBC_2.35)` —
      keep `>= 2.31` / `GLIBC_2.31` and the `libxkbcommon-x11*` entries (expect a conflict here).
- [ ] Re-run the container build (`How to build`) after every merge; new dependencies can raise the
      glibc floor silently.
- [ ] Re-run `objdump -p ... | grep 'required from libc'` on both binaries; highest version must
      stay ≤ `GLIBC_2.31`.
- [ ] Re-run the AppImage smoke test in `ubuntu:20.04` (table above).
- [ ] If upstream changes `.github/workflows/ci.yml` release job, re-check which distro the
      artifacts are built on.
- [ ] Bump the version/`sha256` entries in this file when a new AppImage is published.

## Log of runs

| Date | What | Result |
|---|---|---|
| 2026-10-16 | container build in `ubuntu:20.04` (`build-appimage.sh`: build + `package.sh --formats appimage`) | ✅ exit 0 |
| 2026-10-16 | glibc check of both binaries (`objdump -p`) | ✅ highest `GLIBC_2.30` |
| 2026-10-16 | `pdfcraft-cli --version` from the extracted AppImage in ubuntu:20.04 | ✅ `pdfcraft-cli 0.8.0` |
| 2026-10-16 | AppImage direct run in ubuntu:20.04 (no FUSE in container) | ❌ needs `fusermount` |
| 2026-10-16 | AppImage with `APPIMAGE_EXTRACT_AND_RUN=1`, default renderer (llvmpipe) | ✅ wgpu → OpenGL fallback, alive 12 s |
| 2026-10-16 | AppImage with `WGPU_BACKEND=gl` under Xvfb | ✅ alive 12 s |
| 2026-10-16 | extracted `AppRun` under Xvfb | ✅ alive 12 s |
