
**Project Arora: Gecombineerde TODO & DONE Checklist**

**Initiator:** Assembly for AI (A4A)
**Doelstelling A4A:** "Assembly language to benefit AI performance."
**CRITICAL!!:
**NO CMAKE, NO 3RDPARTY BUILT UTILS, ONLY HARDCORE OLD SKOOL CODEING
**for intel core i7,16gb ram, 12gb vram onboard gpu, gtx Nvidia 8gb vram 4060
**Each opcode on a new line; no sequencing by ";"
**keep fucntionality intact
**meant to be bare metal, no int, no existing foreign coding, no libs, dll, github snippets, all self made
**code by lowest cpu cycles, use dma,i/o,irq.
**keep only as task the next todo or improve or finished part.
**test code, simulate in qemu.
**return compiled, linked, report extensively what is done, how, why. 
**leave code what is done untouched but read it so it conects with new code, all defines in boot_defs_temp.inc 
**the code needs to run incl a running shell env with all memory functionalitie finished, a prompt, file fucntionality, full keyboard control, screen setup
| Taak / Module                          | Status     | Notities / Volgende Stappen                                                                                                                                  |
| :------------------------------------- | :--------- | :----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **I. Basis Boot & UEFI Setup**         |            |                                                                                                                                                              |
| Keuze voor UEFI Bootproces             | [X] DONE   |                                                                                                                                                              |
| Basisstructuur `efi_main`              | [X] DONE   | In `main_uefi_loader.asm`                                                                                                                                    |
| Implementatie UEFI Wrappers:           |            | In `main_uefi_loader.asm` (of `uefi_wrappers.asm`)                                                                                                           |
|   - `UefiPrint`                        | [~] PARTIAL| Basisstructuur aanwezig, testen na GOP setup.                                                                                                                |
|   - `UefiAllocatePages`                | [~] PARTIAL| Basisstructuur aanwezig.                                                                                                                                     |
|   - `UefiGetMemoryMap`                 | [ ] TODO   | Implementeer met robuuste buffer reallocatie (omgaan met `EFI_BUFFER_TOO_SMALL`).                                                                            |
|   - `UefiLocateProtocol`               | [ ] TODO   | Nodig voor GOP, Loaded Image, BlockIO, SimpleFileSystem, etc.                                                                                                |
|   - `UefiHandleProtocol`               | [ ] TODO   | Nodig voor interactie met gevonden protocols.                                                                                                                |
|   - `UefiExitBootServices`             | [~] PARTIAL| Basisstructuur aanwezig.                                                                                                                                     |
|   - UEFI File I/O Wrappers             | [ ] TODO   | (`OpenFile`, `ReadFile`, `CloseFile`) voor laden kernel/modellen.                                                                                            |
| ACPI Parsing:                          |            |                                                                                                                                                              |
|   - RSDP, XSDT/RSDT Vinden & Parsen    | [ ] TODO   | Essentieel voor volgende ACPI-stappen.                                                                                                                       |
|   - MADT Parsen (LAPIC/IOAPIC info)    | [ ] TODO   | Voor accurate APIC base addresses en configuratie.                                                                                                           |
|   - SRAT Parsen (NUMA info)            | [ ] TODO   | Voor `numa_node_count`, `pmm_node_base_addrs`, `pmm_node_addr_limits`.                                                                                        |
|   - MCFG Parsen (ECAM voor PCI)        | [ ] TODO   | Optioneel, voor memory-mapped PCI config access.                                                                                                             |
| GOP Informatie Verkrijgen              | [ ] TODO   | Vóór `ExitBootServices`, gebruik `UefiLocateProtocol` voor GOP, sla framebuffer info op.                                                                    |
| Laden Eigen Image Info (Base/Size)     | [ ] TODO   | Vóór `ExitBootServices`, gebruik `EFI_LOADED_IMAGE_PROTOCOL`.                                                                                                |
| **II. Core CPU Setup**                 |            |                                                                                                                                                              |
| GDT Setup (`gdt_uefi.asm`):            |            |                                                                                                                                                              |
|   - Definitie 64-bit descriptoren      | [X] DONE   |                                                                                                                                                              |
|   - Laden GDT (`lgdt` + segs)          | [X] DONE   |                                                                                                                                                              |
| IDT Setup (`idt64_uefi.asm`):          |            |                                                                                                                                                              |
|   - Exceptions (0-31) stubs/handler    | [X] DONE   | Basisstructuur.                                                                                                                                              |
|   - IRQ Stubs & Handler Registratie    | [ ] TODO   | Uitbreiden voor Keyboard, AHCI, Timer etc. via APIC.                                                                                                         |
|   - Laden IDT (`lidt`)                 | [X] DONE   | Correct geplaatst na `ExitBootServices`.                                                                                                                     |
| APIC Setup (`apic.asm`):               |            |                                                                                                                                                              |
|   - Basisstructuur                     | [X] DONE   |                                                                                                                                                              |
|   - Gebruik ACPI MADT voor Base Addr.  | [ ] TODO   | Vervang hardgecodeerde/default adressen.                                                                                                                     |
|   - Initialisatie LAPIC & I/O APIC     | [X] DONE   | Basis initialisatie logica.                                                                                                                                  |
|   - IRQ Routing (RTEs)                 | [X] DONE   | Voorbeelden voor Kbd/AHCI aanwezig.                                                                                                                          |
|   - Disable Legacy PIC                 | [X] DONE   |                                                                                                                                                              |
| **III. Geheugenbeheer**                |            |                                                                                                                                                              |
| PMM (`pmm64_uefi.asm`):                |            |                                                                                                                                                              |
|   - `pmm64_init_uefi` Implementatie    | [ ] TODO   | Gedetailleerde logica voor UEFI map, NUMA (van ACPI), bitmap alloc/init, regio's vrijgeven/markeren.                                                        |
|   - Core Alloc/Free/Mark Functies      | [X] DONE   | Herbruikbare bitmap logica.                                                                                                                                  |
| Paging (`paging64_uefi.asm`):          |            |                                                                                                                                                              |
|   - `paging_init_64_uefi` Implementatie| [ ] TODO   | Gedetailleerde logica voor mappen RAM (UEFI map, NUMA-bewust) en kernel, gebruikmakend van PMM.                                                              |
|   - Core Map/Unmap Functies            | [X] DONE   | Gebruikt PMM.                                                                                                                                                |
| **IV. Drivers (Post-ExitBootServices)**|            |                                                                                                                                                              |
| Schermdriver (`screen_gop.asm`):       |            |                                                                                                                                                              |
|   - `scr64_init` met GOP info          | [ ] TODO   |                                                                                                                                                              |
|   - `scr64_print_*` met framebuffer    | [ ] TODO   | Implementeer karakterrendering, integreer font.                                                                                                              |
| Keyboard Driver (`keyboard.asm`):      |            |                                                                                                                                                              |
|   - `keyboard_interrupt_handler`       | [X] DONE   | Basisstructuur.                                                                                                                                              |
|   - APIC EOI integratie                | [ ] TODO   | Vervang PIC EOI.                                                                                                                                             |
|   - `getchar_from_buffer`              | [X] DONE   |                                                                                                                                                              |
| PCI Driver (`pci.asm`):                |            |                                                                                                                                                              |
|   - `pci_find_ahci_controller`         | [X] DONE   | Gebruikt legacy I/O. Overweeg ECAM/MCFG.                                                                                                                     |
| AHCI Driver (`ahci.asm`):              |            |                                                                                                                                                              |
|   - `ahci_defs.inc`                    | [X] DONE   |                                                                                                                                                              |
|   - `ahci_init`                        | [ ] TODO   | Gebruik BAR van PCI; HBA/poort init; Command List/FIS setup (PMM alloc); enable interrupts.                                                                |
|   - `ahci_read/write_sectors`          | [ ] TODO   | Implementeer DMA (Cmd Hdr, FIS, PRDT); synchroniseer met IRQ handler.                                                                                        |
|   - `ahci_irq_handler`                 | [ ] TODO   | Verwerk IRQ, signaleer R/W, stuur EOI naar LAPIC.                                                                                                            |
| GPT Parsing:                           | [ ] TODO   | Implementeer functie die GPT leest (via AHCI) om FAT32 LBA start te vinden.                                                                                 |
| FAT32 Driver (`fat32.asm`):            |            |                                                                                                                                                              |
|   - Aanpassen `fat32_init_partition`   | [ ] TODO   | Accepteer AHCI poort & GPT LBA.                                                                                                                              |
|   - Integratie met AHCI R/W            | [ ] TODO   | Vervang placeholder disk I/O.                                                                                                                                |
|   - Write/Create functionaliteit       | [ ] TODO   | Implementeer indien nodig.                                                                                                                                   |
| **V. Applicatielaag & Shell**          |            |                                                                                                                                                              |
| `panic64` Implementatie                | [ ] TODO   | Gebruik `scr64_*` voor output.                                                                                                                               |
| Shell (`shell.asm`):                   |            |                                                                                                                                                              |
|   - Commando Parsing/Dispatch          | [X] DONE   | Basisstructuur.                                                                                                                                              |
|   - Implementatie Shell Commando's     | [ ] TODO   | Logica voor `do_matmul`, `do_loadmodel`, etc.                                                                                                                |
|   - Interruptbeheer (cli/sti)          | [ ] TODO   | Rond kritieke rekenkernen.                                                                                                                                   |
| Linken Compute Libraries               | [ ] TODO   | (`ggml_matmul`, `llama_model_load`, etc.)                                                                                                                    |
| **VI. Bouw & Test**                    |            |                                                                                                                                                              |
| Assembleren alle modules               | [X] DONE   | Objectbestanden worden gegenereerd.                                                                                                                          |
| Linken tot `.efi` applicatie           | [ ] TODO   | Stel linker script/commando's op.                                                                                                                            |
| Testen op UEFI Systeem/Emulator        | [ ] TODO   | Iteratief testen en debuggen.                                                                                                                                |

