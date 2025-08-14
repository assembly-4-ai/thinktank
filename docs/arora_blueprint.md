Here is the FINAL, definitive plan for Project Arora. This plan is to be followed autonomously and as fiat by all coders. It integrates all previously established principles, the core development blueprint, and the detailed hardware reference.

This is not merely a suggestion; it is the unambiguous roadmap for achieving a bare-metal AI.

Project Arora: The Grand Plan for Bare-Metal AI (Fiat Plan)
Foreword: The Unwavering Mandate
Project Arora is a zero-compromise, bare-metal endeavor. Every instruction, every data structure, every interaction with hardware will be crafted in x64 Assembly (NASM). There are no external libraries, no operating system services beyond the absolute minimum UEFI boot services to initiate the kernel. The goal is ultimate speed and efficiency, achieved by direct hardware mastery.

This document is the single source of truth for all development activities. All instructions herein are fiat.

Phase 0: The Forge (Initial Toolchain & Environment Setup)
Objective: Establish the foundational development environment, ensuring compliance and readiness.

0.1 NASM Installation:
Action: Install the latest stable version of NASM.
Verification: nasm -v displays version.
0.2 GNU Linker (ld) Installation:
Action: Install GNU Binutils (which includes ld). Ensure it supports x64 linking for PE32+ (EFI) output.
Verification: ld -v displays version.
0.3 QEMU with OVMF Setup:
Action: Install QEMU. Acquire the OVMF firmware (OVMF.fd or similar).
Verification: Can successfully launch QEMU with OVMF.
qemu-system-x86_64 -bios /path/to/OVMF.fd -m 512M (or higher)
0.4 Text Editor & File Encoding:
Action: Configure your chosen text editor (e.g., VS Code, Sublime Text, Vim) to:
Use UTF-8 encoding without BOM (Byte Order Mark).
Use Unix (LF) line endings.
Disable automatic whitespace trimming on empty lines.
Verification: Create a test .asm file and verify encoding and line endings.
0.5 Initial Build Script (Makefile - Fiat Structure):
Action: Create a Makefile with the following targets. This is the only approved build process.
# Project Arora Build System - FIAT Makefile

NASM    := nasm
LD      := ld
QEMU    := qemu-system-x86_64
OVMF    := /path/to/OVMF.fd # <-- Adjust this path!

BOOTLOADER_ASM  := bootloader.asm
BOOTLOADER_OBJ  := $(BOOTLOADER_ASM:.asm=.obj)
EFI_TARGET      := AroraLoader.efi

# Linker script will be added in a later phase.
LINKER_SCRIPT   := linker.ld 

.PHONY: all run clean debug

all: $(EFI_TARGET)

# Rule to assemble the bootloader
$(BOOTLOADER_OBJ): $(BOOTLOADER_ASM)
    $(NASM) -f win64 $< -o $@

# Rule to link the EFI executable (PLACEHOLDER - will be updated)
# This will require a specific linker script later.
$(EFI_TARGET): $(BOOTLOADER_OBJ)
    # This is a temporary linking command.
    # A full custom linker.ld will be used later.
    # This might require manual entry point settings depending on your ld version.
    $(LD) -o $@ $< -nostdlib --subsystem 10 ; # /SUBSYSTEM:EFI_APPLICATION for PE32+

# Run in QEMU
run: $(EFI_TARGET)
    @echo "Running $(EFI_TARGET) in QEMU..."
    $(QEMU) -bios $(OVMF) -m 2G -serial stdio -hda fat:rw:./AroraFS -net none -cpu host -smp 1,cores=1,threads=1 -device ahci,id=ahci0 -device ide-hd,bus=ahci0.0,drive=disk0 -drive file=AroraDisk.img,if=none,id=disk0 -debugcon file:debug.log

# Clean generated files
clean:
    @echo "Cleaning Project Arora build artifacts..."
    rm -f $(BOOTLOADER_OBJ) $(EFI_TARGET) debug.log AroraDisk.img

