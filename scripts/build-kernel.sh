#!/usr/bin/env bash
# =============================================================================
#  بناء صورة نواة AVD (x86_64) + التحقق من مطابقة الإصدار + تجهيز حزمة التثبيت
# =============================================================================
set -euo pipefail

WORKSPACE="${WORKSPACE:-$HOME/kernel-kleaf}"
OUT_DIR="${OUT_DIR:-$WORKSPACE/out/avd-dist}"
TARGET="${TARGET:-//common:kernel_x86_64}"
EXPECTED_VERSION="${EXPECTED_VERSION:-6.12.58-android16-6-gccafb60de224-ab14828483}"

log() { echo "[build] $*"; }

mkdir -p "$OUT_DIR"
cd "$WORKSPACE"

# ------------------------------------------------------------- 1) البناء
log "بدء البناء: $TARGET (--config=fast --lto=none)"
tools/bazel build --config=fast --lto=none "$TARGET"

# ------------------------------------------------------------- 2) تحديد bzImage
BZIMAGE="$(find -L "$WORKSPACE/bazel-bin" -maxdepth 4 -name bzImage -type f 2>/dev/null | head -1)"
if [[ -z "$BZIMAGE" ]]; then
  echo "[build] خطأ: لم يتم العثور على bzImage" >&2
  exit 1
fi
log "تم العثور على: $BZIMAGE"

# ------------------------------------------------------------- 3) التحقق من الإصدار
GOT_VERSION="$(strings -a "$BZIMAGE" | grep -oE '6\.12\.[0-9]+-android16-[0-9]+-g[0-9a-f]+(-ab[0-9]+)?' | head -1 || true)"
if [[ -z "$GOT_VERSION" ]]; then
  # بzImage مضغوط: نستخرج vmlinux
  if "$WORKSPACE/common/scripts/extract-vmlinux" "$BZIMAGE" > "$OUT_DIR/vmlinux.tmp" 2>/dev/null; then
    GOT_VERSION="$(strings -a "$OUT_DIR/vmlinux.tmp" | grep -oE '6\.12\.[0-9]+-android16-[0-9]+-g[0-9a-f]+(-ab[0-9]+)?' | head -1 || true)"
    rm -f "$OUT_DIR/vmlinux.tmp"
  fi
fi
log "إصدار النواة في الصورة: ${GOT_VERSION:-<غير معروف>}"

# ------------------------------------------------------------- 4) الحزمة
cp -f "$BZIMAGE" "$OUT_DIR/kernel-ranchu"
chmod +x "$OUT_DIR/kernel-ranchu"

{
  echo "Kernel: KernelSU-Next for Android Emulator (AVD)"
  echo "Target: $TARGET"
  echo "Expected kernel release: $EXPECTED_VERSION"
  echo "Actual kernel release:   ${GOT_VERSION:-unknown}"
  echo "File: kernel-ranchu ($(du -h "$OUT_DIR/kernel-ranchu" | cut -f1))"
  echo "SHA256: $(sha256sum "$OUT_DIR/kernel-ranchu" | cut -d' ' -f1)"
} > "$OUT_DIR/kernel-info.txt"

( cd "$OUT_DIR" && sha256sum kernel-ranchu > kernel-ranchu.sha256 )

echo "----------------------------------------------"
cat "$OUT_DIR/kernel-info.txt"
echo "----------------------------------------------"
log "الحزمة في: $OUT_DIR"

if [[ "${GOT_VERSION}" != "$EXPECTED_VERSION" ]]; then
  echo "[build] تحذير: إصدار النواة لا يطابق نواة المحاكي الأصلية!" >&2
  echo "[build] عندها لن تعمل الوحدات (virtio) المخزّنة في الرامديس و vendor.img." >&2
  exit 2
fi
log "مطابقة الإصدار ناجحة ✓"