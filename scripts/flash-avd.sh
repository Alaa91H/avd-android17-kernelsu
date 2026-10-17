#!/usr/bin/env bash
# =============================================================================
#  تثبيت kernel-ranchu المبني داخل صورة نظام المحاكي (مع نسخة احتياطية)
#  الاستخدام: ./scripts/flash-avd.sh [مسار صورة النظام]
# =============================================================================
set -euo pipefail

IMAGE_DIR="${1:-$HOME/Android/Sdk/system-images/android-37.0/google_apis_playstore/x86_64}"
SRC="$(cd "$(dirname "$0")/.." && pwd)/out/kernel-ranchu"
TARGET="$IMAGE_DIR/kernel-ranchu"

[[ -f "$SRC" ]] || { echo "خطأ: لا يوجد $SRC (ابنِ النواة أولًا)" >&2; exit 1; }
[[ -d "$IMAGE_DIR" ]] || { echo "خطأ: مسار صورة النظام غير موجود: $IMAGE_DIR" >&2; exit 1; }

if [[ ! -f "$IMAGE_DIR/kernel-ranchu.stock" ]]; then
  echo "نسخة احتياطية: $TARGET -> $IMAGE_DIR/kernel-ranchu.stock"
  cp -a "$TARGET" "$IMAGE_DIR/kernel-ranchu.stock"
fi

echo "تثبيت: $SRC -> $TARGET"
sudo cp -f "$SRC" "$TARGET"
sudo chmod 644 "$TARGET"

echo "تم. الإصدار الجديد:"
strings -a "$TARGET" | grep -oE '6\.12\.[0-9]+-android16-[0-9]+-g[0-9a-f]+(-ab[0-9]+)?' | head -1 || \
  strings -a "$TARGET" | grep -m1 -oE '6\.12\.[0-9]+[^ ]*' || echo "(تعذّر الاستخراج — استخدم file $TARGET)"

echo
echo "للتراجع: sudo cp '$IMAGE_DIR/kernel-ranchu.stock' '$TARGET'"