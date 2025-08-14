# Instruction Manual: NVIDIA RTX 4060 and Intel i7 Hardware Settings for Bare-Metal NASM Coding

This manual combines general hardware settings for the NVIDIA GeForce RTX 4060 GPU and Intel Core i7-13650HX CPU with specific, low-level details from a user-provided cheat sheet. It is designed for bare-metal programming using NASM, enabling direct hardware interaction without an operating system. The manual covers ports, IRQs, DMA, memory offsets, PCI configurations, DDR memory, and special CPU/GPU opcodes, with practical examples and safety warnings for advanced techniques.

## 1. System Overview

### 1.1 NVIDIA GeForce RTX 4060
- **Architecture**: Ada Lovelace (AD107 chip)
- **Manufacturing Process**: 5nm (TSMC 4N)
- **CUDA Cores**: 3,072
- **Tensor Cores**: 96 (4th gen)
- **RT Cores**: 24 (3rd gen)
- **Memory**: 8 GB GDDR6
  - **Interface**: 128-bit
  - **Bandwidth**: 272 GB/s (14 Gbps effective)
  - **Clock**: 2,250 MHz
- **Base/Boost Clock**: 1.83 GHz / 2.46 GHz
- **Total Graphics Power (TGP)**: 115W
- **Power Connector**: 1x 8-pin PCIe or 1x 12-pin (with adapter)
- **PCI Express**: PCIe 4.0 x8
- **Display Outputs**:
  - 1x HDMI 2.1
  - 3x DisplayPort 1.4a
- **Features**:
  - DLSS 3.0 with Frame Generation
  - 8th-gen NVIDIA Encoder (NVENC) with AV1 support
  - DirectX 12 Ultimate
- **Cooling**: Dual-slot, requires two expansion slots (9.6" x 3.9" x 2-slot)

### 1.2 Intel Core i7-13650HX
- **Architecture**: Raptor Lake-HX
- **Cores/Threads**: 14 cores (6 Performance + 8 Efficient), 20 threads
- **Base/Boost Clock**: Up to 5.2 GHz
- **Cache**: 24 MB L3 cache
- **Socket**: LGA 1700
- **Memory Support**:
  - DDR5 (up to 5600 MHz)
  - DDR4 (backward compatible with some motherboards)
- **PCI Express**: PCIe 5.0 (16 lanes) + PCIe 4.0 (4 lanes)
- **TDP**: 55W base, up to 157W turbo
- **Integrated Graphics**: Intel UHD Graphics (optional, often disabled with dedicated GPU)
- **Chipset Compatibility**: Intel 600/700 series (e.g., Z790, B760)
- **Features**:
  - Intel VT-x, VT-d (virtualization)
  - Hyper-Threading
  - Turbo Boost

## 2. Hardware Configuration

### 2.1 PCI Express Configuration
The RTX 4060 and Intel i7 communicate over the PCI Express (PCIe) bus, requiring specific configuration for bare-metal access.

#### RTX 4060 PCIe
- **Interface**: PCIe 4.0 x8 (uses 8 lanes, compatible with PCIe 3.0 at reduced bandwidth)
- **Slot Requirement**: Primary PCIe x16 slot (electrically x8 for RTX 4060)
- **Base Address Registers (BARs)**:
  - **BAR0**: `0x96000000` (256M, prefetchable) - Control registers, GPU engine access (e.g., Display Core, Graphics Engine)
  - **BAR1**: `0xA0000000` (8GB, prefetchable) - VRAM aperture
  - **BAR3**: `0x80000000` (32M, prefetchable) - ROM/Backup memory
- **Link Negotiation**:
  - Detect electrical idle: Check Link Status at `[PCIe_CAP + 0x10]`
  - Set link speed: Gen4 with `*(volatile uint16_t*)(PCIe_CAP + 0x0C) = 0x4000;`
  - Equalization for Gen4/5: `*(volatile uint32_t*)(PCIe_CAP + 0x100) |= 0x1;`
- **Configuration Steps**:
  1. Insert RTX 4060 into primary PCIe x16 slot.
  2. Update motherboard BIOS for PCIe 4.0 compatibility.
  3. Force PCIe 3.0 in BIOS if instability occurs.