Dit geeft een duidelijker beeld van de resterende werkzaamheden. De stappen met "[ ] TODO" vereisen actieve codering en implementatie. De "[~] PARTIAL" zijn structureel aanwezig maar missen nog cruciale details of robuustheid.
# Project Arora: Forging Phase

This phase of Project Arora focuses on the implementation and benchmarking of a bare model AI, leveraging specific hardware optimizations and advanced input capabilities. The primary goal is to accelerate AI computations using modern hardware components and to quantify these performance gains against a traditional C++ implementation.

## Goals:

1.  **Hardware-Accelerated AI Implementation**: Develop and integrate AI computation routines optimized for:
    *   **NVIDIA RTX 4060 GPU**: Utilize GPU capabilities for parallel processing and accelerated matrix operations.
    *   **Intel i7 CPU Core**: Implement CPU-specific optimizations, potentially involving AVX/AVX2/AVX512 instructions for efficient vector processing.
    *   **DDR5 RAM**: Optimize memory access patterns and data structures to take full advantage of DDR5's higher bandwidth and lower latency.
    *   **PCI Optimization**: Implement efficient data transfer mechanisms over the PCI bus to minimize latency between components (e.g., CPU-GPU communication).

2.  **Full Keyboard Support**: Enhance the existing shell with advanced keyboard functionalities:
    *   **Copy Functionality**: Implement mechanisms to copy selected text or data within the shell environment.
    *   **Paste Functionality**: Implement mechanisms to paste copied text or data into the shell environment.

