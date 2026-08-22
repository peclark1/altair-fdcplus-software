# Altair FDC+ Software

Utilities and experimental software for the Altair FDC+, with an initial focus on firmware 1.8 **Drive Type 8** (iCOM/Pertec FD3712 compatible, 8-inch SSSD IBM-3740 media).

The development approach is intentionally conservative: prove reliable **read-only** access to the Shugart SA-800/SA-801 from CP/M before changing the IMSAI master ROM.

## Physical validation

The first `3712TEST.COM` build was successfully tested on the physical IMSAI with:

- FDC+ firmware 1.8
- Drive Type 8
- Shugart SA-800 configured per the FDC+ manual
- Mike Douglas's `CPM22v1.0-FDC+3712-48K.dsk` image written to an 8-inch floppy with the existing `digitalsystems.cpm135` Greaseweazle profile
- CP/M 3 booted from IDE/CF while the diagnostic accessed the FDC+ directly

Observed status was `40H` for both restore and read; none of Mike's defined error bits were set. Track 0 / sector 1 was read correctly and the known boot-sector signature matched on the first physical test.

That proves the basic IMSAI -> S-100 -> FDC+ Drive Type 8 -> SA-800 -> IBM-3740 media read path.

## 3712TEST.COM v0.2

`3712TEST.COM` runs as a normal CP/M program and talks directly to the FDC+3712 registers at ports `08H` and `09H`; CP/M BDOS is used only for console output.

Version 0.2 remains completely read-only and adds two useful tests:

1. **Arbitrary track/sector reads** from the command line.
2. A **direct CP/M directory listing** read through the FDC+3712 itself.

Usage:

```text
A>3712TEST
A>3712TEST 0 26
A>3712TEST 1 1
A>3712TEST 40 1
A>3712TEST 76 26
```

Track and sector numbers are decimal. Valid ranges are track `0-76` and sector `1-26`. With no arguments, the program defaults to track 0 / sector 1.

For the requested sector, the program:

1. Resets the FDC+3712 controller.
2. Restores drive 0 to track 0.
3. Seeks to the requested track and selects the requested sector.
4. Reports raw and decoded controller status.
5. Reads the full 128-byte sector and displays it as hex/ASCII.
6. If the requested sector is T0/S1, compares its first 16 bytes with Mike Douglas's known boot-sector signature.

It then reads and displays the CP/M directory directly from the floppy.

### Directory layout

The directory reader follows the disk parameters in Mike Douglas's `BIOS.ASM`:

- 26 sectors/track
- 128-byte sectors
- two reserved system tracks (`OFF=2`)
- 64 directory entries (`DRM=63`)
- 1K allocation blocks
- two directory blocks (`AL0=C0H`)
- standard 8-inch SSSD CP/M interleave/skew of 6

The directory therefore occupies 16 logical sectors at the beginning of track 2. Version 0.2 translates those logical sectors to the physical sector IDs used by Mike's BIOS and reads them directly through the FDC+3712.

Only active CP/M user areas 0-15 are displayed. Since this disk has `EXM=0`, the listing displays extent-zero entries so multi-extent files appear once, similar to CP/M `DIR`.

For Mike's supplied CP/M image, the listing should include files such as `ASM.COM`, `DDT.COM`, `FORMAT.COM`, `MBASIC.COM`, `MOVCPM.COM`, `PIP.COM`, `STAT.COM`, and `SYSGEN.COM`.

There are **no write or format commands** in this program.

## Known boot-sector signature

For `CPM22v1.0-FDC+3712-48K.dsk`, track 0 / sector 1 starts with:

```text
31 F6 00 0E 00 CD 0C F4 0E 00 CD 0F F4 21 80 A6
```

A signature match proves much more than a READY indication: the controller interface, drive selection, restore/seek, IBM-3740 sector addressing, FM read path, FIFO transfer, and physical disk contents all agree with the reference image.

## Build on Ubuntu

Install Pasmo once:

```sh
sudo apt update
sudo apt install pasmo
```

Then:

```sh
git clone https://github.com/peclark1/altair-fdcplus-software.git
cd altair-fdcplus-software
git switch feature/fdc3712-test
make verify
```

The result is:

```text
build/3712TEST.COM
```

Transfer that `.COM` file to the existing IDE/CF CP/M 3 system using the normal host-transfer workflow.

## Reference implementation

The controller constants and command sequence are derived from Mike Douglas's FDC+3712 `PROM.ASM` v1.0 supplied in the FDC+3712 software package:

- command/status/data input: port `08H`
- data output: port `09H`
- reset: `81H`
- restore: `0DH`
- load configuration: `15H`
- set drive/sector: `21H`
- set track: `11H`
- seek: `09H`
- read sector: `03H`
- read FIFO byte: `40H`
- shift FIFO: `41H`

The test intentionally does not depend on Mike's PROM jump table at `F400H`, because that address is occupied by the IMSAI target monitor ROM.

## Planned progression

Once v0.2 verifies seeks across the disk and the directory can be read reliably:

1. Build a RAM-resident FDC+3712 service layer and `3712BOOT.COM` bootstrap utility.
2. Load Mike's CP/M system directly from the 8-inch floppy while initially running under IDE/CF CP/M 3.
3. Adapt the booted CP/M image to the IMSAI console configuration.
4. Only after the software path is proven, replace the obsolete CDBL section in the 4K master ROM with the tested FDC+3712 loader.
