# 3712HAND first-boot sequence

`3712HAND.COM` is the first intentionally non-returning transition into the supplied 48K CP/M 2.2 image. Do not run it unless `3712BOOT` and `3712PREP` have both passed immediately beforehand.

Bench sequence:

```text
A>3712BOOT
A>3712PREP
A>3712HAND
```

`3712HAND` first verifies the prepared `4F80H` staged checksum and the prepared cold/warm vectors. It then requires an explicit `B` confirmation. Before touching the active CP/M system it finalizes the staged cold/warm semantics and requires checksum `5005H`.

After the final confirmation message, return to the previous CP/M is intentionally impossible. The utility disables interrupts, installs the C000H service layer, copies `8000H-997FH` to `A600H-BF7FH`, verifies the final `5005H` checksum, and enters the C000H cold-start service.

The v0.1 service layer is intentionally read-only: BIOS WRITE returns an error and issues no FDC+ write command. Console support for this first handoff is limited to the S100Computers Console I/O V2 board at ports `00H/01H`.

The C000H service preserves Mike Douglas's PROM-style warm-boot behavior: the BIOS warm vector remains at `BC92H`, and its patched internal call at `BC95H` invokes the RAM `pWARM` replacement at `C006H` to reload CCP+BDOS from drive 0.
