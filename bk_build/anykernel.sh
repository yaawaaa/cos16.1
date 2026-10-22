#!/sbin/sh
# AnyKernel3 nabu installer; the packer adds Image.gz, dtb and dtbo.img.
properties() { "
kernel.string=RinnRei's bk-Kernel / CoolApk @零音Rei
device.name1=nabu
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
"; }

block=boot;
is_slot_device=1;
ramdisk_compression=auto;
. tools/ak3-core.sh;
if [ "$BOOTMODE" = true ]; then
  abort "Install the kernel from recovery; bkk-control is a separate module.";
fi
dump_boot;
if { [ -f "$split_img/cmdline.txt" ] && \
     grep -Eq '(^|[[:space:]])twrpfastboot=1([[:space:]]|$)' "$split_img/cmdline.txt"; } || \
   { [ -f "$split_img/header" ] && \
     grep -Eq '^cmdline=.*(^|[[:space:]])twrpfastboot=1([[:space:]]|$)' "$split_img/header"; }; then
  abort "PBRP fastboot boot image detected." \
        "Restore the matching system boot image, then flash this package without rebooting recovery.";
fi

pbrp_source="$home/recovery/ramdisk-recovery.cpio.gz";
pbrp_cpio="$home/ramdisk-recovery.cpio";
[ -f "$pbrp_source" ] || abort "Missing embedded PBRP recovery ramdisk.";
"$bin/magiskboot" decompress "$pbrp_source" "$pbrp_cpio" || \
  abort "Cannot decompress embedded PBRP recovery ramdisk.";
[ "$ramdisk" = "$home/ramdisk" ] || abort "Unexpected AnyKernel ramdisk path.";
rm -rf "$ramdisk";
mkdir -p "$ramdisk" || abort "Cannot create PBRP ramdisk directory.";
cd "$ramdisk";
EXTRACT_UNSAFE_SYMLINKS=1 cpio -d -F "$pbrp_cpio" -i || \
  abort "Cannot extract embedded PBRP recovery ramdisk.";
cd "$home";
[ -f "$ramdisk/init" ] && [ -f "$ramdisk/prop.default" ] && \
  [ -f "$ramdisk/twres/ui.xml" ] || abort "Embedded PBRP ramdisk is incomplete.";

# Keep recovery selection under the bootloader's force_normal_boot property.
patch_cmdline androidboot.force_normal_boot ""
patch_prop "$ramdisk/prop.default" ro.mi.os.custfeatureresolve true;

write_boot;

# vendor_boot is handled as a separate image on Android 12+ devices.
block=/dev/block/bootdevice/by-name/vendor_boot;
is_slot_device=1;
ramdisk_compression=auto;
patch_vbmeta_flag=auto;
reset_ak;
dump_boot;
write_boot;
