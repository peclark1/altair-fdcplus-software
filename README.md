# Altair FDC+ Software

Utilities and experimental software for the Altair FDC+, with an initial focus on the firmware 1.8 **Drive Type 8** personality (iCOM/Pertec FD3712 compatible, 8-inch SSSD IBM-3740 media).

The first goal is intentionally conservative: prove reliable **read-only** access to a Shugart SA-800/SA-801 from CP/M before changing the IMSAI master ROM.

## Initial plan

1. Build a CP/M `.COM` diagnostic that talks directly to the FDC+3712 registers at ports `08H`/`09H`.
2. Reset/select/restore drive 0 and report controller status.
3. Read track 0, sector 1 (128 bytes) and display a hex/ASCII dump.
4. Recognize the known first sector of Mike Douglas's `CPM22v1.0-FDC+3712-48K.dsk` image.
5. After sector reads are proven, extend the utility to arbitrary track/sector reads.
6. Only then build a CP/M bootstrap utility and finally move the proven loader into the IMSAI 4K monitor ROM.

No write or format commands are included in the first diagnostic.

## Reference implementation

The initial controller sequence is derived from Mike Douglas's FDC+3712 `PROM.ASM` supplied with the FDC+3712 software package. The utility follows the same controller commands and `08H`/`09H` register mapping, while adding timeouts so a missing/not-ready drive cannot hang CP/M forever.
