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
for t in bc flex bison openssl pahole; do
  printf '  %-10s %s\n' "$t" "$(command -v $t || echo MISSING)"
done

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
else
  echo "=== configuring: stock gki_defconfig ==="
  make gki_defconfig
fi

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
echo "=== building Image + vmlinux (modules skipped to save disk) ==="
df -h . | tail -1
make -j"$(nproc)" Image
df -h . | tail -1

cp -v arch/arm64/boot/Image "$OUT/Image"
cp -v vmlinux "$OUT/vmlinux"
echo "=== compressing vmlinux (DWARF is huge; lldb reads the .gz fine) ==="
gzip -9 -f "$OUT/vmlinux"
rm -f "$OUT/vmlinux"
ls -la "$OUT"
echo "=== done: $VARIANT ==="