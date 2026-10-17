# avd-android17-kernelsu

نواة **KernelSU-Next** مدمجة (built-in) لمحاكي **Android 17 / API 37** من Android Studio،
مبنية من **مصادر Google الرسمية** بنفس إصدار نواة المحاكي تمامًا — بدون Magisk وبدون ملفات `.ko` جاهزة.

A **KernelSU-Next**-enabled kernel for the **Android 17 (API 37)** Android Studio emulator,
built from Google's official AOSP kernel sources at the *exact* kernel revision used by the AVD.

> ✅ **مُختبَر فعليًا**: `su` يعمل، وLSPosed (Vector) يُحقَن في `system_server` بنجاح.

---

## ما الذي يحلّه هذا المستودع؟

| المشكلة | السبب | الحل |
|---|---|---|
| ملفات `kernelsu.ko` الجاهزة لا تعمل | نواة المحاكي لا تصدّر 58 رمزًا يحتاجها LKM (`avc_has_perm`, `policydb_*`, …) | دمج KernelSU-Next داخل النواة (built-in) |
| Magisk + LSPosed على أندرويد 17 | Zygisk يفشل في حقن الـ zygote على محاكي API 37 | KernelSU-Next + ZygiskNext + Vector |

## المبادئ

1. **نفس مصدر النواة**: `kernel/common` عند الوسم `android16-6.12-2025-12_r20`
   = `ccafb60de224d35a8bc14de33e1cd47caaaa786b` (نفس commit نواة المحاكي من `/proc/version`).
2. **نفس إصدار النواة بالضبط**: `6.12.58-android16-6-gccafb60de224-ab14828483`،
   وإلا رفضت النواة تحميل الوحدات المخزّنة في الرامديس و`vendor.img` (vermagic mismatch).
   (يُثبَّت عبر تعديل `stamp.bzl` في Kleaf).
3. **دعم x86_64**: خيار `CONFIG_KSU_X86_PATCH_SYSCALL_DISPATCHER` (KernelSU-Next v3.4.x)
   يفعّل خطّاف الـ syscalls على إصدارات x86_64 الحديثة بدون تعديل نواة يدوي.
   (`CONFIG_KSU` له `default=y` فلا يُكتب في الـ defconfig، وموضع
   `CONFIG_KSU_X86_PATCH_SYSCALL_DISPATCHER` يجب أن يطابق ناتج `savedefconfig` وإلا فشل البناء).

## البناء على GitHub Actions

سير العمل [`build-kernel.yml`](.github/workflows/build-kernel.yml) يبني الصورة تلقائيًا
ويحفظ `kernel-ranchu` + `kernel-ranchu.sha256` كـ **artifact** (90 يومًا).
يمكن أيضًا ربط الناتج بـ Release عبر مدخل `attach_release_tag` عند التشغيل اليدوي.

المخرجات في: `out/kernel-ranchu` — SHA256 الحالي:
`5b9dd8413664dbb3a983e7b5b34e8d6146ad08ca51563be44f1f2cda94c9513e`

### تشغيل يدوي (بنفس الخطوات)

```bash
export WORKSPACE=$PWD/ws PRUNE_GIT_OBJECTS=1
./scripts/prepare-workspace.sh
./scripts/build-kernel.sh
```

## التثبيت على المحاكي (خطوات مُختبَرة فعليًا ✅)

### 1) تثبيت النواة

```bash
./scripts/flash-avd.sh ~/Android/Sdk/system-images/android-37.0/google_apis_playstore/x86_64
```

للتراجع:
```bash
sudo cp ~/Android/Sdk/system-images/android-37.0/google_apis_playstore/x86_64/kernel-ranchu.stock \
        ~/Android/Sdk/system-images/android-37.0/google_apis_playstore/x86_64/kernel-ranchu
```

### 2) تفعيل `su` لـ adb shell