- **Accessing PCIe Configuration Space**:
  - Use ports `0xCF8` (Address) and `0xCFC` (Data)
  - Example NASM code:
    ```nasm
    mov eax, 0x80000000 | (bus << 16) | (dev << 11) | (func << 8) | 0x10
    mov dx, 0x0CF8
    out dx, eax
    mov dx, 0x0CFC
    in eax, dx
    test eax, eax
    jz no_device
    ```

#### Intel i7 PCIe
- **Lanes**: 16x PCIe 5.0 (for GPU) + 4x PCIe 4.0 (for NVMe or other devices)
- **Configuration**:
  - PCIe lanes are directly connected to the CPU for the primary x16 slot.
  - Additional devices may share lanes via chipset (e.g., Z790).
  - Check motherboard manual for lane allocation (e.g., x8/x8 split for dual GPUs).
- **Memory-Mapped Configuration Space (MMCFG)**:
  - Typical base: `0xE0000000–0xEFFFFFFF` (varies by motherboard)
  - Access via memory reads/writes in NASM

### 2.2 Memory Configuration
#### DDR Memory (System RAM)
- **Support**: DDR5 up to 5600 MHz, DDR4 compatible with some motherboards
- **Initialization Sequence**:
  - Enable Power Management Controller (PMC):
    ```nasm
    mov dx, 0xCF8
    mov eax, 0x800000F8
    out dx, eax
    mov dx, 0xCFC
    in eax, dx
    or eax, (1 << 31)  ; Set PMC enable
    out dx, eax
    ```
  - Configure timing registers via MSR `0x1A0`:
    ```nasm
    mov ecx, 0x1A0     ; IA32_MISC_ENABLE
    rdmsr
    and eax, ~(1 << 8) ; Disable fast string ops
    wrmsr
    ```
- **Physical Memory Map**:
  - `0x00000000-0x0009FFFF`: Legacy BIOS (640KB)
  - `0x000A0000-0x000BFFFF`: VGA Memory
  - `0x000C0000-0x000FFFFF`: Option ROMs
  - `0x00100000-0x00EFFFFF`: Free RAM
  - `0xFEC00000-0xFEC00FFF`: IOAPIC
  - `0xFEE00000-0xFEE00FFF`: Local APIC
- **DDR5 Memory Controller Hub (MCH) Register Map**:
  - Base Addresses:
    - `0xFED80000`: DDR5 Channel 0 Control
    - `0xFED84000`: DDR5 Channel 1 Control
    - `0xFED88000`: DDR5 Channel 2 Control
  - Key Offsets:
    - `0x0200`: tCL Timing Register
    - `0x0204`: tRCD/tRP Timing
    - `0x0208`: tRAS/tRC Timing
    - `0x0210`: Command Rate (1T/2T)
    - `0x300`: ZQ Calibration Start
    - `0x304`: ZQ Calibration Status
    - `0x500`: ECC/Scrub Control
  - Typical DDR5-4800 Timing Values:
    - `TCL`: 40 (`0x28`)
    - `TRCD`: 42 (`0x2A`)
    - `TRP`: 42 (`0x2A`)
    - `TRAS`: 90 (`0x5A`)

#### RTX 4060 GDDR6
- **Memory**: 8 GB GDDR6, 128-bit bus, accessed via BAR1 (`0xA0000000`)
- **MMIO Map**:
  - `BAR0 + 0x00610000`: Display Core
  - `BAR0 + 0x00800000`: Graphics Engine
  - `BAR0 + 0x00A00000`: Memory Controller
  - `BAR0 + 0x1000`: Pushbuffer Pointer (GPU Command Queue)
  - `BAR0 + 0x1004`: Kickoff (Start Command Execution)
  - `BAR0 + 0x1540`: SM Control Register
  - `BAR0 + 0x17A00`: Performance Counters Enable
  - `BAR0 + 0x1FF00`: NV_DEBUG_REG
- **Access**: Use DMA for data transfers between system RAM and GPU memory
- **Example NASM Code**:
  ```nasm
  ; Read BAR0 for RTX 4060 frame buffer
  mov eax, 0x80010010  ; BAR0 offset
  mov dx, 0xCF8
  out dx, eax
  mov dx, 0xCFC
  in eax, dx           ; EAX contains frame buffer base
  ```

### 2.3 Ports
- **Serial Port (UART)**: COM1 (`0x3F8`) for debugging
  - Example:
    ```nasm
    mov dx, 0x3F8   ; COM1
    mov al, 'A'
    out dx, al
    ```
