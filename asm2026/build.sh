#!/bin/bash
set -e

# asm2026 build script

# Go to script directory
cd "$(dirname "$0")"

mkdir -p build

echo "Compiling asm2026..."
# Use win64 format to produce a PE COFF object
nasm -f win64 -I include/ -o build/main.obj src/main.asm

echo "Linking asm2026..."
# Link into a real PE32+ EFI application
ld -m i386pep --subsystem 10 -e _start -o build/asm2026.efi build/main.obj

echo "Build successful: asm2026/build/asm2026.efi"
