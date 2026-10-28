#!/bin/bash
# Debug helper for boxes with no serial console (run on the PC as root).
#   sudo ./athena-sd-debug.sh write /dev/sdX bootloader.bin  - write bootloader, clear the SPL log
#   sudo ./athena-sd-debug.sh read  /dev/sdX                 - show the SPL log the box left behind
set -euo pipefail

LOG_SECTOR=2048   # 1 MiB into the card, written by the debug SPL
cmd=${1:?usage: $0 write|read /dev/sdX [bootloader.bin]}
DEV=${2:?usage: $0 write|read /dev/sdX [bootloader.bin]}

[ "$(id -u)" = 0 ] || { echo "run as root (sudo)" >&2; exit 1; }
case "$DEV" in *[0-9]) P=${DEV}p ;; *) P=$DEV ;; esac
[ "$(blkid -s LABEL -o value "${P}1" 2>/dev/null)" = BOOT ] ||
	{ echo "$DEV does not look like the Armbian card (no BOOT partition)" >&2; exit 1; }

case "$cmd" in
write)
	BIN=${3:?missing bootloader.bin}
	[ "$(dd if="$BIN" bs=1 skip=4 count=8 status=none)" = "eGON.BT0" ] ||
		{ echo "$BIN is not an Allwinner boot image" >&2; exit 1; }
	dd if="$BIN" of="$DEV" bs=1k seek=8 conv=fsync status=none
	dd if=/dev/zero of="$DEV" bs=512 seek=$LOG_SECTOR count=2 conv=fsync status=none
	echo "wrote $(basename "$BIN") and cleared the SPL log"
	;;
read)
	out=$(dd if="$DEV" bs=512 skip=$LOG_SECTOR count=2 status=none | tr -d '\0')
	if [ -z "$out" ]; then
		echo "SPL log is empty: the SPL never ran, or could not write to the card"
	else
		echo "$out"
	fi
	;;
*)
	echo "unknown command $cmd" >&2; exit 1 ;;
esac
