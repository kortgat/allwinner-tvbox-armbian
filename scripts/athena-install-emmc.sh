#!/bin/bash
# Install the running (SD-booted) Armbian system onto the box's eMMC.
#
# ERASES the eMMC. Run on the box, booted from SD, as root:
#   athena-install-emmc.sh /path/to/u-boot-athena-p7-ac300.bin
#
# Layout matches the SD image: 16 MiB gap for the bootloader (SPL at 8 KiB),
# FAT32 /boot (512 MiB), ext4 / (rest). The SoC boot ROM reads the SPL from
# the eMMC user area at 8 KiB; the SD card still takes priority when present.
set -euo pipefail

UBOOT=${1:?usage: $0 u-boot-athena-p7-ac300.bin}
DEV=/dev/mmcblk2
MNT=/mnt/emmc

[ -b "$DEV" ] || { echo "no eMMC at $DEV" >&2; exit 1; }
[ -s "$UBOOT" ] || { echo "missing $UBOOT" >&2; exit 1; }
root_src=$(findmnt -no SOURCE /)
case "$root_src" in
"$DEV"*) echo "refusing: / is on the eMMC ($root_src)" >&2; exit 1 ;;
esac
if [ "$(dd if="$UBOOT" bs=1 skip=4 count=8 status=none)" != "eGON.BT0" ]; then
	echo "$UBOOT is not an Allwinner boot image" >&2; exit 1
fi

echo "== wiping $DEV"
umount "$DEV"p* 2>/dev/null || true
wipefs -a "$DEV"p* 2>/dev/null || true
wipefs -a "$DEV"
blkdiscard -f "$DEV" 2>/dev/null || true

echo "== partitioning"
sfdisk -q "$DEV" <<EOF
label: dos
start=32768, size=1046528, type=c
start=1081344, type=83
EOF
partprobe "$DEV" 2>/dev/null || blockdev --rereadpt "$DEV"
udevadm settle

mkfs.vfat -F 32 -n BOOT_EMMC "$DEV"p1 >/dev/null
mkfs.ext4 -q -F -L ROOTFS_EMMC "$DEV"p2

boot_uuid=$(blkid -s UUID -o value "$DEV"p1)
root_uuid=$(blkid -s UUID -o value "$DEV"p2)

echo "== copying root filesystem"
mkdir -p "$MNT"
mount "$DEV"p2 "$MNT"
rsync -aAXH --numeric-ids --info=progress2 \
	--exclude={/boot/*,/dev/*,/proc/*,/sys/*,/run/*,/tmp/*,/mnt/*,/media/*,/lost+found,/var/log.hdd/*,/swapfile} \
	/ "$MNT"/

echo "== copying /boot"
mkdir -p "$MNT"/boot
mount "$DEV"p1 "$MNT"/boot
rsync -rt --info=progress2 /boot/ "$MNT"/boot/

echo "== pointing the copy at the eMMC"
# Mount by UUID: the SD card also carries a partition labelled BOOT
sed -i -E "s|^UUID=[^ ]+([[:space:]]+/[[:space:]])|UUID=$root_uuid\1|; s|^LABEL=BOOT([[:space:]])|UUID=$boot_uuid\1|" "$MNT"/etc/fstab
sed -i "s|^rootdev=.*|rootdev=UUID=$root_uuid|" "$MNT"/boot/armbianEnv.txt
grep -E "^(UUID|LABEL)" "$MNT"/etc/fstab
grep "^rootdev" "$MNT"/boot/armbianEnv.txt

sync
umount "$MNT"/boot "$MNT"

echo "== writing bootloader"
dd if="$UBOOT" of="$DEV" bs=1k seek=8 conv=fsync status=none
cmp -n "$(stat -c%s "$UBOOT")" "$UBOOT" <(dd if="$DEV" bs=1k skip=8 status=none) &&
	echo "bootloader verified"

echo "== done: power off, remove the SD card, and power on to boot from eMMC"
