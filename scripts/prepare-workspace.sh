#!/usr/bin/env bash
# =============================================================================
#  تحضير شجرة نواة Android 17 / GKI 6.12.58 (نواة محاكي AVD) مع KernelSU-Next
# =============================================================================
#  الهدف: إنتاج صورة نواة (bzImage) بنفس إصدار نواة المحاكي بالضبط،
#  لكن مع KernelSU-Next مدمج (built-in) + دعم كامل لـ x86_64.
#
#  نقطتان جوهريتان:
#   1) إصدار النواة (UTS_RELEASE) يجب أن يطابق نواة المحاكي الأصلية تمامًا،
#      وإلا لن تعمل الوحدات المخزّنة في الرامديس و vendor.img.
#   2) Kleaf يقارن gki_defconfig بناتج savedefconfig، لذلك يجب وضع
#      CONFIG_KSU_X86_PATCH_SYSCALL_DISPATCHER في الموضع الصحيح بالضبط،
#      وعدم كتابة CONFIG_KSU لأنه default=y أصلًا.
#
set -euo pipefail

WORKSPACE="${WORKSPACE:-$HOME/kernel-kleaf}"
MANIFEST_URL="${MANIFEST_URL:-https://android.googlesource.com/kernel/manifest}"
MANIFEST_BRANCH="${MANIFEST_BRANCH:-common-android16-6.12-2025-12}"

# وسم المطابق لنواة المحاكي: 6.12.58-android16-6-gccafb60de224-ab14828483
KERNEL_TAG="${KERNEL_TAG:-android16-6.12-2025-12_r20}"
KERNEL_COMMIT="${KERNEL_COMMIT:-ccafb60de224d35a8bc14de33e1cd47caaaa786b}"

KSU_REPO_URL="${KSU_REPO_URL:-https://github.com/KernelSU-Next/KernelSU-Next.git}"
KSU_TAG="${KSU_TAG:-v3.4.2}"

# اللاحقة التي تضيفها Kleaf بعد البادئة (-android16-6)
LOCALVERSION="${LOCALVERSION:--gccafb60de224-ab14828483}"

# أدوات سلاسل الترجمة الضخمة: نأخذ منها النسخة المستخدمة فقط (توفير ~10GB)
CLANG_REPO_URL="${CLANG_REPO_URL:-https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86}"
CLANG_PATHS="${CLANG_PATHS:-clang-r536225 clang-stable llvm-binutils-stable kleaf profiles embedded-sysroots docs}"
RUST_REPO_URL="${RUST_REPO_URL:-https://android.googlesource.com/platform/prebuilts/rust}"
RUST_PATHS="${RUST_PATHS:-linux-x86/1.82.0 bootstrap}"
SPARSE_TOOLCHAINS="${SPARSE_TOOLCHAINS:-1}"

# مشاريع غير لازمة لبناء صورة النواة
EXCLUDE_PROJECTS_RE="${EXCLUDE_PROJECTS_RE:-^(prebuilts/clang/host/linux-x86|prebuilts/rust|prebuilts/fuchsia_sdk|prebuilts/ndk-r26|test/.*|kernel/tests|external/arm-trusted-firmware|bootable/recovery|bootable/libbootloader|common-modules/virtio-media|common-modules/trusty|external/boringssl|external/compiler-rt|external/googletest)$}"

PRUNE_GIT_OBJECTS="${PRUNE_GIT_OBJECTS:-0}"
REPO_BIN="${REPO_BIN:-$HOME/bin/repo}"

log() { echo "[prepare] $*"; }
die() { echo "[prepare] خطأ: $*" >&2; exit 1; }

# ------------------------------------------------------------------ أدوات مساعدة
clone_sparse() {   # url, rev, dest, patterns...
  local url="$1" rev="$2" dest="$3"; shift 3
  if [[ -d "$dest/.git" ]]; then return 0; fi
  log "استنساخ ناقص: $(basename "$dest") ( Patterns: $* )"
  mkdir -p "$dest"
  (
    cd "$dest"
    git init -q
    git remote add origin "$url"
    git config advice.detachedHead false
    git sparse-checkout init --cone >/dev/null
    git sparse-checkout set "$@" >/dev/null
    git fetch -q --depth=1 origin "$rev"
    git checkout -q FETCH_HEAD
  )
}

# ------------------------------------------------------------------ 1) أداة repo
if [[ ! -x "$REPO_BIN" ]]; then
  log "تنزيل أداة repo..."
  mkdir -p "$(dirname "$REPO_BIN")"
  curl -sS --max-time 180 https://storage.googleapis.com/git-repo-downloads/repo -o "$REPO_BIN"
  chmod +x "$REPO_BIN"
fi

# ------------------------------------------------------------------ 2) المزامنة
mkdir -p "$WORKSPACE"
if [[ ! -d "$WORKSPACE/.repo" ]]; then
  log "repo init: $MANIFEST_BRANCH"
  (cd "$WORKSPACE" && "$REPO_BIN" init -u "$MANIFEST_URL" -b "$MANIFEST_BRANCH" --depth=1)
fi

