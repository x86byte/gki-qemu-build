#!/bin/bash
# Build the Android GKI (android-mainline, arm64) and emit Image + vmlinux.
# Runs on a GitHub Actions Linux runner.
#
# Deliberately does NOT use the AOSP `repo` + Bazel/Kleaf flow: that pulls tens
# of GB and is fragile in CI. A plain LLVM kernel build off gki_defconfig gives
# the same arm64 GKI binaries in ~40 minutes.
#
#   release : stock gki_defconfig -- matches what ships, for fidelity
#   debug   : + software KASAN / UBSAN / DEBUG_ATOMIC_SLEEP -- for finding bugs
set -euo pipefail

VARIANT="${1:-release}"
KSRC="${KSRC:-/home/runner/kernel/common}"
OUT="${OUT:-/home/runner/kernel/out}"

cd "$KSRC"
export ARCH=arm64
export LLVM=1
export CROSS_COMPILE=aarch64-linux-gnu-
export KBUILD_BUILD_USER=android
export KBUILD_BUILD_HOST=qemu-re

echo "=== toolchain ==="
clang --version | head -2
# Not all runner images put ld.lld on PATH; do not let a missing one kill the
# build here, the kernel build itself will fail loudly if it truly needs it.
ld.lld --version 2>/dev/null || ld.lld-18 --version 2>/dev/null || echo "ld.lld not found on PATH (build will need it)"
make --version | head -1
for t in bc flex bison openssl pahole rustc cargo bindgen; do
  printf '  %-10s %s\n' "$t" "$(command -v $t || echo MISSING)"
done

# The GKI ships the *Rust* binder, and gki_defconfig selects it. RUST however
# hangs off `RUST_IS_AVAILABLE`, a def_bool $(success, scripts/rust_is_available.sh)
# probe. On a runner with no Rust toolchain that probe fails, olddefconfig then
# drops CONFIG_RUST, and CONFIG_ANDROID_BINDER_IPC_RUST (which `depends on RUST`)
# silently disappears with it -- you get a kernel with NO binder driver at all
# and no warning anywhere. This is checked explicitly below so it can never
# happen silently again.
echo "=== rust availability probe ==="
if make rustavailable; then
  echo "  rust toolchain detected by the kernel build"
else
  echo "  WARNING: kernel reports no Rust toolchain; CONFIG_RUST and therefore"
  echo "           CONFIG_ANDROID_BINDER_IPC_RUST will be dropped by olddefconfig."
  echo "           The resulting kernel has no binder driver."
fi

# AOSP's top-level Kconfig ends with
#     source "$(KCONFIG_EXT_PREFIX)Kconfig.ext"
# which is a hook for downstream kernel forks to splice in their own Kconfig.
# kernel/common itself does not ship a Kconfig.ext (404), so a pristine
# android-mainline checkout cannot even run `make gki_defconfig` without one.
# An empty file is the intended no-op: KCONFIG_EXT_PREFIX defaults to empty, so
# this resolves to the stub and nothing extra is sourced.
if [ ! -e Kconfig.ext ]; then
  : > Kconfig.ext
  echo "created empty Kconfig.ext stub (AOSP external-Kconfig hook)"
fi

if [ "$VARIANT" = "debug" ]; then
  echo "=== configuring: gki_defconfig + KASAN/UBSAN ==="
  make gki_defconfig
  # Software-tag KASAN rather than the HW-tag variant gki_defconfig selects:
  # HW tags need the tagged-pointer ABI and a lot of VA we do not want here.
  # KMEMLEAK is deliberately NOT enabled -- it conflicts with KASAN.
  scripts/config --file .config \
    -e KASAN \
    -e KASAN_GENERIC \
    -e KASAN_OUTLINE \
    -e KASAN_STACK \
    -e KASAN_VMALLOC \
    -d KASAN_HW_TAGS \
    -e UBSAN \
    -e UBSAN_BOUNDS \
    -e UBSAN_SHIFT \
    -e UBSAN_ALIGN \
    -e DEBUG_ATOMIC_SLEEP \
    -e LOCKDEP \
    -e DEBUG_LOCK_ALLOC \
    -e PROVE_LOCKING \
    -e DEBUG_INFO_DWARF5 \
    -d DEBUG_INFO_NONE
  make olddefconfig
  # KASAN adds a large redzone to every stack frame, which pushes several
  # GKI ioctl handlers over the 2048-byte -Wframe-larger-than limit that the
  # GKI sets as -Werror. It is a warning about code we are not changing, and it
  # only fires in this instrumented variant, so downgrade it to a warning.
  # Observed: fs/exfat/file.c:607 exfat_ioctl, stack frame size (2336).
  scripts/config --file .config -d WERROR
  make olddefconfig
  grep -E '^(# )?CONFIG_WERROR' .config || echo "  (WERROR not written out)"
else
  echo "=== configuring: stock gki_defconfig ==="
  make gki_defconfig
fi

