# FDC+3712 transition plan

The physical IMSAI has now validated `3712BOOT.COM` v0.2: all 51 CP/M 2.2 system sectors are staged at `8000H-997FH`, the CCP and BIOS signatures match, and the full image checksum is `54B0H`.

The transition is intentionally split into conservative steps.

## Step 1: staged BIOS patch preparation

`3712PREP.COM` operates only on the already staged image. It verifies the original image, checks every byte at 19 planned BIOS patch sites, redirects those staged BIOS references to a future RAM service layer at `C000H`, verifies the replacements, and checks the resulting staged-image checksum (`4F80H`). It does not touch the active CP/M 3 system, does not copy the staged image to its final `A600H-BF7FH` addresses, and does not transfer control.

The planned RAM service vector table is:

- `C003H` cold start
- `C006H` warm start
- `C009H` home
- `C00CH` select drive
- `C00FH` set track
- `C012H` set sector
- `C015H` set DMA
- `C018H` read
- `C01BH` write (initial transition will remain read-only)
- `C01EH` console status
- `C021H` console input
- `C024H` console output
- `C027H` list status

For the first boot transition, console I/O will be kept deliberately simple and use the already proven S100Computers Console I/O board at ports `00H/01H`. Front-panel selectable Console I/O / Serial I/O / MIO support can be added after the CP/M 2.2 handoff itself is proven.

## Later step: irreversible handoff

Only after the staged patch preparation is physically validated will a separate transition utility install the RAM service layer, copy the patched staged image from `8000H-997FH` to `A600H-BF7FH`, establish CP/M page-zero vectors, and enter the 48K CP/M 2.2 system. Once that copy begins, return to the old CP/M 3 environment is intentionally impossible.