3.  **Bare Model AI**: Implement a fundamental AI model (e.g., a simple neural network or a basic machine learning algorithm) to serve as the target for acceleration.

4.  **C++ Benchmark Development**: Create a comparable C++ implementation of the bare model AI to serve as a baseline for performance comparison.

5.  **Benchmarking and Performance Analysis**: Conduct rigorous benchmarking to measure the speed difference between the hardware-accelerated AI and the C++ benchmark. This will involve:
    *   Defining clear metrics for performance evaluation (e.g., inference time, throughput).
    *   Developing a robust benchmarking framework.
    *   Analyzing results to identify bottlenecks and areas for further optimization.

## Scope:

This phase will involve low-level assembly programming for hardware interaction and optimization, integration with the existing UEFI environment, and potentially high-level programming (C++) for the benchmark. The focus is on demonstrating significant performance improvements through hardware-specific optimizations for AI workloads.

## Next Steps (from `todo.md`):

- [ ] Research Hardware-Specific Optimizations
- [ ] Implement Hardware-Accelerated AI
  - [ ] Implement NVIDIA RTX 4060 GPU acceleration
  - [ ] Implement Intel i7 CPU core optimization
  - [ ] Implement DDR5 RAM optimization
  - [ ] Implement PCI optimization
- [ ] Implement Full Keyboard Support
  - [ ] Implement copy functionality
  - [ ] Implement paste functionality
- [ ] Develop C++ Benchmark
- [ ] Benchmarking and Performance Analysis
- [ ] Document Forging Phase
- [ ] Deliver Results to User


