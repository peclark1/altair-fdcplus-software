# Altair FDC+ Software

Utilities and experimental software for the Altair FDC+, with an initial focus on firmware 1.8 **Drive Type 8** (iCOM/Pertec FD3712 compatible, 8-inch SSSD IBM-3740 media).

The first goal is intentionally conservative: prove reliable **read-only** access to a Shugart SA-800/SA-801 from CP/M before changing the IMSAI master ROM.

## 3712TEST.COM

`3712TEST.COM` is the first hardware diagnostic. It runs as a normal CP/M program and talks directly to the FDC+3712 registers at ports `08H` and `09H`; CP/M BDOS is used only for console output.

The test performs only these operations:

1. Reset the FDC+3712 controller.
2. Select drive 0 / sector 1.
3. Restore drive 0 to track 0.
4. Report the raw controller status and decoded status flags.
5. Read track 0 / sector 1 into a 128-byte RAM buffer.
6. Display the complete sector as hex and printable ASCII.
7. Compare the first 16 bytes against track 0 / sector 1 of Mike Douglas's `CPM22v1.0-FDC+3712-48K.dsk` image.
8. Return normally to CP/M.

There are **no write or format commands** in this program.

The known boot-sector signature is:

```text
31 F6 00 0E 00 CD 0C F4 0E 00 CD 0F F4 21 80 A6
```

A signature match proves much more than a READY indication: the controller interface, drive selection, restore/seek, IBM-3740 sector addressing, FM read path, FIFO transfer, and the physical disk contents all agree with the reference image.

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

## First physical test

Prepare an 8-inch floppy from Mike Douglas's `CPM22v1.0-FDC+3712-48K.dsk` image using Greaseweazle, then boot the IMSAI normally from IDE/CF into CP/M 3.

With the FDC+ powered up in firmware 1.8 Drive Type 8 and the prepared disk loaded in drive 0, run:

```text
A>3712TEST
```

Expected success looks approximately like:

```text
FDC+3712 TEST v0.1 - READ ONLY
Drive 0, IBM-3740 track 0 sector 1

Reset/select/restore: status=..
Read T00/S01: status=..

128-byte sector dump:
00: 31 F6 00 0E 00 CD 0C F4 0E 00 CD 0F F4 21 80 A6 ...
...
PASS: Mike Douglas CP/M boot-sector signature matched.
```

The diagnostic includes a bounded BUSY timeout, unlike the original PROM routine, so a missing or incorrectly configured drive/controller should return to CP/M rather than hang indefinitely.

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

After this single-sector test is proven on the physical IMSAI:

1. Add arbitrary track/sector read testing.
2. Verify seeks to several tracks and reads across the disk.
3. Build a RAM-resident FDC+3712 service layer and CP/M bootstrap utility.
4. Adapt the booted CP/M image to the IMSAI console configuration.
5. Only after the software path is proven, replace the obsolete CDBL section in the 4K master ROM with the tested FDC+3712 loader.