- **PCIe Configuration Space**:
  - `0xCF8`: Configuration Address Port
  - `0xCFC`: Configuration Data Port
- **Debug Port**: `0xCF9` (PCIe debugging, access via `out dx, al`)
- **Note**: RTX 4060 primarily uses memory-mapped I/O (MMIO) via PCIe BARs, reducing reliance on legacy I/O ports.

### 2.4 IRQs
- **RTX 4060**:
  - Uses Message Signaled Interrupts (MSIs) over PCIe
  - Typical MSI vector: 16–31 (dynamic, configured via ACPI tables)
  - Query MSI capability at PCIe config space offset `0x60`
- **Intel i7**:
  - **Local APIC**: `0xFEE00000-0xFEE00FFF`
  - **IOAPIC**: `0xFEC00000-0xFEC00FFF`
  - Example NASM code to enable APIC:
    ```nasm
    mov ecx, 0x1B        ; IA32_APIC_BASE MSR
    rdmsr
    or eax, 0x800        ; Enable APIC
    wrmsr
    ```
- **Configuration**: Parse ACPI tables (RSDT/XSDT) to map IRQs to devices

### 2.5 DMA
- **General DMA Setup**:
  - Requires physically contiguous memory
  - Programmed via device DMA registers
  - Example (C):
    ```c
    *(volatile uint64_t*)(BAR0 + 0x00) = src_phys_addr;  // Source
    *(volatile uint64_t*)(BAR0 + 0x08) = dst_phys_addr;  // Destination
    *(volatile uint32_t*)(BAR0 + 0x10) = size;           // Length
    *(volatile uint32_t*)(BAR0 + 0x14) = 1;              // Start bit
    ```

- **AHCI Controller DMA**:
  - **Base Address**: `0xF7248000`
  - **Key Registers**:
    - `AHCI_CAP`: `0x00` (Capabilities)
    - `AHCI_GHC`: `0x04` (Global Host Control)
    - `AHCI_PxCLB`: `0x00` (Port x Command List Base)
    - `AHCI_PxFB`: `0x08` (Port x FIS Base)
  - Example (C):
    ```c
    #define AHCI_BASE 0xF7248000
    struct ahci_cmd_header {
        uint32_t opts;
        uint32_t status;
        uint64_t ctba;  // Command Table DMA Address
        uint32_t reserved[4];
    };
    void setup_ahci_dma(void) {
        volatile uint8_t* hba = (uint8_t*)map_physical(AHCI_BASE);
        struct ahci_cmd_header* cmdlist = dma_alloc(1024);
        uint8_t* fis = dma_alloc(256);
        uint8_t* cmdtable = dma_alloc(128);
        uint64_t clb = virt_to_phys(cmdlist);
        uint64_t fb = virt_to_phys(fis);
        write64(hba + PxCLB, clb);
        write64(hba + PxFB, fb);
        uint32_t cmd = read32(hba + PxCMD);
        write32(hba + PxCMD, cmd | 0x10);  // Set FRE
    }
    ```

- **PCIe Root Complex Exploit DMA** (Warning: High Risk):
  - Offset: `BAR0 + 0x1000`
  - Example (C):
    ```c
    void pcie_dma_exploit(void *src, void *dst, size_t len) {
        volatile uint64_t *dma = (uint64_t*)(BAR0 + 0x1000);
        dma[0] = (uint64_t)src;  // Source
        dma[1] = (uint64_t)dst;  // Destination
        dma[2] = len | 0x80000000; // Start bit
        while (dma[2] & 0x80000000); // Wait
    }
    ```
  - **Caution**: This technique is experimental and may cause system instability or violate hardware warranties.

## 3. CPU and GPU Opcodes

