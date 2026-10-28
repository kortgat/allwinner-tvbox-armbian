#!/bin/bash
# Make a compact, flashable golden image from the generalized athena SD card.
# Run on the PC as root with the card inserted:
#   sudo scripts/athena-make-image.sh /dev/sdX [name-prefix]
# (default prefix athena-h618-armbian-golden; eros-h313-lpddr3-armbian-golden
# for the LPDDR3 box)
#
# Shrinks the card's ext4 root (Armbian grows it again on a new box's first
# boot), trims partition 2 to match, copies only the used span and compresses.
set -euo pipefail

DEV=${1:?usage: $0 /dev/sdX [name-prefix]}
NAME=${2:-athena-h618-armbian-golden}
OUT_DIR=$PWD   # image lands in the current directory
OUT=$OUT_DIR/$NAME-$(date +%Y%m%d).img
HEADROOM_MIB=512   # free space kept for the first boot, before the auto-resize

[ "$(id -u)" = 0 ] || { echo "run as root (sudo)" >&2; exit 1; }
[ -b "$DEV" ] || { echo "$DEV is not a block device" >&2; exit 1; }
case "$DEV" in *[0-9]) P=${DEV}p ;; *) P=$DEV ;; esac
[ "$(blkid -s LABEL -o value "${P}1")" = BOOT ] &&
[ "$(blkid -s LABEL -o value "${P}2")" = ROOTFS ] ||
	{ echo "$DEV does not look like the athena Armbian card (BOOT/ROOTFS)" >&2; exit 1; }
[ -e "$(dirname "$OUT")" ] || exit 1
lsblk -o NAME,SIZE,LABEL,MODEL "$DEV"

umount "${P}1" "${P}2" 2>/dev/null || true

echo "== checking and shrinking the root filesystem"
e2fsck -fy "${P}2"
bs=$(dumpe2fs -h "${P}2" 2>/dev/null | awk -F: '/^Block size/ { gsub(/ /, "", $2); print $2 }')
min_blocks=$(resize2fs -P "${P}2" 2>/dev/null | awk -F: '/minimum/ { gsub(/ /, "", $2); print $2 }')
new_blocks=$(( min_blocks + HEADROOM_MIB * 1024 * 1024 / bs ))
resize2fs "${P}2" "$new_blocks"

echo "== trimming partition 2"
start=$(cat "/sys/class/block/$(basename "${P}2")/start")
sectors=$(( new_blocks * bs / 512 ))
echo "${start},${sectors}" | sfdisk -q -N 2 --no-reread "$DEV"
partprobe "$DEV" 2>/dev/null || true
end_bytes=$(( (start + sectors) * 512 ))

echo "== copying $(( end_bytes / 1024 / 1024 )) MiB"
dd if="$DEV" of="$OUT" bs=1M count=$(( (end_bytes + 1048575) / 1048576 )) \
	conv=fsync status=progress

echo "== compressing"
xz -T0 -6 -f "$OUT"
sha256sum "$OUT.xz" > "$OUT.xz.sha256"
chown --reference="$OUT_DIR" "$OUT.xz" "$OUT.xz.sha256"
ls -l "$OUT.xz"
echo "== done. Flash with: xz -dc $(basename "$OUT").xz | sudo dd of=/dev/sdX bs=4M conv=fsync"
