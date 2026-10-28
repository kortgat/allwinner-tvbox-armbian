# Armbian for "UHD Streaming STB" TV boxes (Allwinner H618 / H313)

Ready-to-flash Armbian images, bootloaders and scripts for the cheap Allwinner
TV boxes sold as **"UHD Streaming STB"**. Stock Armbian or ophub images either
show a black screen or crash randomly on them, because their RAM settings do
not match these boards.

Based on ophub Armbian 26.11 (Ubuntu resolute, kernel 6.18.51-ophub), with:

- a U-Boot SPL using the board's own RAM settings, plus ophub's U-Boot (which
  powers up the AC300 Ethernet chip)
- a device tree with the right Ethernet (EMAC1 RMII, AC300 PHY) and USB ports
- boot.scr turning on the AC300 PHY's 24 MHz clock (PWM5 bypass), with
  `clk_ignore_unused` to keep it on
- both onboard Seekwave Wi-Fi drivers (DKMS) + firmware; the right one is picked
  from the chip's SDIO ID at boot, and the interface is always named `wifi0`
- a per-board Wi-Fi MAC and hostname (`armbian-xxxx`) derived from the SoC serial
- scripts to install from SD to the internal eMMC, and to back up / restore Android

What works: HDMI console, Ethernet (100 Mbit), onboard Wi-Fi, all USB ports,
CPU frequency scaling, eMMC. Not tested: Bluetooth, IR remote, audio, video
acceleration.

## Which box do I have?

Two different boards are sold under the same name and look identical. They
need different images. Check in Android first, under Settings > About, or:

```
adb shell getprop ro.product.device
```

| Android says | Board | SoC | RAM | Image | Bootloader | Wi-Fi |
|---|---|---|---|---|---|---|
| Android 12, `athena-p7` | athena-p7 | H618 | 2 GB DDR3 | `athena-h618-armbian-golden-*.img.xz` | `u-boot-athena-p7-ac300.bin` | SWT6621S |
| Android 10, `eros-p1` | eros-p1 | H313 | 2 GB LPDDR3 | `eros-h313-lpddr3-armbian-golden-*.img.xz` | `u-boot-eros-p1-lpddr3-ac300.bin` | SV6160 or SWT6621S |

eros-p1 boxes come with either Wi-Fi chip; the eros-p1 image detects which one
is fitted. The wrong image just shows a black screen; nothing gets damaged. If unsure,
try one, then the other.

The images are on the [Releases](../../releases) page (too big for git).

You need: an SD card of 8 GB or more, an Ethernet cable (easiest; log in over
SSH) or an HDMI screen + USB keyboard, and a Linux PC.

## Install on a new box

### 1. Write the image to an SD card (on the PC)

Find the card with `lsblk`. Double-check the device name; `dd` overwrites
whatever you give it.

```sh
sha256sum -c eros-h313-lpddr3-armbian-golden-20261028.img.xz.sha256
xz -dc eros-h313-lpddr3-armbian-golden-20261028.img.xz | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress
```

(Use the athena-h618 image for an athena-p7 box.) balenaEtcher can also write
the `.img.xz` directly.

**Write a fresh copy before every new box.** A card that has booted once holds
that box's hostname, MAC address, passwords and Wi-Fi settings.

### 2. First boot from the SD card

Put the card in the box, plug in Ethernet (and/or HDMI + keyboard), and power
on. The box always boots from the SD card when one is inserted.

Log in as `root` / `1234`, on the console or with `ssh root@<box-ip>`. The IP is
in your router's DHCP list, with hostname `armbian-xxxx`. The Armbian wizard asks
for a new root password and a user account. The first boot also grows the
filesystem and sets the box's own hostname and Wi-Fi MAC.

Optional Wi-Fi now (it gets copied to the eMMC in step 4):

```sh
nmcli dev wifi connect '<SSID>' ifname wifi0 password '<password>'
```

(or use `nmtui`).

### 3. Optional: back up Android (step 4 erases it)

Run these on the PC while the box is booted from the SD card. It takes 10-15
minutes and 2-3 GB of disk. Replace `<box-ip>`; each command asks for the box's
root password.

```sh
mkdir android-backup-<boxname> && cd android-backup-<boxname>
ssh root@<box-ip> 'sfdisk -d /dev/mmcblk2' > partition-table.txt
ssh root@<box-ip> 'cat /dev/mmcblk2boot0' > mmcblk2boot0.bin
ssh root@<box-ip> 'cat /dev/mmcblk2boot1' > mmcblk2boot1.bin
ssh root@<box-ip> 'dd if=/dev/mmcblk2 bs=4M status=none | gzip -1' > emmc-full.img.gz
```

Check that the backup really matches the eMMC. Both commands must print the
same hash:

```sh
ssh root@<box-ip> 'sha256sum /dev/mmcblk2'
gzip -dc emmc-full.img.gz | sha256sum
```

Keep this folder safe; it is the only way back to Android. It is specific to
that box, so don't share it (it contains the box's Android data and keys).

### 4. Install Armbian on the eMMC (ERASES Android)

On the box, as root, with the bootloader for its type:

```sh
# eros-p1
/root/athena/athena-install-emmc.sh /root/athena/u-boot-eros-p1-lpddr3-ac300.bin
# athena-p7
/root/athena/athena-install-emmc.sh /root/athena/u-boot-athena-p7-ac300.bin
```

Each image only carries its own type's bootloader in `/root/athena`. The
script wipes the eMMC, copies the running system (including the user, password
and Wi-Fi you set up) and writes the bootloader. It ends with
`bootloader verified`. Then:

```sh
poweroff
```

Remove the SD card and power on. The box now boots Armbian from the eMMC.
Check with `findmnt /` (it should show `/dev/mmcblk2p2`).

## Restoring Android

1. Boot the box from an Armbian SD card for its type. A freshly written image
   is fine; do the first login so SSH works.
2. From the PC, in the backup folder:
   ```sh
   gzip -dc emmc-full.img.gz | ssh root@<box-ip> 'dd of=/dev/mmcblk2 bs=4M conv=fsync'
   ```
   Optional check: `ssh root@<box-ip> 'sha256sum /dev/mmcblk2'` must match the
   hash you recorded at backup time.
3. `ssh root@<box-ip> poweroff`, remove the SD card and power on. Android's own
   bootloader is inside the image (at 8 KiB), so nothing else is needed.

The `mmcblk2boot0/1` files are not used by these boxes and normally do not need
restoring. A backup only restores onto the box it came from, or an identical
one with the same eMMC size.

## Making a new golden image

After changing the SD system (updates, extra packages):

1. On the box, booted from the SD card:
   ```sh
   /root/athena/athena-generalize.sh "$(awk -F: '$1=="root"{print $2}' /etc/shadow)"
   ```
   The argument is the password hash new boxes start with. On a card still
   using `1234`, this command passes exactly that. The script removes users,
   Wi-Fi, SSH keys and logs, then powers off.
2. Put the card in the PC and, from this repo:
   ```sh
   sudo scripts/athena-make-image.sh /dev/sdX eros-h313-lpddr3-armbian-golden
   ```
   Use the prefix `athena-h618-armbian-golden` (the default) for the DDR3 box.
   This writes `<prefix>-<date>.img.xz` and a `.sha256` file to the current
   directory.

## Repository layout

| Path | What |
|---|---|
| `scripts/athena-install-emmc.sh` | copy the running SD system to the eMMC (on the box) |
| `scripts/athena-generalize.sh` | reset an SD system to first-boot state (on the box) |
| `scripts/athena-make-image.sh` | shrink, image and compress a generalized card (PC, sudo) |
| `scripts/athena-sd-debug.sh` | write a bootloader to a card / read a debug log (PC, sudo) |
| `bootloader/u-boot-athena-p7-ac300.bin` | DDR3 bootloader |
| `bootloader/u-boot-eros-p1-lpddr3-ac300.bin` | LPDDR3 bootloader |
| `bootloader/debug/` | RAM-debug bootloaders (LED blink codes) for bringing up unknown boxes |
| `bootloader/BUILDING.md` | how the bootloaders were built |
| `dtb/` | device trees (`sun50i-h618-vontar-h618-usb.dtb` for athena-p7, `sun50i-h313-eros-p1.dtb` for eros-p1) |
| `patches/swt6621s-ophub-6.18-cfg80211.patch` | SWT6621S Wi-Fi driver ([Novice-PG/swt6621s](https://github.com/Novice-PG/swt6621s) 1.0.3) ported to this kernel; its Bluetooth module installs as `skwbt_lite` so it can sit beside the SV6160 one |
| `patches/sv6160-ea6x21-ophub-6.18.patch` | SV6160 Wi-Fi driver ([joilg/ea6x21-dkms](https://github.com/joilg/ea6x21-dkms) b193d8b) ported to this kernel |
| `rootfs/` | files the images add under `/etc`: the udev rule and modprobe config that pick the Wi-Fi driver by SDIO ID (`1FFE:6621` = SWT6621S, `0000:0000` = SV6160), and the ordering that writes the Wi-Fi MAC before udev runs |
| `patches/u-boot-h616-dram-sweep-led-debug.patch` | the U-Boot debug SPL used to find working RAM settings |

A bootloader can be written to a card or eMMC by hand at 8 KiB:
`dd if=u-boot-....bin of=/dev/sdX bs=1k seek=8 conv=fsync`.

## Notes and known issues

- **Armbian updates that rewrite `/boot/boot.cmd`** drop the AC300 clock lines,
  and Ethernet stops working. Re-add these before the `booti` line and rebuild:
  ```
  mw.l 0x030017ac 0x00010001
  mw.l 0x0300a028 0x00000050
  mw.l 0x0300a040 0x00200020
  mw.l 0x0300a080 0x00000020
  ```
  ```sh
  mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr
  ```
- **A new kernel needs the Wi-Fi driver rebuilt.** DKMS does it automatically
  if the matching kernel headers are installed.
- **SV6160 Wi-Fi:** never `rmmod skw_sdio`. The driver crashes on unload and
  the next shutdown hangs for minutes. Reboot instead.
- eros-p1 RAM runs at 600 MHz; 720 MHz is unstable.
- The SD card always boots first. To boot the eMMC, take the card out.