### 3.1 Intel i7 CPU Opcodes
- **Instruction Set**: x86-64 (AMD64)
- **Standard Instructions**:
  - **CPUID**: Query CPU features (e.g., SSE, AVX, VT-x)
    ```nasm
    mov eax, 1
    cpuid
    test edx, (1<<25) ; SSE support?
    test ecx, (1<<25) ; AES-NI?
    ```
  - **RDMSR/WRMSR**: Read/write Model-Specific Registers
    ```nasm
    mov ecx, 0x79       ; IA32_BIOS_UPDT_TRIG
    mov eax, [esi+48]   ; Get data size
    mov edx, [esi+52]
    wrmsr
    ```
  - **IN/OUT**: Access I/O ports
  - **MOV to/from CRx**: Control registers (e.g., CR3 for paging)
  - **VMX Instructions**: For virtualization (VMXON, VMLAUNCH)
  - **AVX/AVX2**: Vectorized operations
    ```nasm
    vaddps ymm0, ymm1, ymm2  ; AVX vector add
    ```
  - **RDTSC**: Read Time-Stamp Counter
    ```nasm
    rdtsc
    ; EDX:EAX contains 64-bit cycle count
    ```
  - **INVPCID**: Invalidate TLB

- **Undocumented/Forbidden Opcodes** (Warning: High Risk):
  - **ICEBP**: `db 0x0F, 0x04` (In-Circuit Emulator Breakpoint)
  - **PREFETCHT0**: `db 0x0F, 0x18, 0x01` (Cache line pinning)
  - **LDMXCSR**: `db 0x0F, 0xAE, 0xE8` (SSE control takeover)
  - **Opcode Aliasing**:
    - `0xF3 0x0F 0xBC`: REP BSF (executes CPUID)
    - `0x66 0x0F 0x12`: MOVDDUP (secret register copy)
  - **Caution**: These opcodes are undocumented and may cause system crashes or undefined behavior. Use only in controlled environments with proper authorization.

### 3.2 NVIDIA RTX 4060 GPU Opcodes
- **Instruction Set**: Proprietary (CUDA/PTX for high-level, custom microcode for low-level)
- **Reverse-Engineered Commands**:
  - Memory Copy: `0xBAC00000` (VRAM-to-VRAM transfer)
  - 3D Operation: `0xBAD00000` (Start rendering job)
  - Register Write: `0x00000031` (MI_LOAD_REGISTER_IMM)
- **Advanced Command Stream**:
  - **Header Format**:
    - Bits 0-7: Opcode
    - Bits 8-15: Subcode
    - Bits 16-31: Length (DWORDs)
  - **Key Opcodes**:
    - `0x1B`: NOP
    - `0x2A`: DRAW_3D
    - `0x31`: LOAD_REG
    - `0x5A`: MEM_COPY
    - `0xC0`: SHADER_LOAD
- **Pushbuffer Format**:
  ```c
  struct PushBufferHeader {
      uint32_t magic;    // 0xDEADBEEF
      uint32_t engine;   // 0xC0 = 3D, 0xD0 = Compute
      uint64_t va_start; // Virtual address
      uint32_t dwords;   // Command length
      uint32_t flags;    // Bit 0 = IB (Indirect Buffer)
  };
  ```
- **Shader Upload Example** (Python/Assembly Hybrid):
  ```python
  def upload_shader(vaddr, code):
      gpu_va = allocate_gpu_mem(len(code))
      cmd = [
          0x1B000000,  # NOP
          0xC1000000 | ((len(code)//4) & 0xFFFF),  # SHADER_LOAD
          gpu_va & 0xFFFFFFFF,
          gpu_va >> 32,
      ] + code
      submit_to_engine(ENGINE_COMPUTE, cmd)
  ```
- **SM Control** (Warning: High Risk):
  ```c
  #define SM_CONTROL_REG  (BAR0 + 0x1540)
  void sm_hijack(uint32_t sm_id) {
      volatile uint32_t *ctrl = (uint32_t*)SM_CONTROL_REG;
      ctrl[sm_id] = 0xDEADBEEF;  // SM takeover
      while ((ctrl[sm_id] & 0x80000000) == 0); // Wait
  }
  ```