# BTF generation is the last step and it is the one that fails on this host:
# pahole aborts with "Reached the limit of per-CPU variables: 4096" and then
# "Failed to generate BTF for vmlinux", after the full 40 minute compile.
# We do not need it: vmlinux already carries DWARF5, which is what lldb and gdb
# actually consume. BTF matters for *shipping* kernels where you have no
# vmlinux at all -- for a self-built debug kernel it is strictly redundant.
echo "=== disabling CONFIG_DEBUG_INFO_BTF (pahole per-CPU limit; DWARF5 is what we debug with) ==="
scripts/config --file .config -d DEBUG_INFO_BTF
make olddefconfig
grep -E '^CONFIG_DEBUG_INFO' .config

echo "=== sanity: symbols the QEMU harness depends on ==="
# BLK_DEV_INITRD + RD_GZIP are default-y so they may not appear literally; a
# missing CONFIG_ line for those is fine, anything else is a real problem.
for sym in SERIAL_AMBA_PL011 SERIAL_AMBA_PL011_CONSOLE DEVTMPFS DEVTMPFS_MOUNT \
           PROC_FS SYSFS KALLSYMS BLK_DEV_INITRD RD_GZIP; do
  line=$(grep -E "^CONFIG_${sym}=" .config || true)
  printf '  %-26s %s\n' "$sym" "${line:-<default-y, not written out>}"
done
echo "  VA_BITS: $(grep -E '^CONFIG_ARM64_VA_BITS=' .config)"
echo "  KASAN:   $(grep -E '^CONFIG_KASAN=' .config || echo 'not set (release)')"

mkdir -p "$OUT"

# Hard assert on the things a silently-dropped dependency can take with it.
# Getting burned by a missing binder already cost us a full build cycle.
echo "=== assert: binder must be present ==="
if ! grep -qE '^CONFIG_ANDROID_BINDER_IPC_RUST=y' .config; then
  echo "FATAL: CONFIG_ANDROID_BINDER_IPC_RUST is not set in .config."
  echo "       CONFIG_RUST is: $(grep -E '^(# )?CONFIG_RUST=' .config || echo 'absent')"
  echo "       -> this kernel has no binder driver; it cannot be used for binder work."
  exit 1
fi
echo "  CONFIG_ANDROID_BINDER_IPC_RUST=y  (Rust binder built in)"

# gendwarfksyms needs <dwarf.h>, which Debian/Ubuntu install under a versioned
# directory. If the workflow could not put it on the include path, drop the
# feature rather than the build: we only need a bootable Image and vmlinux, not
# the .ksyms sidecar.
if ! ls /usr/include/dwarf.h >/dev/null 2>&1; then
  echo "=== no dwarf.h on the include path, disabling GENDWARFKSYMS ==="
  scripts/config --file .config -d GENDWARFKSYMS
  make olddefconfig
  grep -E '^CONFIG_GENDWARFKSYMS' .config || echo "  (GENDWARFKSYMS now off)"
fi

echo "=== building Image + vmlinux ==="
df -h . | tail -1
make -j"$(nproc)" Image
df -h . | tail -1

cp -v arch/arm64/boot/Image "$OUT/Image"
echo "=== compressing vmlinux in place (avoids holding two multi-GB copies) ==="
gzip -9 -f vmlinux
mv -v vmlinux.gz "$OUT/vmlinux.gz"

# Modules. gki_defconfig sets 124 symbols to =m, and `make Image` never builds
# them, so without this step the artifact ships with zero .ko files and the
# whole module surface is simply absent. They are small compared to the kernel
# proper, and the release variant has the disk headroom, so build them.
#
# `modules_install` needs the staging layout (System.map, Module.symvers);
# `make modules` alone is enough to get the .ko files with symbols.
if [ "$VARIANT" = "release" ]; then
  echo "=== building modules ($(grep -c '=m$' .config || true) configured =m) ==="
  make -j"$(nproc)" modules
  echo "=== collecting modules into $OUT/modules ==="
  rm -rf "$OUT/modules"
  mkdir -p "$OUT/modules"
  # -C is fine here: a module built as =m has no external module deps in a
  # GKI build unless CONFIG_MODVERSIONS needs a matching Module.symvers, which
  # the kernel build has already produced next to vmlinux.
  find . -name '*.ko' ! -name '*.ko.*' -exec cp --parents {} "$OUT/modules/" \;
  echo "modules built: $(find "$OUT/modules" -name '*.ko' | wc -l)"
  # A flat copy too: the tree layout above preserves the build path, but a flat
  # directory is what you actually insmod from and what depmod wants to hash.
  mkdir -p "$OUT/modules-flat"
  find . -name '*.ko' ! -name '*.ko.*' -exec cp {} "$OUT/modules-flat/" \;
  echo "flat modules: $(find "$OUT/modules-flat" -name '*.ko' | wc -l)"
fi

ls -la "$OUT"
echo "=== done: $VARIANT ==="