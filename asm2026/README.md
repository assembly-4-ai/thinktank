# asm2026

Minimal UEFI project in x64 NASM assembly.

## Project Structure

- `src/`: Source code (`main.asm`)
- `include/`: Include files (`efi.inc`)
- `build/`: Build artifacts
- `build.sh`: Build script

## How to build

Ensure `nasm` and `ld` (with `i386pep` support) are in your PATH, then run:

```bash
bash build.sh
```

The resulting UEFI executable will be in `build/asm2026.efi`.

## Project Goals

- Explore bare-metal UEFI development using NASM.
- Adhere to Microsoft x64 ABI for UEFI services.
- Foundation for optimized OS components.
