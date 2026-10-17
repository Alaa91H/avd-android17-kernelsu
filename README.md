# avd-android17-kernelsu

نواة **KernelSU-Next** مدمجة (built-in) لمحاكي **Android 17 / API 37** من Android Studio،
مبنية من **مصادر Google الرسمية** بنفس إصدار نواة المحاكي تمامًا — بدون Magisk وبدون ملفات `.ko` جاهزة.

A **KernelSU-Next**-enabled kernel for the **Android 17 (API 37)** Android Studio emulator,
built from Google's official AOSP kernel sources at the *exact* kernel revision used by the AVD.

---

## ما الذي يحلّه هذا المستودع؟

| المشكلة | السبب | الحل |
|---|---|---|
| ملفات `kernelsu.ko` الجاهزة لا تعمل | نواة المحاكي لا تصدّر 58 رمزًا يحتاجها LKM (مثل `avc_has_perm`, `policydb_*`) | دمج KernelSU-Next داخل النواة (built-in) |
| Magisk + LSPosed على أندرويد 17 | Zygisk يفشل في حقن الـ zygote على محاكي API 37 | KernelSU-Next + ZygiskNext + Vector |

## المبادئ

1. **نفس مصدر النواة**: `kernel/common` عند الوسم
   `android16-6.12-2025-12_r20` = `ccafb60de224d35a8bc14de33e1cd47caaaa786b`
   وهو نفس commit نواة المحاكي (`/proc/version`).
2. **نفس إصدار النواة بالضبط**: `6.12.58-android16-6-gccafb60de224-ab14828483`،
   وإلا رفضت النواة تحميل الوحدات المخزّنة في الرامديس و`vendor.img` (vermagic mismatch).
3. **دعم x86_64**: خيار `CONFIG_KSU_X86_PATCH_SYSCALL_DISPATCHER` (KernelSU-Next v3.4.x)
   يفعّل خطّاف الـ syscalls على إصدارات x86_64 الحديثة بدون تعديل نواة يدوي.

## البناء على GitHub Actions

سير العمل [`build-kernel.yml`](.github/workflows/build-kernel.yml) يبني الصورة تلقائيًا
ويحدّد `kernel-ranchu` + `kernel-ranchu.sha256` كـ **artifact** (وعند الدفع بوسم `v*` يرفعها إلى Release).

المخرجات في: `out/kernel-ranchu`

### تشغيل يدوي

```bash
export WORKSPACE=$PWD/ws PRUNE_GIT_OBJECTS=1
./scripts/prepare-workspace.sh
./scripts/build-kernel.sh
```

## التثبيت على المحاكي

```bash
# 1) استبدل نواة صورة النظام (مع نسخة احتياطية تلقائية)
./scripts/flash-avd.sh ~/Android/Sdk/system-images/android-37.0/google_apis_playstore/x86_64

# 2) شغّل المحاكي normally (لا حاجة لتمرير -kernel)
emulator -avd Medium_Phone_API_37.0 -no-snapshot
```

ثم:

```bash
adb install KernelSU_Next_v3.4.2_33355-release.apk     # تطبيق المدير
adb push ksud-x86_64-linux-android /data/local/tmp/    # من مخرجات KernelSU-Next
adb shell su -c 'cp /data/local/tmp/ksud /data/adb/ksud && chmod 755 /data/adb/ksud'
adb reboot
```

### مع Magisk (اختياري — لل amphitheater Ramanujan)

إن كان لديك Magisk مثبت، يمكن bootstrapping لـ `ksud` عبره، لكنه ليس مطلوبًا بعد أول تشغيل.

## LSPosed (Vector)

```bash
# ZygiskNext (بديل Zygisk لـ KernelSU/APatch) ثم Vector
adb push Zygisk-Next-1.5.2-864-a4a72ce-release.zip /data/local/tmp/
adb push Vector-v2.2-3080-Release.zip /data/local/tmp/
adb shell su -c 'ksud module install /data/local/tmp/Zygisk-Next-1.5.2-864-a4a72ce-release.zip'
adb shell su -c 'ksud module install /data/local/tmp/Vector-v2.2-3080-Release.zip'
adb reboot
# فتح مدير LSPosed parasitic:
adb shell su -c 'sh /data/adb/modules/zygisk_vector/action.sh'
```

## الملفات

| الملف | الوظيفة |
|---|---|
| `scripts/prepare-workspace.sh` | `repo init/sync`، تثبيت commit، دمج KernelSU-Next، تفعيل الخيارات، تثبيت الإصدار |
| `scripts/build-kernel.sh` | بناء Bazel/Kleaf + التحقق من مطابقة الإصدار + حزمة المخرجات |
| `scripts/flash-avd.sh` | تثبيت `kernel-ranchu` داخل صورة النظام مع نسخة احتياطية |
| `.github/workflows/build-kernel.yml` | بناء آلي على GitHub Actions |

## الترخيص / المصدر

- نواة Android: AOSP GPL-2.0 ([kernel/manifest](https://android.googlesource.com/kernel/manifest))
- KernelSU-Next: GPL-2.0 ([KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next))