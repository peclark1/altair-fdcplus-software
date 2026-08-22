# 3712PREP bench sequence

Transfer `3712BOOT.COM` and `3712PREP.COM` to CP/M before staging the image. Then run them back-to-back without running another transient program between them:

```text
A>3712BOOT
A>3712PREP
```

`3712PREP` expects the original staged image checksum `54B0H`, validates 19 exact BIOS patch sites, applies only RAM changes inside `8000H-997FH`, and expects the patched staged-image checksum `4F80H`.

No disk write, final-address copy, or control transfer is performed by `3712PREP`.