# Debug with GDB (requires -s and -S in QEMU, and gdb client)
debug: $(EFI_TARGET)
    @echo "Starting QEMU for GDB debugging..."
    $(QEMU) -bios $(OVMF) -m 2G -serial stdio -hda fat:rw:./AroraFS -net none -cpu host -smp 1,cores=1,threads=1 -device ahci,id=ahci0 -device ide-hd,bus=ahci0.0,drive=disk0 -drive file=AroraDisk.img,if=none,id=disk0 -debugcon file:debug.log -s -S # -s: listen for gdb, -S: freeze CPU at start

# Placeholder for creating AroraDisk.img and AroraFS directory
# This will be refined as the FAT32 driver is developed.
# For now, manually create AroraFS/ and an empty AroraDisk.img (e.g., dd if=/dev/zero of=AroraDisk.img bs=1M count=100)
Pre-Requisite for run and debug: Manually create an empty directory named AroraFS in your project root for QEMU's FAT filesystem. For AroraDisk.img, create a dummy file: dd if=/dev/zero of=AroraDisk.img bs=1M count=100 (on Linux/WSL) or create a large empty file (Windows).
Phase 1: The Ascent (UEFI Loader & Essential System Information)
Objective: Successfully execute the fiat UEFI loader, obtain critical system details from UEFI, and transition gracefully to bare-metal control.

1.1 Deploy Fiat UEFI Loader:
Action: Place the bootloader.asm (from previous output) in the project root.
Action: Assemble it (make $(BOOTLOADER_OBJ)).
Action: Link it (using the placeholder make $(EFI_TARGET)). You may need to create a dummy linker.ld for this initial stage or use direct ld flags that specify entry point (-e _start).
Action: Ensure the AroraLoader.efi is placed in an appropriate directory structure for QEMU to boot from (e.g., AroraFS/EFI/BOOT/BOOTX64.EFI).
Verification: Run QEMU (make run). Observe "Project Arora: UEFI Loader Initialized..." and "Attempting bare-metal transition..." printed to the QEMU console/debug log. The system should then halt with "ERROR: ExitBootServices FAILED!" (expected, as dummy values are used).
1.2 Implement UEFI Boot Services Wrappers:
Action: Within efi_main (or a new assembly file linked in), implement direct assembly wrappers for the following UEFI Boot Services, following the x64 calling convention and SystemTable offsets from the Master Manual (UEFI Spec v2.10):
UefiAllocatePages (Offset 0x118 in EFI_BOOT_SERVICES)
UefiGetMemoryMap (Offset 0x180 in EFI_BOOT_SERVICES) - This is critical and complex. Must handle EFI_BUFFER_TOO_SMALL by re-calling with a larger allocated buffer.
UefiLocateProtocol (Offset 0x278 in EFI_BOOT_SERVICES)
UefiHandleProtocol (Offset 0x100 in EFI_BOOT_SERVICES)
UefiOpenFile (Requires EFI_SIMPLE_FILE_SYSTEM_PROTOCOL and EFI_FILE_PROTOCOL)
UefiReadFile
UefiCloseFile
Verification: Implement small tests for each wrapper. For example, call UefiAllocatePages for a few pages and print the returned address.
1.3 ACPI Table Parsing:
Action: Implement parse_acpi_tables:
RSDP Discovery: Scan memory ranges (EBDA, 0xF0000-0xFFFFF) for "RSD PTR " signature. Verify checksum.
XSDT/RSDT Parsing: Parse XSDT (preferred) or RSDT to find pointers to other ACPI tables. Verify checksums.
MADT (APIC) Parsing: Extract LAPIC base addresses and I/O APIC configurations.
SRAT (NUMA) Parsing: Extract NUMA node physical memory ranges and APIC affinities.
MCFG (PCIe ECAM) Parsing: Get the base address for PCI Express Configuration Space.
Action: Store all extracted ACPI data in Arora's own, self-defined global data structures.
Verification: Print discovered ACPI table addresses, LAPIC/IOAPIC info, and MCFG base address to the debug output.
1.4 GOP (Graphics Output Protocol) Information Retrieval:
Action: Use UefiLocateProtocol and UefiHandleProtocol to retrieve the EFI_GRAPHICS_OUTPUT_PROTOCOL interface.
Action: Extract and store the framebuffer physical address, pixel width, height, and pixel format from the GOP structure into Arora's global data.
Verification: Print the extracted GOP information.
1.5 Arora Image Information Retrieval:
Action: Use UefiLocateProtocol to find EFI_LOADED_IMAGE_PROTOCOL_GUID associated with Arora's own image handle.
Action: Extract and store Arora's physical base address and size. This is crucial for PMM to avoid allocating over ourselves.
Verification: Print Arora's own loaded address and size.
1.6 Final ExitBootServices Call:
Action: After all necessary information is gathered, call UefiGetMemoryMap *one final time* to get the MapKey, MemoryMapSize, DescriptorSize, and DescriptorVersion.
Action: Replace the dummy values in the ExitBootServices call within efi_main with the actual, dynamically retrieved values.
Verification: The system should no longer print "ExitBootServices FAILED!". It should transition smoothly to a halt state or the next instruction (if any).
Phase 2: The Core (Bare-Metal Kernel Infrastructure)
Objective: Establish Arora's own self-sufficient execution environment, free from UEFI, with fundamental memory management and interrupt handling.

