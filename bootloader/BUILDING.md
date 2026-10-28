# How the bootloaders were built

Both files are hybrids:

- the first `0xA000` bytes are a mainline U-Boot **SPL** (DRAM init) built with
  this board's RAM settings
- everything after `0xA000` is the **FIT** (TF-A + U-Boot proper) taken from the
  ophub Armbian image's `u-boot-*.bin`. ophub's patched U-Boot powers up the
  AC300 Ethernet PHY, which mainline U-Boot does not do.

```sh
dd if=mainline/u-boot-sunxi-with-spl.bin of=hybrid.bin bs=1 count=$((0xA000))
dd if=ophub-u-boot.bin of=hybrid.bin bs=1 skip=$((0xA000)) seek=$((0xA000))
```

TF-A: v2.13.0, `PLAT=sun50i_h616`.

## athena-p7 (H618, DDR3): `u-boot-athena-p7-ac300.bin`

U-Boot v2025.10, `transpeed-8k618-t_defconfig` with the vendor DRAM values
from the box's Android boot0:

```
CONFIG_DRAM_CLK=600
CONFIG_DRAM_SUNXI_CA_DRI=0x1c1c
CONFIG_DRAM_SUNXI_TPR0=0xc0001008
CONFIG_DRAM_SUNXI_TPR2=0x100
CONFIG_DRAM_SUNXI_TPR6=0x33808080
CONFIG_DRAM_SUNXI_TPR10=0x2f00f6
CONFIG_DRAM_SUNXI_TPR12=0xeddc7564
CONFIG_AXP_DCDC3_VOLT=1500
```

## eros-p1 (H313, LPDDR3): `u-boot-eros-p1-lpddr3-ac300.bin`

U-Boot master (2027.01-rc1, c267fa81d). **v2025.10 and older don't work** for
LPDDR3: they read the Vref from the wrong byte of TPR6 (fixed upstream in
5a24cc074, "fix LPDDR3 TPR6 parsing"). Config: `tanix_tx1_defconfig` with:

```
CONFIG_DRAM_CLK=600          # 720 is unstable on this box
CONFIG_AXP_DCDC2_VOLT=1120
```

The resulting DRAM values (from the Tanix TX1; the box's own vendor values did
not train):

```
CONFIG_DRAM_SUNXI_DX_ODT=0x06060606
CONFIG_DRAM_SUNXI_DX_DRI=0x0d0d0d0d
CONFIG_DRAM_SUNXI_CA_DRI=0x1919
CONFIG_DRAM_SUNXI_ODT_EN=0x9988eeee
CONFIG_DRAM_SUNXI_TPR6=0x2fb08080
CONFIG_DRAM_SUNXI_TPR10=0x402f4469
CONFIG_DRAM_SUNXI_TPR11=0x0e0f0d0d
CONFIG_DRAM_SUNXI_TPR12=0x11131213
CONFIG_AXP_DCDC3_VOLT=1200
```

## Debug bootloaders (`debug/`)

These were built with `../patches/u-boot-h616-dram-sweep-led-debug.patch`. The
patch blinks the box LED (PH5, blue when high) at each SPL stage and sweeps a
list of DRAM setting variants, without stopping on timeouts. It is useful on a
box with no serial console that only shows a black screen.

Pair them with marker files written by `fatwrite` in `boot.scr`, so you can
see how far the boot got. Don't log to the SD card from the SPL before DRAM
init; that hangs the SPL.

- `u-boot-athena-p7.bin`, `u-boot-transpeed.bin`: plain mainline builds
  (no AC300 init)
- `*-LED*`: LED-signalling SPLs