KernelSU-Next يعترض تنفيذ `/system/bin/su` داخل النواة (su compat)، لكن شِل adb
يقرأ المسار قبل التنفيذ — لذلك نفعّل معامل النواة:

```bash
IMG=~/Android/Sdk/system-images/android-37.0/google_apis_playstore/x86_64
echo " kernelsu.allow_shell=1" | sudo tee -a "$IMG/kernel_cmdline.txt"
```

### 3) تهيئة `ksud` (مرة واحدة)

> **مهم:** لا تشغّل Magisk مع KernelSU-Next في الوقت نفسه — يقوم `ksud` باكتشاف Magisk
> ويتخطّى كامل إعداداته: `Magisk detected, skip post-fs-data!` و `skip service`
> (فلا يُنشأ `su` ولا تُحمَّل الوحدات). استعمل **رامديس أصلي** بعد التهيئة.

أسهل طريقة: استخدم Magisk **مرة واحدة فقط** لوضع `ksud` ثم تخلَّص منه:

```bash
adb push ksud-x86_64-linux-android /data/local/tmp/          # من مخرجات KernelSU-Next v3.4.2
adb shell su -c 'cp /data/local/tmp/ksud /data/adb/ksud'
adb shell su -c 'chmod 755 /data/adb/ksud'
# ⇅ تسمية SELinux إلزامية، وإلا رفض init التنفيذ:
#   init: Could not start exec service: Cannot find '/data/adb/ksud': Permission denied
adb shell su -c 'chcon u:object_r:ksu_file:s0 /data/adb/ksud'
adb uninstall com.topjohnwu.magisk
```

ثم أعد تشغيل المحاكي **بدون** `-ramdisk ramdisk-patched.img`
(الرامديس الأصلي كافٍ — KernelSU-Next لا يحتاج تعديل الرامديس).

### 4) مدير KernelSU-Next

```bash
adb install KernelSU_Next_v3.4.2_33355-release.apk
```

### 5) التحقق

```bash
adb shell su -c id
# uid=0(root) gid=0(root) groups=0(root) context=u:r:ksu:s0
adb logcat -b all -d | grep "KernelSU Next" | head
```

## LSPosed (Vector) عبر ZygiskNext

```bash
adb push Zygisk-Next-1.5.2-864-a4a72ce-release.zip /data/local/tmp/
adb push Vector-v2.2-3080-Release.zip             /data/local/tmp/
adb shell su -c '/data/adb/ksud module install /data/local/tmp/Zygisk-Next-1.5.2-864-a4a72ce-release.zip'
adb shell su -c '/data/adb/ksud module install /data/local/tmp/Vector-v2.2-3080-Release.zip'
adb reboot
```

التحقق (يجب أن تظهر هذه الأسطر):

```bash
adb logcat -b all -d | grep Vector
# I/VectorNative  ] Injected Vector framework into system_server.
# I/VectorDaemon  ] Successfully injected Vector IPC binder for applications.

# فتح المدير (parasitic manager):
adb shell su -c 'sh /data/adb/modules/zygisk_vector/action.sh'
```

## الملفات

| الملف | الوظيفة |
|---|---|
| `scripts/prepare-workspace.sh` | `repo init/sync`، تثبيت commit، دمج KernelSU-Next، تفعيل الخيارات، تثبيت الإصدار |
| `scripts/build-kernel.sh` | بناء Bazel/Kleaf + التحقق من مطابقة الإصدار + حزمة المخرجات |
| `scripts/flash-avd.sh` | تثبيت `kernel-ranchu` داخل صورة النظام مع نسخة احتياطية |
| `.github/workflows/build-kernel.yml` | بناء آلي على GitHub Actions |

## المصادر والترخيص

- نواة Android: AOSP GPL-2.0 ([kernel/manifest](https://android.googlesource.com/kernel/manifest))
- KernelSU-Next: GPL-2.0 ([KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next))
- ZygiskNext و Vector: راجع التراخيص الأصلية (غير مضمّنة في هذا المستودع)