2.1 GDT (Global Descriptor Table) Configuration:
Action: Define a custom 64-bit GDT (null, 64-bit code, 64-bit data) in a new assembly file.
Action: Implement a routine to load the new GDT using lgdt and reload segment registers (mov es, rax; mov ds, rax; ...).
Verification: After loading, verify segment register values.
2.2 PMM (Physical Memory Manager - Bitmap Allocator):
Action: Implement pmm64_init. Allocate the bitmap based on total physical memory from UefiGetMemoryMap. Mark regions (UEFI, reserved, Arora's image) as "used" and conventional memory as "free". Incorporate NUMA info from SRAT to manage NUMA nodes.
Action: Implement pmm_alloc_pages, pmm_free_pages, pmm_mark_used, pmm_mark_free.
Verification: Print total, used, and free memory from PMM. Test pmm_alloc_pages and pmm_free_pages and observe bitmap changes.
2.3 Paging (64-bit Long Mode Paging):
Action: Implement paging_init_64. Allocate PML4, PDPT, PD, PT tables using PMM.
Action: Identity map a small initial region. Map Arora's entire kernel to higher-half virtual address space (e.g., 0xFFFFFFFF80000000). Map all physical RAM into the higher-half. Map MMIO regions (LAPIC, IOAPIC, PCI ECAM, GPU BARs, Framebuffer) with appropriate caching attributes.
Action: Load PML4 into CR3. Set PAE in CR4. Set LME in EFER MSR. Enable protected mode and paging.
Action: Implement map_page, unmap_page, get_phys_addr.
Verification: After enabling paging, ensure code continues execution. Test get_phys_addr on kernel addresses.
2.4 IDT (Interrupt Descriptor Table) Configuration:
Action: Define the IDT structure. Hand-craft assembly stubs for all 32 CPU exceptions (push error code, save registers, jump to panic64).
Action: Hand-craft assembly stubs for 256 IRQ handlers (save registers, call specific driver handler, send EOI, restore registers).
Action: Load IDT using lidt.
Verification: Trigger a software interrupt (e.g., int 0x3 for breakpoint) and ensure the corresponding handler is invoked.
2.5 APIC (Advanced Programmable Interrupt Controller) Initialization:
Action: Disable legacy PIC (8259) via I/O ports.
Action: Initialize LAPIC: Map MMIO registers, enable LAPIC, configure SIVR, LVT entries.
Action: Initialize I/O APIC: Map MMIO registers, configure Redirection Table Entries (RTEs) to route IRQs to IDT vectors.
Verification: Verify APIC registers read/write correctly. Mask all interrupts except for a dummy timer interrupt.
Phase 3: The Senses (Essential Bare-Metal Drivers)
Objective: Enable fundamental interaction with the system via screen, keyboard, and storage.

3.1 Screen Driver (screen_gop.asm):
Action: Implement scr64_init using GOP framebuffer info.
Action: Implement scr64_put_pixel, scr64_draw_rect, scr64_clear_screen.
Action: Embed a basic bitmap font. Implement scr64_print_char, scr64_print_string, scr64_newline.
Action: Implement cursor management.
Verification: Display a full screen of text. Draw a simple rectangle.
3.2 Keyboard Driver (keyboard.asm):
Action: Implement PS/2 controller I/O (0x60/0x64).
Action: Implement keyboard_interrupt_handler (tied to IRQ1 in IDT), which reads scan codes, translates, stores in a circular buffer, and sends LAPIC EOI.
Action: Implement getchar_from_buffer.
Verification: Type on keyboard, characters appear on screen.
3.3 PCI Driver (pci.asm):
Action: Implement pci_read_config_dword, pci_write_config_dword (using ECAM from MCFG if available, fallback to I/O ports).
Action: Implement pci_enumerate_devices to discover all PCI devices.
Action: Implement BAR parsing for memory-mapped and I/O ranges.
Action: Implement pci_find_ahci_controller.
Action: Integrate PCIe Link Negotiation (set speed, equalization) using Master Manual details.
Verification: Print a list of all detected PCI devices with Vendor/Device IDs and BAR addresses.
3.4 GPT (GUID Partition Table) Parser (gpt.asm):
Action: Implement gpt_parse to read LBA 0 (PMBR) and LBA 1 (GPT Header).
Action: Implement GPT header validation (signature, CRC32).
Action: Implement parsing of Partition Entry Array to find the target FAT32 partition's LBA start.
Verification: Successfully identify and extract the start LBA of a test FAT32 partition on AroraDisk.img.
3.5 AHCI Driver (ahci.asm):
Action: Define all AHCI HBA registers, port registers, command structures (Command List, FIS Receive, Command Header, PRDT) in assembly.
Action: Implement ahci_init: Map HBA BAR, HBA reset, enable AHCI mode, enumerate ports, allocate DMA-safe structures using PMM, enable port interrupts.
Action: Implement ahci_read_sectors, ahci_write_sectors: manually construct Command Header/PRDT, build FIS, trigger command, wait for interrupt/poll, send EOI.
Action: Implement ahci_irq_handler (tied to AHCI IRQ in IDT): read/clear status, signal completion, send EOI.
Verification: Successfully read a block from AroraDisk.img (e.g., LBA 0 or LBA 1) using direct AHCI commands and print its contents.
3.6 FAT32 Driver (fat32.asm):
Action: Implement fat32_init_partition (reads boot sector).
Action: Implement fat32_cluster_to_lba, fat32_get_next_cluster (reads FAT table).
Action: Implement directory entry parsing (including LFNs).
Action: Implement fat32_open_file, fat32_read_file.
Verification: Open and read a simple text file (e.g., test.txt) from AroraDisk.img and print its contents to the screen.
Phase 4: The Interface (Application Layer & Shell)
Objective: Create a functional command-line interface for interaction and testing.

4.1 panic64 (Critical Error Handler):
Action: Implement panic64: Disable interrupts, print error message, dump CPU register state, provide stack trace, halt (hlt).
Verification: Force a known exception (e.g., divide by zero) and ensure panic64 executes correctly.
4.2 Shell (shell.asm):
Action: Implement input loop, command parser, command dispatcher.
Action: Implement help command.
Action: Implement meminfo (uses PMM info).
Action: Implement pciinfo (uses PCI driver).
Action: Implement ls <path> (uses FAT32 driver).
Action: Implement cat <file> (uses FAT32 driver).
Verification: Test all implemented shell commands for correctness and stability.
Phase 5: The Mind (AI Core Logic)
Objective: Implement the fundamental AI model components directly in assembly.

5.1 ggml_matmul (Matrix Multiplication - CPU Optimized):
Action: Implement highly optimized GEMM routine.
Action: Integrate extensive SSE, AVX, AVX2, AVX-512 for float/integer operations. Prioritize FMA where applicable.
Action: Apply manual loop unrolling and register blocking.
Action: Design algorithms for cache awareness (L1, L2, L3).
Verification: Implement do_matmul <dim> shell command. Test with small matrices, verify results against known outputs, and measure performance (using CPU performance counters from Master Manual).
5.2 llama_model_load (Model Deserialization):
Action: Implement parser for Llama (or chosen LLM) binary model format (header, metadata, weight layout).
Action: Use FAT32 driver to read weights into PMM-allocated, aligned memory.
Action: Create in-memory structures to represent the model.
Verification: Implement do_loadmodel <path> shell command. Verify model structures are populated correctly.
5.3 llama_inference (Core AI Inference Loop):
Action: Implement rudimentary tokenizer or expect pre-tokenized input.
Action: Implement forward pass for each layer:
Self-Attention (QKV, dot-product, output projection) using ggml_matmul.
Normalization (RMSNorm/LayerNorm) using SIMD.
Activation Functions (ReLU, GELU, Swish) using SIMD.
Feed-Forward Networks.
Action: Implement basic KV cache management.
Action: Implement output logits processing.
Verification: Implement do_inference <model_id> <input_path> shell command. Run inference on a small, known input and verify output against reference. Measure inference time.
5.4 Custom AI Kernels:
Action: Implement vectorized assembly routines for common activations, normalization, and quantization if applicable.
Verification: Profile these kernels individually for performance.
Phase 6: The Summit (Advanced Optimization & GPU Integration)
Objective: Push CPU performance to its absolute limits and initiate direct GPU control for offloading.

6.1 Deep CPU Microcode Optimization:
Action: Explore and implement finer-grained control over CPU features using Undocumented MSRs and Forbidden Opcodes (Master Manual Appendix A.1.2, A.1.8) for potential performance gains. (Extremely hazardous, proceed with cloned hardware.)
Action: Leverage Cache Control & Timing techniques for specific hot paths.
Verification: Micro-benchmarking, careful analysis of instruction trace, and side-channel monitoring if available.
6.2 Bare-Metal RTX 4060 Command Submission:
Action: Implement direct GPU register access via BAR0 (Master Manual Appendix A.2.2).
Action: Implement submit_render or submit_compute routines that manually construct GPU command streams in VRAM (allocated via PMM/GPU VRAM manager).
Action: Use Key GPU Opcodes (DRAW_3D, SHADER_LOAD, MEM_COPY) from Master Manual Appendix A.2.3.
Verification: Trigger basic GPU operations (e.g., VRAM copy, simple clear screen via GPU) and observe results.
6.3 Shader Upload & Execution:
Action: Implement upload_shader (Master Manual Appendix A.2.3) using SHADER_LOAD opcode to push compiled shader binaries (not CUDA source) to GPU VRAM.
Action: Implement the necessary GPU command structures to dispatch compute shaders.
Verification: Load a trivial compute shader (e.g., a simple vector add) and verify its execution.
6.4 (Future) GPU Matrix Multiplication Offload:
Action: Design an interface within ggml_matmul to offload portions to the GPU. This will involve setting up GPU-side memory buffers, preparing GPU commands for compute dispatch, and waiting for completion.
Verification: Compare performance of CPU-only vs. CPU+GPU matrix multiplication.
Continuous Practices (Throughout All Phases)
Code Review: Rigorous, peer-to-peer review of every assembly module.
Documentation: Maintain comprehensive inline comments explaining every instruction, register use, and design decision. Update the readme.md with detailed progress ([ ] TODO / [X] DONE).
Iterative Refinement: Every routine, once implemented, must undergo at least two additional cycles of optimization and polish.
Verification: Consistent testing on QEMU and the bare-metal machine.
Error Handling: Implement robust error paths (panic64) at every critical juncture.
Naming Conventions: Adhere strictly to consistent naming conventions for labels, variables, and functions.
This plan, alongside the Master Manual, forms the complete and explicit directive for Project Arora. Commence.