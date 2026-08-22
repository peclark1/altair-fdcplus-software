# 3712HAND first-boot sequence

`3712HAND.COM` is the first intentionally non-returning transition into the supplied 48K CP/M 2.2 image. Do not perform the real boot unless `3712BOOT` and `3712PREP` have both passed immediately beforehand.

Bench sequence:

```text
A>3712BOOT
A>3712PREP
A>3712HAND
```

`3712HAND` first verifies the prepared `4F80H` staged checksum and the prepared cold/warm vectors.

## Safe first bench test

At the first prompt, press `P`. This changes only the staged image's final cold/warm vector semantics and verifies that its checksum becomes `5005H`. Active CP/M is still untouched.

After `5005 PASS`, `3712HAND` presents a second prompt. For the **first physical test**, press any key **other than `B`** (for example `X`). The program restores the original `4F80H` prepared vectors and returns safely to the current CP/M.

Expected safe-test sequence:

```text
Prepared checksum 8000-997F:  4F80  PASS
Prepared cold/warm vectors:   PASS
...
Final staged checksum:         5005  PASS
...
Aborted after 5005 test. Prepared 4F80 vectors restored;
current CP/M was not changed.
```

This P-then-X test validates the complete final staged-image transformation without crossing the irreversible boundary.

## Real handoff

Only after the safe test has passed, run `3712HAND` again. Press `P`, verify `5005 PASS`, and then press `B` at the second prompt.

After `B`, return to the previous CP/M is intentionally impossible. The utility disables interrupts, installs the C000H service layer, verifies that copy, copies `8000H-997FH` to `A600H-BF7FH`, verifies the final `5005H` checksum, and enters the C000H cold-start service.

The v0.1 service layer is intentionally read-only: BIOS WRITE returns an error and issues no FDC+ write command. Console support for this first handoff is limited to the S100Computers Console I/O V2 board at ports `00H/01H`.

The C000H service preserves Mike Douglas's PROM-style warm-boot behavior: the BIOS warm vector remains at `BC92H`, and its patched internal call at `BC95H` invokes the RAM `pWARM` replacement at `C006H` to reload CCP+BDOS from drive 0.
