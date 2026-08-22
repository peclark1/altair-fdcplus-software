# FDC+3712 transition plan

The physical IMSAI has validated `3712BOOT.COM` v0.2: all 51 CP/M 2.2 system sectors are staged at `8000H-997FH`, the CCP and BIOS signatures match, and the full image checksum is `54B0H`.

It has also validated `3712PREP.COM` v0.1: all 19 source patch sites match, all 19 replacement sites verify, and the prepared staged-image checksum is `4F80H`.

The transition is intentionally split into conservative steps.

## Step 1: staged BIOS patch preparation

`3712PREP.COM` operates only on the already staged image. It verifies the original image, checks every byte at 19 planned BIOS patch sites, redirects the staged BIOS disk/console references toward a RAM service layer at `C000H`, verifies the replacements, and checks the resulting staged-image checksum (`4F80H`). It does not touch the active CP/M 3 system, does not copy the staged image to its final `A600H-BF7FH` addresses, and does not transfer control.

## Step 2: atomic handoff

`3712HAND.COM` first verifies the prepared `4F80H` stage while the old CP/M is still completely intact. It requires an explicit `B` confirmation before doing anything non-returning.

Two prepared BIOS vectors need different semantics during the real boot than during the isolated PREP test:

- the BIOS cold vector at `BC00H` becomes `JMP C000H`, the full new cold-start entry;
- the BIOS warm vector at `BC03H` is restored to the supplied BIOS `wBoot` routine at `BC92H`;
- the already-prepared internal call at `BC3CH` remains `CALL C003H`, where `C003H` provides the PROM-style `pCOLD` service;
- the already-prepared internal call at `BC95H` remains `CALL C006H`, where `C006H` provides the PROM-style `pWARM` reload service.

Those two final vector adjustments change the staged checksum from `4F80H` to `5005H`; `3712HAND` verifies `5005H` before crossing the irreversible point.

The C000H service vector table is:

- `C000H` full cold start
- `C003H` PROM-style `pCOLD`
- `C006H` PROM-style `pWARM`
- `C009H` home
- `C00CH` select drive
- `C00FH` set track
- `C012H` set sector
- `C015H` set DMA
- `C018H` read
- `C01BH` write (v0.1 returns error; no disk write command is issued)
- `C01EH` console status
- `C021H` console input
- `C024H` console output
- `C027H` list status

After the irreversible point, `3712HAND` uses no BDOS calls. It disables interrupts, runs on its own low-memory stack, installs the service layer at `C000H`, verifies that copy, copies the prepared system from `8000H-997FH` to `A600H-BF7FH`, verifies the final `5005H` image checksum, and jumps to `C000H`.

For the first physical handoff, console I/O is deliberately limited to the proven S100Computers Console I/O board at ports `00H/01H`. Front-panel selectable Console I/O / Serial I/O / MIO support can be added after the CP/M 2.2 handoff itself is proven.

Disk writes are also deliberately disabled for the first boot. Once cold boot, directory reads, program loads, and warm boot are all proven, a later change can add the original PROM-style write path and then reintroduce the broader console-selection logic.