- **Note**: GPU opcodes are proprietary and partially reverse-engineered. Use open-source drivers like [Nouveau](https://nouveau.freedesktop.org/) or contact NVIDIA for developer access.

## 4. Bare-Metal NASM Coding Guidelines
- **Bootstrap**:
  - Initialize CPU in real mode, switch to protected/long mode:
    ```nasm
    bits 16
    global _start
    _start:
        cli
        lgdt [gdt_descriptor]
        mov eax, cr0
        or eax, 1
        mov cr0, eax
        jmp 0x08:protected_mode
    bits 32
    protected_mode:
        mov ax, 0x10
        mov ds, ax
        mov es, ax
        mov ss, ax
        hlt
    section .data
    gdt_descriptor:
        dw gdt_end - gdt - 1
        dd gdt
    gdt:
        dd 0, 0
        dd 0x0000FFFF, 0x00CF9A00  ; Code segment
        dd 0x0000FFFF, 0x00CF9200  ; Data segment
    gdt_end:
    ```
- **PCIe Initialization**:
  - Scan PCIe bus for RTX 4060 (vendor ID: `0x10DE`, device ID: ~`0x28A0`)
  - Read BARs to map GPU memory
- **Memory Management**:
  - Set up paging for high memory (>4 GB)
  - Map GPU frame buffer and MMIO regions
- **Interrupt Handling**:
  - Configure APIC for MSI handling
  - Write interrupt handlers for GPU events
- **GPU Programming**:
  - Initialize GPU via command buffers
  - Use DMA for data transfers
  - Submit shaders or compute tasks
- **Example NASM Code**:
  ```nasm
  section .text
  global _start
  bits 32
  _start:
      ; Scan PCIe bus for NVIDIA GPU (vendor 0x10DE)
      mov eax, 0x80000000
      mov dx, 0xCF8
      out dx, eax
      mov dx, 0xCFC
      in eax, dx
      cmp eax, 0x10DE
      je found_gpu
      hlt
  found_gpu:
      ; Read BAR0 for frame buffer
      mov eax, 0x80010010  ; BAR0 offset
      mov dx, 0xCF8
      out dx, eax
      mov dx, 0xCFC
      in eax, dx
      ; EAX contains frame buffer base
      hlt
  ```

## 5. Troubleshooting
- **RTX 4060 Instability**:
  - Force PCIe 3.0 in BIOS if PCIe 4.0 causes crashes
  - Ensure PSU provides 550W with 1x 8-pin PCIe cable
- **IRQ Conflicts**:
  - Check ACPI tables for IRQ assignments
  - Disable unused devices in BIOS
- **DMA Issues**:
  - Verify VT-d is enabled in BIOS
  - Use DMAR tables to configure DMA remapping
- **Opcode Issues**:
  - Avoid undocumented opcodes unless in a controlled environment
  - Refer to [NVIDIA CUDA Toolkit](https://developer.nvidia.com/cuda-toolkit) or [Nouveau](https://nouveau.freedesktop.org/) for GPU commands

## 6. Additional Resources
- **NVIDIA**:
  - [CUDA Toolkit](https://developer.nvidia.com/cuda-toolkit): High-level GPU programming
  - [Nouveau Driver](https://nouveau.freedesktop.org/): Open-source NVIDIA driver (limited low-level access)
  - Contact NVIDIA for proprietary documentation (developer program)
- **Intel**:
  - [Intel 64 and IA-32 Architectures Software Developer’s Manual](https://www.intel.com/content/www/us/en/developer/articles/technical/intel-sdm.html)
  - Intel VT-d Specification for DMA
- **General**:
  - [OSDev Wiki](https://wiki.osdev.org/Main_Page): Bare-metal programming tutorials
  - [ACPI Specification](https://uefi.org/specifications): For parsing DMAR, RSDT tables
  - [PCIe Specification](https://pcisig.com/specifications): For configuration space details
  - [Bare-Metal GPU Programming Guide](https://macoy.me/blog/programming/PiGPU): General principles for GPU programming

## 7. Limitations
- **Proprietary Information**: NVIDIA’s GPU opcodes and low-level registers are not publicly documented. Reverse engineering or developer access is required.
- **Dynamic Assignments**: IRQs, DMA channels, and memory offsets vary by motherboard and BIOS. Use ACPI tables or runtime scanning.
- **Complexity**: Bare-metal GPU programming is challenging without OS-level drivers. Consider using a minimal OS for initial testing.
- **Risky Operations**: Undocumented opcodes and silicon-level hacking can cause hardware damage or legal issues.

## 8. Disclaimer
This manual includes advanced and potentially hazardous techniques, such as undocumented opcodes and silicon-level hacking. These should only be attempted by experts with proper authorization, equipment, and safety measures. Mishandling can lead to permanent hardware damage or violation of legal agreements (e.g., NDAs with Intel/NVIDIA). Always test in a controlled environment and consult vendor documentation when possible.