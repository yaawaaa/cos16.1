#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OUT_DIR=${OUT_DIR:-/home/rinnrei/Project/uwuAP-temp/out/nabu-4.14.336-yawaa}
ARTIFACTS=${ARTIFACTS:-$OUT_DIR/artifacts}
PACKAGE_ROOT=${PACKAGE_ROOT:-$OUT_DIR/packages}
TEMPLATE=$SCRIPT_DIR/anykernel.sh
ANYKERNEL_DIR=$SCRIPT_DIR/anykernel
RECOVERY=$SCRIPT_DIR/recovery/ramdisk-recovery.cpio.gz

for file in "$ARTIFACTS/Image.gz" "$ARTIFACTS/dtb" "$ARTIFACTS/dtbo.img" \
  "$TEMPLATE" "$ANYKERNEL_DIR/tools/ak3-core.sh" \
  "$ANYKERNEL_DIR/tools/busybox" "$ANYKERNEL_DIR/tools/magiskboot" \
  "$ANYKERNEL_DIR/META-INF/com/google/android/update-binary" \
  "$ANYKERNEL_DIR/META-INF/com/google/android/updater-script" "$RECOVERY"; do
  [ -f "$file" ] || { echo "kernel package input missing: $file" >&2; exit 2; }
done
[ "$(sha256sum "$RECOVERY" | awk '{print $1}')" = \
  248feef8879116c86df1729ecf9595b4be50834dd5bd66fe5732953cafaa4602 ] || {
  echo "embedded PBRP ramdisk checksum mismatch" >&2; exit 2;
}
[ "$(grep -c '^export BOOTMODE;$' "$ANYKERNEL_DIR/META-INF/com/google/android/update-binary")" -eq 1 ] || {
  echo "AnyKernel3 bootmode export is missing" >&2; exit 2;
}
command -v zip >/dev/null 2>&1 || { echo "zip is required" >&2; exit 2; }
command -v unzip >/dev/null 2>&1 || { echo "unzip is required" >&2; exit 2; }

KERNEL_RELEASE=${KERNEL_RELEASE:-}
if [ -z "$KERNEL_RELEASE" ]; then
  [ -r "$OUT_DIR/include/config/kernel.release" ] || {
    echo "kernel release metadata is missing" >&2; exit 2;
  }
  IFS= read -r KERNEL_RELEASE < "$OUT_DIR/include/config/kernel.release"
fi
KERNEL_SUFFIX=${KERNEL_RELEASE##*-}
[ "$KERNEL_SUFFIX" != "$KERNEL_RELEASE" ] || {
  echo "kernel release has no package suffix: $KERNEL_RELEASE" >&2; exit 2;
}
case "$KERNEL_SUFFIX" in
  ''|*[!A-Za-z0-9._-]*)
    echo "invalid package suffix: $KERNEL_SUFFIX" >&2; exit 2 ;;
esac

stamp=$(date -u +%H%M%S)
PACKAGE="$PACKAGE_ROOT/bk-Kernel_nabu-A17-Hyper-$KERNEL_SUFFIX-$stamp"
ZIP_PATH="$PACKAGE.zip"
[ ! -e "$PACKAGE" ] && [ ! -e "$ZIP_PATH" ] || {
  echo "package already exists: $PACKAGE" >&2; exit 1;
}
mkdir -p "$PACKAGE/tools" "$PACKAGE/recovery"
cp "$ARTIFACTS/Image.gz" "$PACKAGE/Image.gz"
cp "$ARTIFACTS/dtb" "$PACKAGE/dtb"
cp "$ARTIFACTS/dtbo.img" "$PACKAGE/dtbo.img"
cp "$TEMPLATE" "$PACKAGE/anykernel.sh"
chmod 0755 "$PACKAGE/anykernel.sh"
for tool in ak3-core.sh busybox magiskboot; do
  cp "$ANYKERNEL_DIR/tools/$tool" "$PACKAGE/tools/$tool"
done
cp -a "$ANYKERNEL_DIR/META-INF" "$PACKAGE/META-INF"
cp "$RECOVERY" "$PACKAGE/recovery/ramdisk-recovery.cpio.gz"
(cd "$PACKAGE" && zip -qr9 "$ZIP_PATH" .)
unzip -t "$ZIP_PATH" >/dev/null

expected_files=$(printf '%s\n' \
  Image.gz anykernel.sh dtb dtbo.img \
  META-INF/com/google/android/update-binary \
  META-INF/com/google/android/updater-script \
  recovery/ramdisk-recovery.cpio.gz \
  tools/ak3-core.sh tools/busybox tools/magiskboot | LC_ALL=C sort)
actual_files=$(unzip -Z1 "$ZIP_PATH" | grep -v '/$' | LC_ALL=C sort)
[ "$actual_files" = "$expected_files" ] || {
  echo "kernel package contains unexpected or missing files" >&2; exit 1;
}
unzip -p "$ZIP_PATH" anykernel.sh | grep -Fx 'device.name1=nabu' >/dev/null || {
  echo "AnyKernel target is not nabu" >&2; exit 1;
}
unzip -p "$ZIP_PATH" anykernel.sh | \
  grep -Fx "kernel.string=RinnRei's bk-Kernel / CoolApk @零音Rei" >/dev/null || {
  echo "AnyKernel kernel.string is incorrect" >&2; exit 1;
}
for required in \
  'Install the kernel from recovery; bkk-control is a separate module.' \
  'PBRP fastboot boot image detected.' \
  'patch_cmdline androidboot.force_normal_boot ""' \
  'patch_prop "$ramdisk/prop.default" ro.mi.os.custfeatureresolve true;' \
  'block=/dev/block/bootdevice/by-name/vendor_boot;' \
  'pbrp_sha256=15ae763c1f5b93ae48bcd007ff1f66871873aaee5b3a32852acbbf75b897fc54;'; do
  unzip -p "$ZIP_PATH" anykernel.sh | grep -F "$required" >/dev/null || {
    echo "AnyKernel step missing: $required" >&2; exit 1;
  }
done
[ "$(unzip -p "$ZIP_PATH" anykernel.sh | grep -c '^[[:space:]]*dump_boot;$')" -eq 2 ] || {
  echo "boot/vendor_boot dump steps are incomplete" >&2; exit 1;
}
[ "$(unzip -p "$ZIP_PATH" anykernel.sh | grep -c '^[[:space:]]*write_boot;$')" -eq 2 ] || {
  echo "boot/vendor_boot write steps are incomplete" >&2; exit 1;
}
[ "$(unzip -p "$ZIP_PATH" recovery/ramdisk-recovery.cpio.gz | sha256sum | awk '{print $1}')" = \
  248feef8879116c86df1729ecf9595b4be50834dd5bd66fe5732953cafaa4602 ] || {
  echo "packaged PBRP ramdisk checksum mismatch" >&2; exit 1;
}
(cd "$PACKAGE_ROOT" && sha256sum "$(basename "$ZIP_PATH")" > "$(basename "$ZIP_PATH").sha256")
echo "$ZIP_PATH"
