### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
# begin properties
properties() { '
kernel.string=Asgard-OSS Kernel v1.1
do.devicecheck=0
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name3=
device.name4=
device.name5=
supported.versions=
supported.patchlevels=
'; } # end properties

### AnyKernel install

## boot shell variables
block=boot
is_slot_device=1
ramdisk_compression=auto
patch_vbmeta_flag=auto

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh

split_boot

########## CUSTOM START ##########

BOOTMODE=false;
ps | grep zygote | grep -v grep >/dev/null && BOOTMODE=true;
$BOOTMODE || ps -A 2>/dev/null | grep zygote | grep -v grep >/dev/null && BOOTMODE=true;


extract_erofs() {
	local img_file=$1
	local out_dir=$2

	${bin}/extract.erofs -i $img_file -x -T8 -o $out_dir &> /dev/null
}

mkfs_erofs() {
	local work_dir=$1
	local out_file=$2

	local partition_name=$(basename $work_dir)

	${bin}/mkfs.erofs \
		--mount-point /${partition_name} \
		--fs-config-file ${work_dir}/../config/${partition_name}_fs_config \
		--file-contexts  ${work_dir}/../config/${partition_name}_file_contexts \
		-z lz4hc \
		$out_file $work_dir
}

is_mounted() { mount | grep -q " $1 "; }

# Check snapshot status
# Technical details: https://blog.xzr.moe/archives/30/
${bin}/snapshotupdater_static dump &>/dev/null
rc=$?
if [ "$rc" != 0 ]; then
	ui_print "Cannot get snapshot status via snapshotupdater_static! rc=$rc."
	if $BOOTMODE; then
		ui_print "If you are installing the kernel in an app, try using another app."
		ui_print "Recommend KernelFlasher:"
		ui_print "  https://github.com/fatalcoder524/KernelFlasher/releases"
	else
		ui_print "Please try to reboot to system once before installing!"
	fi
	abort "Aborting..."
fi
snapshot_status=$(${bin}/snapshotupdater_static dump 2>/dev/null | grep '^Update state:' | awk '{print $3}')
ui_print "Current snapshot state: $snapshot_status"
if [ "$snapshot_status" != "none" ]; then
	ui_print " "
	ui_print "Seems like you just installed a rom update."
	if [ "$snapshot_status" == "merging" ]; then
		ui_print "Please use the rom for a while to wait for"
		ui_print "the system to complete the snapshot merge."
		ui_print "It's also possible to use the \"Merge Snapshots\" feature"
		ui_print "in TWRP's Advanced menu to instantly merge snapshots."
	else
		ui_print "Please try to reboot to system once before installing!"
	fi
	abort "Aborting..."
fi
unset rc snapshot_status

# Extract kernel version info
kernel_name=$(basename "$ZIPFILE" .zip)

# Fix unable to mount image as read-write in recovery
$BOOTMODE || setenforce 0

########## VENDOR_DLKM PROCESSING ##########

# Check vendor_dlkm partition status
[ -d /vendor_dlkm ] || mkdir /vendor_dlkm
is_mounted /vendor_dlkm || \
	mount /vendor_dlkm -o ro || mount /dev/block/mapper/vendor_dlkm${slot} /vendor_dlkm -o ro || \
		abort "! Failed to mount /vendor_dlkm"

# Always update vendor_dlkm to ensure modules are current
umount /vendor_dlkm

# Dump vendor_dlkm partition image
ui_print "- Dumping vendor_dlkm partition..."
dd if=/dev/block/mapper/vendor_dlkm${slot} of=${home}/vendor_dlkm.img

ui_print "- Unpacking /vendor_dlkm partition..."
extract_vendor_dlkm_dir=${home}/_extract_vendor_dlkm
mkdir -p $extract_vendor_dlkm_dir
vendor_dlkm_is_ext4=false
extract_erofs ${home}/vendor_dlkm.img $extract_vendor_dlkm_dir || vendor_dlkm_is_ext4=true
sync

if $vendor_dlkm_is_ext4; then
	ui_print "- /vendor_dlkm partition is ext4 file system"
	mount ${home}/vendor_dlkm.img $extract_vendor_dlkm_dir -o ro -t ext4 || \
		abort "! Unsupported file system!"
	vendor_dlkm_free_space=$(df -k | grep -E "[[:space:]]$extract_vendor_dlkm_dir\$" | awk '{print $4}')
	umount $extract_vendor_dlkm_dir

	if [ "$vendor_dlkm_free_space" -lt 10240 ]; then
		ui_print "- Insufficient free space, attempting resize..."
		super_free_space=$(${bin}/lptools_static free | grep '^Free space' | awk '{print $NF}')
		[ "$super_free_space" -gt "$((10 * 1024 * 1024))" ] || \
			abort "! Super device does not have enough free space!"

		${bin}/e2fsck -f -y ${home}/vendor_dlkm.img
		vendor_dlkm_current_size_mb=$(du -bm ${home}/vendor_dlkm.img | awk '{print $1}')
		vendor_dlkm_target_size_mb=$((vendor_dlkm_current_size_mb + 10))
		${bin}/resize2fs ${home}/vendor_dlkm.img "${vendor_dlkm_target_size_mb}M" || \
			abort "! Failed to resize vendor_dlkm image!"
		ui_print "- Resized to ${vendor_dlkm_target_size_mb}M"
		${bin}/e2fsck -f -y ${home}/vendor_dlkm.img

		unset super_free_space vendor_dlkm_current_size_mb vendor_dlkm_target_size_mb
	fi

	mount ${home}/vendor_dlkm.img $extract_vendor_dlkm_dir -o rw -t ext4 || \
		abort "! Failed to mount vendor_dlkm.img as read-write!"

	extract_vendor_dlkm_modules_dir=${extract_vendor_dlkm_dir}/lib/modules
else
	extract_vendor_dlkm_modules_dir=${extract_vendor_dlkm_dir}/vendor_dlkm/lib/modules
fi

# Update vendor modules (from _modules_vendor directory)
ui_print "- Updating /vendor_dlkm modules..."
if [ -d "${home}/_modules_vendor" ] && [ "$(ls -A ${home}/_modules_vendor/*.ko 2>/dev/null)" ]; then
	cp -f ${home}/_modules_vendor/*.ko ${extract_vendor_dlkm_modules_dir}/
	ui_print "  Copied $(ls ${home}/_modules_vendor/*.ko 2>/dev/null | wc -l) vendor modules"
else
	ui_print "  Warning: _modules_vendor directory not found or empty, skipping vendor modules"
fi
sync

if $vendor_dlkm_is_ext4; then
	umount $extract_vendor_dlkm_dir
else
	ui_print "- Repacking /vendor_dlkm image..."
	rm -f ${home}/vendor_dlkm.img
	mkfs_erofs ${extract_vendor_dlkm_dir}/vendor_dlkm ${home}/vendor_dlkm.img || \
		abort "! Failed to repack the vendor_dlkm image!"
	rm -rf ${extract_vendor_dlkm_dir}
fi

unset vendor_dlkm_is_ext4 vendor_dlkm_free_space extract_vendor_dlkm_dir extract_vendor_dlkm_modules_dir

########## SYSTEM_DLKM PROCESSING ##########

# Check system_dlkm partition status
[ -d /system_dlkm ] || mkdir /system_dlkm
is_mounted /system_dlkm || \
	mount /system_dlkm -o ro || mount /dev/block/mapper/system_dlkm${slot} /system_dlkm -o ro || \
		abort "! Failed to mount /system_dlkm"

# Always update system_dlkm to ensure modules are current
umount /system_dlkm

# Dump system_dlkm partition image
ui_print "- Dumping system_dlkm partition..."
dd if=/dev/block/mapper/system_dlkm${slot} of=${home}/system_dlkm.img

ui_print "- Unpacking /system_dlkm partition..."
extract_system_dlkm_dir=${home}/_extract_system_dlkm
mkdir -p $extract_system_dlkm_dir
system_dlkm_is_ext4=false
extract_erofs ${home}/system_dlkm.img $extract_system_dlkm_dir || system_dlkm_is_ext4=true
sync

if $system_dlkm_is_ext4; then
	ui_print "- /system_dlkm partition is ext4 file system"
	mount ${home}/system_dlkm.img $extract_system_dlkm_dir -o ro -t ext4 || \
		abort "! Unsupported file system!"
	system_dlkm_free_space=$(df -k | grep -E "[[:space:]]$extract_system_dlkm_dir\$" | awk '{print $4}')
	umount $extract_system_dlkm_dir

	if [ "$system_dlkm_free_space" -lt 10240 ]; then
		ui_print "- Insufficient free space, attempting resize..."
		super_free_space=$(${bin}/lptools_static free | grep '^Free space' | awk '{print $NF}')
		[ "$super_free_space" -gt "$((10 * 1024 * 1024))" ] || \
			abort "! Super device does not have enough free space!"

		${bin}/e2fsck -f -y ${home}/system_dlkm.img
		system_dlkm_current_size_mb=$(du -bm ${home}/system_dlkm.img | awk '{print $1}')
		system_dlkm_target_size_mb=$((system_dlkm_current_size_mb + 10))
		${bin}/resize2fs ${home}/system_dlkm.img "${system_dlkm_target_size_mb}M" || \
			abort "! Failed to resize system_dlkm image!"
		ui_print "- Resized to ${system_dlkm_target_size_mb}M"
		${bin}/e2fsck -f -y ${home}/system_dlkm.img

		unset super_free_space system_dlkm_current_size_mb system_dlkm_target_size_mb
	fi

	mount ${home}/system_dlkm.img $extract_system_dlkm_dir -o rw -t ext4 || \
		abort "! Failed to mount system_dlkm.img as read-write!"

	extract_system_dlkm_modules_dir=${extract_system_dlkm_dir}/lib/modules/android16-6.1
else
	extract_system_dlkm_modules_dir=${extract_system_dlkm_dir}/system_dlkm/lib/modules/android16-6.1
fi

# Create android16-6.1 directory if it doesn't exist
mkdir -p ${extract_system_dlkm_modules_dir}

# Update system modules (from _modules_system directory)
ui_print "- Updating /system_dlkm modules..."
if [ -d "${home}/_modules_system" ] && [ "$(ls -A ${home}/_modules_system/*.ko 2>/dev/null)" ]; then
	cp -f ${home}/_modules_system/*.ko ${extract_system_dlkm_modules_dir}/
	ui_print "  Copied $(ls ${home}/_modules_system/*.ko 2>/dev/null | wc -l) system modules"
else
	ui_print "  Warning: _modules_system directory not found or empty, skipping system modules"
fi
sync

if $system_dlkm_is_ext4; then
	umount $extract_system_dlkm_dir
else
	ui_print "- Repacking /system_dlkm image..."
	rm -f ${home}/system_dlkm.img
	mkfs_erofs ${extract_system_dlkm_dir}/system_dlkm ${home}/system_dlkm.img || \
		abort "! Failed to repack the system_dlkm image!"
	rm -rf ${extract_system_dlkm_dir}
fi

unset system_dlkm_is_ext4 system_dlkm_free_space extract_system_dlkm_dir extract_system_dlkm_modules_dir

########## CUSTOM END ##########

# Flash updated /vendor_dlkm image
vendor_dlkm_flashed=false
if [ -f ${home}/vendor_dlkm.img ]; then
	ui_print "- Flashing vendor_dlkm partition..."
	flash_generic vendor_dlkm
	vendor_dlkm_flashed=true
fi

# Flash updated /system_dlkm image
system_dlkm_flashed=false
if [ -f ${home}/system_dlkm.img ]; then
	ui_print "- Flashing system_dlkm partition..."
	flash_generic system_dlkm
	system_dlkm_flashed=true
fi

# Flash kernel to boot
boot_flashed=false
flash_boot && boot_flashed=true

# Recovery instructions (only show if all operations completed)
if $boot_flashed && ($vendor_dlkm_flashed || $system_dlkm_flashed); then
	ui_print " "
	ui_print "============================================"
	ui_print "  IMPORTANT INFORMATION"
	ui_print "============================================"
	ui_print " "
	ui_print "If your device doesn't boot or goes to"
	ui_print "fastboot:"
	ui_print " "
	ui_print "  * Flash original boot.img"
	ui_print "  * Reboot to recovery"
	ui_print "  * Dirty flash your ROM"
	ui_print " "
	ui_print "============================================"
	ui_print " "
fi