DEFAULT_REV="$(sed -n 's/.*<default[^>]*revision="\([^"]*\)".*/\1/p' "$WORKSPACE/.repo/manifests/default.xml" | head -1)"
DEFAULT_REV="${DEFAULT_REV:-main-kernel-2025}"
log "إصدار الافتراضي للمانيفست: $DEFAULT_REV"

if [[ ! -d "$WORKSPACE/common" ]]; then
  log "repo sync (20-60 دقيقة)..."
  PROJECTS=()
  while IFS= read -r p; do PROJECTS+=("$p"); done < <(
    python3 - "$WORKSPACE/.repo/manifests/default.xml" "$EXCLUDE_PROJECTS_RE" <<'PY'
import re, sys, xml.etree.ElementTree as ET
manifest, exclude = sys.argv[1], re.compile(sys.argv[2])
for proj in ET.parse(manifest).getroot().iter("project"):
    path = proj.get("path")
    if path and not exclude.match(path):
        print(path)
PY
  )
  log "عدد المشاريع: ${#PROJECTS[@]}"
  (cd "$WORKSPACE" && "$REPO_BIN" sync -c -j"${SYNC_JOBS:-4}" --no-tags "${PROJECTS[@]}")
fi

# ------------------------------------------------------------------ 3) أدوات الترجمة (استنساخ ناقص)
if [[ "$SPARSE_TOOLCHAINS" == "1" ]]; then
  clone_sparse "$CLANG_REPO_URL" "$DEFAULT_REV" "$WORKSPACE/prebuilts/clang/host/linux-x86" $CLANG_PATHS
  clone_sparse "$RUST_REPO_URL"   "$DEFAULT_REV" "$WORKSPACE/prebuilts/rust"                 $RUST_PATHS
fi

# ------------------------------------------------------------------ 4) نفس commit نواة المحاكي
log "تثبيت نواة المصدر عند $KERNEL_TAG"
cd "$WORKSPACE/common"
git fetch --depth=1 https://android.googlesource.com/kernel/common \
    "refs/tags/$KERNEL_TAG:refs/tags/$KERNEL_TAG" >/dev/null 2>&1 || true
git checkout -f "$KERNEL_TAG"
ACTUAL="$(git rev-parse HEAD)"
[[ "$ACTUAL" == "$KERNEL_COMMIT" ]] || die "commit غير مطابق: $ACTUAL"
log "commit = $ACTUAL"

# ------------------------------------------------------------------ 5) دمج KernelSU-Next
log "دمج KernelSU-Next $KSU_TAG"
cd "$WORKSPACE"
if [[ ! -d KernelSU-Next ]]; then
  git clone -q --depth=1 --branch "$KSU_TAG" "$KSU_REPO_URL" KernelSU-Next
else
  ( cd KernelSU-Next
    git fetch -q --depth=1 origin "refs/tags/$KSU_TAG:refs/tags/$KSU_TAG" >/dev/null 2>&1 || true
    git checkout -f "$KSU_TAG" )
fi
ln -sfn ../../KernelSU-Next/kernel common/drivers/kernelsu

grep -q "kernelsu" common/drivers/Makefile || printf "\nobj-\$(CONFIG_KSU) += kernelsu/\n" >> common/drivers/Makefile
grep -q 'source "drivers/kernelsu/Kconfig"' common/drivers/Kconfig || \
  sed -i '/endmenu/i source "drivers/kernelsu/Kconfig"' common/drivers/Kconfig

# ------------------------------------------------------------------ 6) خيارات النواة
DEFCONFIG="$WORKSPACE/common/arch/x86/configs/gki_defconfig"
# Kleaf يشترط أن يطابق defconfig ناتج savedefconfig (بما فيه الترتيب).
# CONFIG_KSU له default=y فلا يُكتب إطلاقًا؛
# و CONFIG_KSU_X86_PATCH_SYSCALL_DISPATCHER يقع بعد خيارات drivers/ وقبل fs/.
if ! grep -q "CONFIG_KSU_X86_PATCH_SYSCALL_DISPATCHER" "$DEFCONFIG"; then
  log "تفعيل CONFIG_KSU_X86_PATCH_SYSCALL_DISPATCHER في $DEFCONFIG"
  sed -i '0,/^CONFIG_EXT4_FS=/s//CONFIG_KSU_X86_PATCH_SYSCALL_DISPATCHER=y\nCONFIG_EXT4_FS=/' "$DEFCONFIG"
fi
grep -n "KSU" "$DEFCONFIG" || true

# ------------------------------------------------------------------ 7) تثبيت نسخة النواة
# Kleaf يكتب اللاحقة في <out>/localversion عبر stamp.bzl — نثبّتها على قيمة
# المحاكي الأصلية حتى تعمل وحدات الرامديس و vendor.img دون تعديل.
STAMP="$WORKSPACE/build/kernel/kleaf/impl/stamp.bzl"
log "تثبيت localversion = android16-6$LOCALVERSION"
python3 - "$STAMP" "$LOCALVERSION" <<'PY'
import sys
path, suffix = sys.argv[1], sys.argv[2]
src = open(path).read()
old = """stable_scmversion_cmd = "echo '-maybe-dirty'\""""
new = """stable_scmversion_cmd = "echo '%s'\"""" % suffix
if old in src:
    open(path, "w").write(src.replace(old, new))
    print("[prepare] تم تعديل stamp.bzl")
else:
    print("[prepare] stamp.bzl معدّل مسبقًا (أو بدون سطر maybe-dirty) — تجاهل")
PY

# ------------------------------------------------------------------ 8) تنظيف
if [[ "$PRUNE_GIT_OBJECTS" == "1" ]]; then
  log "حذف كائنات git لتحرير المساحة"
  rm -rf "$WORKSPACE/.repo/project-objects" || true
  rm -rf "$WORKSPACE/.repo/projects"/*/  2>/dev/null || true
fi

log "اكتمل التجهيز: $WORKSPACE"
df -h "$WORKSPACE" | tail -1
du -sh "$WORKSPACE" 2>/dev/null | tail -1