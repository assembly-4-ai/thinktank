#!/bin/bash
set -e
mkdir -p build
rm -rf build/*

echo "Compiling core modules..."

# Core modules
nasm -f elf64 -I includes/ -o build/main_uefi_loader_pic.o core/main_uefi_loader_pic.asm
nasm -f elf64 -I includes/ -o build/pmm64_pic.o core/pmm64_pic.asm
nasm -f elf64 -I includes/ -o build/numa_pic.o core/numa_pic.asm
nasm -f elf64 -I includes/ -o build/idt64_pic.o core/idt64_pic.asm
nasm -f elf64 -I includes/ -o build/pic_pic.o core/pic_pic.asm
nasm -f elf64 -I includes/ -o build/keyboard_pic.o core/keyboard_pic.asm
nasm -f elf64 -I includes/ -o build/screen_gop.o core/screen_gop.asm
nasm -f elf64 -I includes/ -o build/paging64_uefi.o core/paging64_uefi.asm
nasm -f elf64 -I includes/ -o build/gdt_uefi.o core/gdt_uefi.asm
nasm -f elf64 -I includes/ -o build/pci.o drivers/pci.asm
nasm -f elf64 -I includes/ -o build/ahci.o drivers/ahci.asm
nasm -f elf64 -I includes/ -o build/fat32_runtime.o filesystem/fat32_runtime.asm
nasm -f elf64 -I includes/ -o build/shell.o shell/shell.asm
nasm -f elf64 -I includes/ -o build/error_pic.o core/error_pic.asm
nasm -f elf64 -I includes/ -o build/simple_font.o utils/simple_font.asm
nasm -f elf64 -I includes/ -o build/itoa64.o core/itoa64.asm
nasm -f elf64 -I includes/ -o build/compute_lib.o compute/compute_lib.asm
nasm -f elf64 -I includes/ -o build/ai_integration.o ai/ai_integration.asm
nasm -f elf64 -I includes/ -o build/ai_test_suite.o ai/ai_test_suite.asm
nasm -f elf64 -I includes/ -o build/ai_status.o ai/ai_status.asm
nasm -f elf64 -I includes/ -o build/hardware_accelerated_ai.o ai/hardware_accelerated_ai.asm
nasm -f elf64 -I includes/ -o build/gpu_discovery.o gpu/gpu_discovery.asm
nasm -f elf64 -I includes/ -o build/gpu_mmio.o gpu/gpu_mmio.asm
nasm -f elf64 -I includes/ -o build/gpu_dma.o gpu/gpu_dma.asm
nasm -f elf64 -I includes/ -o build/gpu_irq.o gpu/gpu_irq.asm
nasm -f elf64 -I includes/ -o build/gpu_compute.o gpu/gpu_compute.asm
nasm -f elf64 -I includes/ -o build/gpu_initialization.o gpu/gpu_initialization.asm
nasm -f elf64 -I includes/ -o build/gpu_test_suite.o gpu/gpu_test_suite.asm
nasm -f elf64 -I includes/ -o build/memory_leak_detection.o core/memory_leak_detection.asm
nasm -f elf64 -I includes/ -o build/time_stamp.o utils/time_stamp.asm
nasm -f elf64 -I includes/ -o build/ai_math_functions.o ai/ai_math_functions.asm
nasm -f elf64 -I includes/ -o build/ai_tensor_core.o ai/ai_tensor_core.asm
nasm -f elf64 -I includes/ -o build/ai_transformer_core.o ai/ai_transformer_core.asm
nasm -f elf64 -I includes/ -o build/ai_shell_interface.o ai/ai_shell_interface.asm
nasm -f elf64 -I includes/ -o build/pmm_utils.o core/pmm_utils.asm
nasm -f elf64 -I includes/ -o build/shell_utils.o utils/shell_utils.asm
nasm -f elf64 -I includes/ -o build/hex_utils.o utils/hex_utils.asm
nasm -f elf64 -I includes/ -o build/float_compare.o compute/float_compare.asm
nasm -f elf64 -I includes/ -o build/string_utils.o utils/string_utils.asm

ld -T uefi.lds -o build/arora_core.efi \
   build/main_uefi_loader_pic.o \
   build/pmm64_pic.o \
   build/numa_pic.o \
   build/idt64_pic.o \
   build/pic_pic.o \
   build/keyboard_pic.o \
   build/screen_gop.o \
   build/paging64_uefi.o \
   build/gdt_uefi.o \
   build/pci.o \
   build/ahci.o \
   build/fat32_runtime.o \
   build/shell.o \
   build/error_pic.o \
   build/simple_font.o \
   build/itoa64.o \
   build/compute_lib.o \
   build/ai_integration.o \
   build/ai_test_suite.o \
   build/ai_status.o \
   build/hardware_accelerated_ai.o \
   build/gpu_discovery.o \
   build/gpu_mmio.o \
   build/gpu_dma.o \
   build/gpu_irq.o \
   build/gpu_compute.o \
   build/gpu_initialization.o \
   build/gpu_test_suite.o \
   build/memory_leak_detection.o \
   build/time_stamp.o \
   build/ai_math_functions.o \
   build/ai_tensor_core.o \
   build/ai_transformer_core.o \
   build/ai_shell_interface.o \
   build/pmm_utils.o \
   build/shell_utils.o \
   build/hex_utils.o \
   build/float_compare.o \
   build/string_utils.o

echo "Core build complete. Creating disk image..."

dd if=/dev/zero of=build/arora_disk.img bs=1M count=64
mkfs.fat -F 32 build/arora_disk.img
mmd -i build/arora_disk.img ::/EFI
mmd -i build/arora_disk.img ::/EFI/BOOT
mcopy -i build/arora_disk.img build/arora_core.efi ::/EFI/BOOT/BOOTX64.EFI

echo "Disk image created. Running QEMU..."
qemu-system-x86_64 -bios /usr/share/ovmf/OVMF.fd -hda build/arora_disk.img -m 4G -smp 4
