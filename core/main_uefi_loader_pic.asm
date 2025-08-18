; main_uefi_loader_pic.asm - Merged UEFI Bootloader + GDT/IDT/PIC Setup
; PIC-compliant version that avoids global variables in .bss/.data sections
; and uses PC-relative addressing for all static data

BITS 64
default rel

; Removed global _start to avoid conflict with gnu-efi crt0-efi-x86_64.o
global efi_main ; Use efi_main as our entry point instead
global init_main_runtime_data
global get_efi_image_base, get_efi_image_size
global get_key_buffer, get_key_buffer_head, get_key_buffer_tail
global uefi_AllocatePagesWrapper ; Export the UEFI AllocatePages wrapper

%include "boot_defs_temp.inc" ; Includes UEFI/AHCI/FAT/PIC Defs now
%include "boot_defs_uefi.inc" ; Additional UEFI-specific definitions

; --- Externals ---

; Memory Management
extern pmm64_init_uefi, pmm_alloc_frame, pmm_free_frame, pmm_mark_region_used
; Paging
extern paging_init_64_uefi, reload_cr3, kernel_pml4
; GDT
extern setup_final_gdt64, load_gdt_and_segments64, gdt64_pointer_var
; IDT
extern setup_final_idt64
extern load_idt64
extern dt64_pointer_var ; Use combined setup
; Screen Driver (Post-BS)
extern scr64_init, scr64_print_string, scr64_print_hex, scr64_print_dec
extern gop_framebuffer_base, gop_framebuffer_size, gop_h_res, gop_v_res
extern gop_pixels_per_scanline, gop_pixel_format
; Keyboard Driver (Post-BS)
extern keyboard_init, getchar_from_buffer
; PCI
extern pci_init, pci_find_ahci_controller
; AHCI
extern ahci_init, ahci_read_sectors, ahci_write_sectors
; FAT32
extern fat32_init
; PIC
extern pic_remap
; Runtime modules
extern init_acpi_runtime_data, get_acpi_lapic_base, get_acpi_ioapic_base
extern get_numa_node_count, get_numa_node_base, get_numa_node_limit
extern init_fat32_runtime_data, get_current_dir_cluster, set_current_dir_cluster
extern init_idt64_runtime_data, get_idt64_pointer
extern init_keyboard_runtime_data
; Payload / Panic
extern shell_run, panic64

; Structure of runtime main data block:
; Offset 0:  main_runtime_data_ptr (qword)
; Offset 8:  gImageHandle (qword)
; Offset 16: gSystemTable (qword)
; Offset 24: gMemoryMap (qword)
; Offset 32: gMemoryMapSize (qword)
; Offset 40: gMapKey (qword)
; Offset 48: gDescriptorSize (qword)
; Offset 56: gDescriptorVersion (qword)
; Offset 64: gFinalGdtBase (qword)
; Offset 72: gFinalIdtBase (qword)
; Offset 80: gAhciBaseAddr (qword)
; Offset 88: gFat32PartitionLba (qword)
; Offset 96: gAhciPortNum (dword)
; Offset 100: padding (4 bytes)
; Offset 104: gFileSystemHandle (qword)
; Offset 112: gFileSystemProtocol (qword)
; Offset 120: gRootDirectory (qword)
; Offset 128: efi_image_base (qword)
; Offset 136: efi_image_size (qword)
; Offset 144: key_buffer (KEY_BUFFER_SIZE bytes)
; Offset 144+KEY_BUFFER_SIZE: key_buffer_head (word)
; Offset 146+KEY_BUFFER_SIZE: key_buffer_tail (word)
; Offset 148+KEY_BUFFER_SIZE: disk_read_buffer (4096 bytes)
; Total size: 148 + KEY_BUFFER_SIZE + 4096

%define MAIN_RUNTIME_DATA_SIZE (148 + KEY_BUFFER_SIZE + 4096)

%define OFFSET_MAIN_RUNTIME_PTR 0
%define OFFSET_IMAGE_HANDLE 8
%define OFFSET_SYSTEM_TABLE 16
%define OFFSET_MEMORY_MAP 24
%define OFFSET_MEMORY_MAP_SIZE 32
%define OFFSET_MAP_KEY 40
%define OFFSET_DESCRIPTOR_SIZE 48
%define OFFSET_DESCRIPTOR_VERSION 56
%define OFFSET_FINAL_GDT_BASE 64
%define OFFSET_FINAL_IDT_BASE 72
%define OFFSET_AHCI_BASE_ADDR 80
%define OFFSET_FAT32_PARTITION_LBA 88
%define OFFSET_AHCI_PORT_NUM 96
%define OFFSET_FILE_SYSTEM_HANDLE 104
%define OFFSET_FILE_SYSTEM_PROTOCOL 112
%define OFFSET_ROOT_DIRECTORY 120
%define OFFSET_EFI_IMAGE_BASE 128
%define OFFSET_EFI_IMAGE_SIZE 136
%define OFFSET_KEY_BUFFER 144
%define OFFSET_KEY_BUFFER_HEAD(buffer_size) (144 + buffer_size)
%define OFFSET_KEY_BUFFER_TAIL(buffer_size) (146 + buffer_size)
%define OFFSET_DISK_READ_BUFFER(buffer_size) (148 + buffer_size)

section .data
    ; Single global pointer to runtime allocated data
    main_runtime_data_ptr dq 0

section .rodata
    ; Messages (read-only data, PC-relative addressing)
    msg_welcome db "UEFI Loader Initializing...", 0Dh, 0Ah, 0
    msg_loaded_image_ok db "Loaded Image Info OK", 0Dh, 0Ah, 0
    msg_loaded_image_fail db "Failed to get Loaded Image Protocol!", 0Dh, 0Ah, 0
    msg_gop_ok db "Graphics Output Protocol OK", 0Dh, 0Ah, 0
    msg_gop_fail db "Failed to get GOP!", 0Dh, 0Ah, 0
    msg_memmap_ok db "Memory Map OK", 0Dh, 0Ah, 0
    msg_memmap_fail db "Failed to get Memory Map!", 0Dh, 0Ah, 0
    msg_alloc_gdt_fail db "Failed to allocate GDT!", 0Dh, 0Ah, 0
    msg_alloc_idt_fail db "Failed to allocate IDT!", 0Dh, 0Ah, 0
    msg_pmm_ok db "PMM Initialized", 0Dh, 0Ah, 0
    msg_pmm_fail db "PMM Initialization Failed!", 0Dh, 0Ah, 0
    msg_paging_ok db "Paging Initialized", 0Dh, 0Ah, 0
    msg_paging_fail db "Paging Initialization Failed!", 0Dh, 0Ah, 0
    msg_gdt_ok db "GDT Setup OK", 0Dh, 0Ah, 0
    msg_exit_bs_fail db "ExitBootServices Failed!", 0Dh, 0Ah, 0
    msg_post_exit db "Exited Boot Services. Setting up HW...", 0Dh, 0Ah, 0
    msg_pic_ok db "PIC Remapped OK", 0Dh, 0Ah, 0
    msg_pci_ok db "PCI Init OK", 0Dh, 0Ah, 0
    msg_ahci_ok db "AHCI Init OK", 0Dh, 0Ah, 0
    msg_ahci_fail db "AHCI Init Failed!", 0Dh, 0Ah, 0
    msg_gpt_ok db "FAT32 Partition Found OK", 0Dh, 0Ah, 0
    msg_gpt_fail db "FAT32 Partition Not Found!", 0Dh, 0Ah, 0
    msg_fat32_ok db "FAT32 Init OK", 0Dh, 0Ah, 0
    msg_fat32_fail db "FAT32 Init Failed!", 0Dh, 0Ah, 0
    msg_kbd_ok db "Keyboard Init OK", 0Dh, 0Ah, 0
    msg_idt_ok db "IDT Setup OK. Enabling Interrupts.", 0Dh, 0Ah, 0
    msg_jumping db "Jumping to Shell...", 0Dh, 0Ah, 0
    msg_shell_return_err db "Shell Returned Unexpectedly!", 0Dh, 0Ah, 0
    msg_fs_ok db "File System Protocol OK", 0Dh, 0Ah, 0
    msg_fs_fail db "Failed to get File System Protocol!", 0Dh, 0Ah, 0
    msg_root_dir_ok db "Root Directory Opened OK", 0Dh, 0Ah, 0
    msg_root_dir_fail db "Failed to open Root Directory!", 0Dh, 0Ah, 0
    msg_file_open_fail db "Failed to open file!", 0Dh, 0Ah, 0
    msg_file_read_fail db "Failed to read file!", 0Dh, 0Ah, 0
    msg_file_write_fail db "Failed to write file!", 0Dh, 0Ah, 0
    msg_file_close_fail db "Failed to close file!", 0Dh, 0Ah, 0
    msg_runtime_init_fail db "Failed to initialize runtime data!", 0Dh, 0Ah, 0

    ; UEFI File I/O related GUIDs (read-only)
    EFI_SIMPLE_FILE_SYSTEM_PROTOCOL_GUID: dd 0x964E5B22; dw 0x6459, 0x11D2; db 0x8E, 0x39, 0x00, 0xA0, 0xC9, 0x69, 0x72, 0x3B

section .text

;--------------------------------------------------------------------------
; uefi_AllocatePagesWrapper: Wrapper for UEFI AllocatePages service
; Input: RCX=Type, RDX=MemType, R8=Pages, R9=AddrPtr
; Output: RAX=Status, [R9]=PhysAddr if successful
;--------------------------------------------------------------------------
uefi_AllocatePagesWrapper:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    
    ; Save parameters
    mov r12, rcx    ; Type
    mov r13, rdx    ; MemType
    mov r14, r8     ; Pages
    mov r15, r9     ; AddrPtr
    
    ; Get main runtime data pointer
    call get_main_runtime_data
    test rax, rax
    jz .not_initialized
    
    ; Get system table
    mov rbx, [rax + OFFSET_SYSTEM_TABLE]
    test rbx, rbx
    jz .no_system_table
    
    ; Get boot services
    mov rbx, [rbx + OFFSET_ST_BOOTSERVICES]
    test rbx, rbx
    jz .no_boot_services
    
    ; Call AllocatePages
    ; RCX = Type
    ; RDX = MemType
    ; R8 = Pages
    ; R9 = AddrPtr
    mov rcx, r12
    mov rdx, r13
    mov r8, r14
    mov r9, r15
    
    ; Call through function pointer
    mov rax, [rbx + OFFSET_BS_ALLOCATEPAGES]
    call rax
    
    jmp .done
    
.not_initialized:
.no_system_table:
.no_boot_services:
    ; Return error
    mov rax, EFI_UNSUPPORTED
    
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

;--------------------------------------------------------------------------
; init_main_runtime_data: Allocate and initialize main runtime data
; Input: None
; Output: RAX = 0 on success, error code otherwise
;--------------------------------------------------------------------------
init_main_runtime_data:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    
    ; Check if already initialized
    mov rax, [rel main_runtime_data_ptr]
    test rax, rax
    jnz .already_initialized
    
    ; Allocate memory for main runtime data
    mov rdi, (MAIN_RUNTIME_DATA_SIZE + 4095) / 4096  ; Pages needed
    call pmm_alloc_frame
    test rax, rax
    jz .allocation_error
    
    ; Save pointer to allocated memory
    mov [rel main_runtime_data_ptr], rax
    mov rdi, rax
    
    ; Store self-reference at offset 0
    mov [rdi + OFFSET_MAIN_RUNTIME_PTR], rax
    
    ; Initialize all fields to 0
    mov rcx, MAIN_RUNTIME_DATA_SIZE / 8  ; Number of qwords
    lea rdi, [rdi + 8]  ; Skip the first qword (self-reference)
    xor rax, rax
    rep stosq
    
    ; Success
    xor rax, rax
    jmp .done
    
.already_initialized:
    ; Already initialized, return success
    xor rax, rax
    jmp .done
    
.allocation_error:
    ; Failed to allocate memory
    mov rax, 1
    
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

;--------------------------------------------------------------------------
; get_main_runtime_data: Get pointer to main runtime data
; Input: None
; Output: RAX = Pointer to main runtime data, 0 if not initialized
;--------------------------------------------------------------------------
get_main_runtime_data:
    mov rax, [rel main_runtime_data_ptr]
    ret

;--------------------------------------------------------------------------
; get_efi_image_base: Get EFI image base address
; Input: None
; Output: RAX = EFI image base address
;--------------------------------------------------------------------------
get_efi_image_base:
    push rbp
    mov rbp, rsp
    
    ; Get main runtime data pointer
    call get_main_runtime_data
    test rax, rax
    jz .not_initialized
    
    ; Return EFI image base
    mov rax, [rax + OFFSET_EFI_IMAGE_BASE]
    jmp .done
    
.not_initialized:
    ; Return 0 if not initialized
    xor rax, rax
    
.done:
    pop rbp
    ret

;--------------------------------------------------------------------------
; get_efi_image_size: Get EFI image size
; Input: None
; Output: RAX = EFI image size
;--------------------------------------------------------------------------
get_efi_image_size:
    push rbp
    mov rbp, rsp
    
    ; Get main runtime data pointer
    call get_main_runtime_data
    test rax, rax
    jz .not_initialized
    
    ; Return EFI image size
    mov rax, [rax + OFFSET_EFI_IMAGE_SIZE]
    jmp .done
    
.not_initialized:
    ; Return 0 if not initialized
    xor rax, rax
    
.done:
    pop rbp
    ret

;--------------------------------------------------------------------------
; get_key_buffer: Get pointer to key buffer
; Input: None
; Output: RAX = Pointer to key buffer
;--------------------------------------------------------------------------
get_key_buffer:
    push rbp
    mov rbp, rsp
    
    ; Get main runtime data pointer
    call get_main_runtime_data
    test rax, rax
    jz .not_initialized
    
    ; Return pointer to key buffer
    lea rax, [rax + OFFSET_KEY_BUFFER]
    jmp .done
    
.not_initialized:
    ; Return 0 if not initialized
    xor rax, rax
    
.done:
    pop rbp
    ret

;--------------------------------------------------------------------------
; get_key_buffer_head: Get pointer to key buffer head
; Input: None
; Output: RAX = Pointer to key buffer head
;--------------------------------------------------------------------------
get_key_buffer_head:
    push rbp
    mov rbp, rsp
    
    ; Get main runtime data pointer
    call get_main_runtime_data
    test rax, rax
    jz .not_initialized
    
    ; Return pointer to key buffer head
    lea rax, [rax + OFFSET_KEY_BUFFER_HEAD(KEY_BUFFER_SIZE)]
    jmp .done
    
.not_initialized:
    ; Return 0 if not initialized
    xor rax, rax
    
.done:
    pop rbp
    ret

;--------------------------------------------------------------------------
; get_key_buffer_tail: Get pointer to key buffer tail
; Input: None
; Output: RAX = Pointer to key buffer tail
;--------------------------------------------------------------------------
get_key_buffer_tail:
    push rbp
    mov rbp, rsp
    
    ; Get main runtime data pointer
    call get_main_runtime_data
    test rax, rax
    jz .not_initialized
    
    ; Return pointer to key buffer tail
    lea rax, [rax + OFFSET_KEY_BUFFER_TAIL(KEY_BUFFER_SIZE)]
    jmp .done
    
.not_initialized:
    ; Return 0 if not initialized
    xor rax, rax
    
.done:
    pop rbp
    ret

; --- Helper to unmask specific PIC IRQ line ---
pic_unmask_irq: ; Input: AL = IRQ line (0-15)
    push rax
    push rdx
    cmp al, 8
    jb .master_mask
.slave_mask:
    mov dx, PIC2_DATA ; Slave data port (0xA1)
    in al, dx         ; Read current mask
    mov ah, al        ; Save it
    pop rdx            ; Get IRQ line back into dl
    sub dl, 8         ; Convert to slave line number (0-7)
    mov al, 1
    push rcx
    mov cl, dl
    shl al, cl       ; Create bitmask
    pop rcx
    not al            ; Invert mask (0 to unmask)
    and ah, al        ; Clear the specific bit in saved mask
    mov al, ah        ; Move new mask to AL
    mov dx, PIC2_DATA
    out dx, al        ; Write new mask to slave PIC
    jmp .mask_done
.master_mask:
    mov dx, PIC1_DATA ; Master data port (0x21)
    in al, dx         ; Read current mask
    mov ah, al        ; Save it
    pop rdx            ; Get IRQ line back into dl
    mov al, 1
    push cx
    mov cl, dl
    shl al, cl        ; Create bitmask
    pop cx
    not al            ; Invert mask (0 to unmask)
    and ah, al        ; Clear the specific bit in saved mask
    mov al, ah        ; Move new mask to AL
    mov dx, PIC1_DATA
    out dx, al        ; Write new mask to master PIC
.mask_done:
    pop rdx
    pop rax
    ret

; --- Main UEFI Entry Point ---
efi_main:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    and rsp, -16
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    
    ; Initialize main runtime data
    call init_main_runtime_data
    test rax, rax
    jnz .runtime_init_fail
    
    ; Get main runtime data pointer
    call get_main_runtime_data
    mov r15, rax  ; Save pointer in R15
    
    ; Save image handle and system table
    mov [r15 + OFFSET_IMAGE_HANDLE], rdi
    mov [r15 + OFFSET_SYSTEM_TABLE], rsi

    ; 1. Print Welcome
    mov rcx, [r15 + OFFSET_SYSTEM_TABLE]
    lea rdx, [rel msg_welcome]
    call UefiPrint

    ; 2. Get Loaded Image Info
    mov rcx, [r15 + OFFSET_IMAGE_HANDLE]
    mov rdx, EFI_LOADED_IMAGE_PROTOCOL_GUID
    mov r8, rsp
    call UefiHandleProtocol
    test rax, rax
    jnz .loaded_image_fail
    mov rbx, [rsp]
    mov rax, [rbx + OFFSET_LOADED_IMAGE_IMAGEBASE]
    mov [r15 + OFFSET_EFI_IMAGE_BASE], rax
    mov rax, [rbx + OFFSET_LOADED_IMAGE_IMAGESIZE]
    mov [r15 + OFFSET_EFI_IMAGE_SIZE], rax
    mov rcx, [r15 + OFFSET_SYSTEM_TABLE]
    lea rdx, [rel msg_loaded_image_ok]
    call UefiPrint

    ; 3. Get GOP Info
    mov rcx, EFI_GRAPHICS_OUTPUT_PROTOCOL_GUID
    mov rdx, 0
    mov r8, rsp
    call UefiLocateProtocol
    test rax, rax
    jnz .gop_fail
    mov rbx, [rsp]
    mov rcx, [rbx + OFFSET_GOP_MODE]
    mov rax, [rcx + OFFSET_GOP_MODE_FBBASE]
    mov [gop_framebuffer_base], rax
    mov rax, [rcx + OFFSET_GOP_MODE_FBSIZE]
    mov [gop_framebuffer_size], rax
    mov rdx, [rcx + OFFSET_GOP_MODE_INFO]
    mov eax, [rdx + OFFSET_GOP_INFO_HRES]
    mov [gop_h_res], eax
    mov eax, [rdx + OFFSET_GOP_INFO_VRES]
    mov [gop_v_res], eax
    mov eax, [rdx + OFFSET_GOP_INFO_PIXELFMT]
    mov [gop_pixel_format], eax
    mov eax, [rdx + OFFSET_GOP_INFO_PIXELSPERSCANLINE]
    mov [gop_pixels_per_scanline], eax
    mov rcx, [r15 + OFFSET_SYSTEM_TABLE]
    lea rdx, [rel msg_gop_ok]
    call UefiPrint

    ; 3.5 Get File System Protocol
    mov rcx, EFI_SIMPLE_FILE_SYSTEM_PROTOCOL_GUID
    mov rdx, 0
    lea r8, [r15 + OFFSET_FILE_SYSTEM_PROTOCOL]
    call UefiLocateProtocol
    test rax, rax
    jnz .fs_fail
    
    ; Open Root Directory
    mov rbx, [r15 + OFFSET_FILE_SYSTEM_PROTOCOL]
    mov rax, [rbx + OFFSET_SFS_OPENVOLUME]
    mov rcx, rbx
    lea rdx, [r15 + OFFSET_ROOT_DIRECTORY]
    call rax
    test rax, rax
    jnz .root_dir_fail
    
    mov rcx, [r15 + OFFSET_SYSTEM_TABLE]
    lea rdx, [rel msg_root_dir_ok]
    call UefiPrint

    ; 4. Get Memory Map (First time)
    ; Allocate memory for memory map
    mov rcx, AllocateAnyPages
    mov rdx, EfiLoaderData
    mov r8, 4  ; 4 pages (16KB)
    lea r9, [r15 + OFFSET_MEMORY_MAP]
    call UefiAllocatePages
    test rax, rax
    jnz .memmap_fail
    
    ; Get memory map
    mov rcx, [r15 + OFFSET_MEMORY_MAP]
    mov qword [r15 + OFFSET_MEMORY_MAP_SIZE], 4096 * 4
    lea rdx, [r15 + OFFSET_MEMORY_MAP_SIZE]
    lea r8, [r15 + OFFSET_MAP_KEY]
    lea r9, [r15 + OFFSET_DESCRIPTOR_SIZE]
    push qword [r15 + OFFSET_DESCRIPTOR_VERSION]
    call UefiGetMemoryMap
    add rsp, 8  ; Clean up stack
    test rax, rax
    jnz .memmap_fail
    mov rcx, [r15 + OFFSET_SYSTEM_TABLE]
    lea rdx, [rel msg_memmap_ok]
    call UefiPrint

    ; 5. Allocate GDT/IDT memory
    mov rcx, AllocateAnyPages
    mov rdx, EfiLoaderData
    mov r8, 1
    lea r9, [r15 + OFFSET_FINAL_GDT_BASE]
    call UefiAllocatePages
    test rax, rax
    jnz .alloc_gdt_fail
    mov rcx, AllocateAnyPages
    mov rdx, EfiLoaderData
    mov r8, 1
    lea r9, [r15 + OFFSET_FINAL_IDT_BASE]
    call UefiAllocatePages
    test rax, rax
    jnz .alloc_idt_fail

    ; 6. Initialize PMM
    mov rcx, [r15 + OFFSET_MEMORY_MAP]
    mov rdx, [r15 + OFFSET_MEMORY_MAP_SIZE]
    mov r8, [r15 + OFFSET_DESCRIPTOR_SIZE]
    call pmm64_init_uefi
    test rax, rax
    jnz .pmm_fail
    mov rax, [r15 + OFFSET_FINAL_GDT_BASE]
    mov rdx, PAGE_SIZE_4K
    add rdx, rax
    call pmm_mark_region_used
    mov rax, [r15 + OFFSET_FINAL_IDT_BASE]
    mov rdx, PAGE_SIZE_4K
    add rdx, rax
    call pmm_mark_region_used
    mov rax, [gop_framebuffer_base]
    mov rdx, [gop_framebuffer_size]
    add rdx, rax
    call pmm_mark_region_used
    mov rcx, [r15 + OFFSET_SYSTEM_TABLE]
    lea rdx, [rel msg_pmm_ok]
    call UefiPrint

    ; 7. Load Kernel/Payload - Skipped

    ; 8. Setup Final Paging
    mov rcx, [r15 + OFFSET_MEMORY_MAP]
    mov rdx, [r15 + OFFSET_MEMORY_MAP_SIZE]
    mov r8, [r15 + OFFSET_DESCRIPTOR_SIZE]
    mov r9, kernel_pml4
    call paging_init_64_uefi
    test rax, rax
    jnz .paging_fail
    mov rcx, [r15 + OFFSET_SYSTEM_TABLE]
    lea rdx, [rel msg_paging_ok]
    call UefiPrint

    ; 9. Setup GDT Descriptors
    mov rdi, [r15 + OFFSET_FINAL_GDT_BASE]
    call setup_final_gdt64
    mov rcx, [r15 + OFFSET_SYSTEM_TABLE]
    lea rdx, [rel msg_gdt_ok]
    call UefiPrint

    ; 10. Get Memory Map AGAIN for ExitBootServices Key
    mov rcx, [r15 + OFFSET_MEMORY_MAP]
    lea rdx, [r15 + OFFSET_MEMORY_MAP_SIZE]
    lea r8, [r15 + OFFSET_MAP_KEY]
    lea r9, [r15 + OFFSET_DESCRIPTOR_SIZE]
    push qword [r15 + OFFSET_DESCRIPTOR_VERSION]
    call UefiGetMemoryMap
    add rsp, 8  ; Clean up stack
    test rax, rax
    jnz .memmap_fail

    ; 11. Exit Boot Services
    mov rcx, [r15 + OFFSET_IMAGE_HANDLE]
    mov rdx, [r15 + OFFSET_MAP_KEY]
    call UefiExitBootServices
    test rax, rax
    jnz .exit_bs_fail

    ; --- UEFI Boot Services are GONE ---

    ; 12. Load GDT/Segments, Init Screen
    call load_gdt_and_segments64
    mov rdi, [gop_framebuffer_base]
    mov esi, [gop_h_res]
    mov edx, [gop_v_res]
    mov ecx, [gop_pixels_per_scanline]
    mov r8d, [gop_pixel_format]
    call scr64_init
    lea rsi, [rel msg_post_exit]
    call scr64_print_string

    ; 13. Remap PIC
    call pic_remap
    lea rsi, [rel msg_pic_ok]
    call scr64_print_string

    ; 14. Setup IDT and Load
    mov rdi, [r15 + OFFSET_FINAL_IDT_BASE]
    call setup_final_idt64
    call load_idt64
    lea rsi, [rel msg_idt_ok]
    call scr64_print_string

    ; 15. Initialize PCI & AHCI
    call pci_init
    call pci_find_ahci_controller
    test rax, rax
    jz .ahci_fail
    mov [r15 + OFFSET_AHCI_BASE_ADDR], rax
    call ahci_init
    test rax, rax
    jnz .ahci_fail

    ; 16. Find FAT32 Partition (Placeholder)
    ; call FindFat32PartitionLba ; Needs implementation using AHCI
    ; test rax, rax; jnz .gpt_fail
    mov qword [r15 + OFFSET_FAT32_PARTITION_LBA], 2048 ;### HARCODED LBA FOR TESTING ###

    ; 17. Initialize FAT32
    mov rdi, [r15 + OFFSET_FAT32_PARTITION_LBA]
    mov edx, [r15 + OFFSET_AHCI_PORT_NUM]
    call fat32_init
    test rax, rax
    jnz .fat32_fail

    ; 18. Initialize Keyboard & Unmask IRQ
    call keyboard_init
    mov al, KB_IRQ ; Unmask Keyboard IRQ (IRQ 1)
    call pic_unmask_irq

    ; 19. Enable Interrupts
    sti

    ; 20. Jump to Shell
    lea rsi, [rel msg_jumping]
    call scr64_print_string
    call shell_run

    ; Should not return
    lea rsi, [rel msg_shell_return_err]
    call panic64

; --- Error Handling ---
.runtime_init_fail:
    lea rsi, [rel msg_runtime_init_fail]
    jmp .panic_or_print
.loaded_image_fail:
    lea rsi, [rel msg_loaded_image_fail]
    jmp .panic_or_print
.gop_fail: 
    lea rsi, [rel msg_gop_fail]
    jmp .panic_or_print
.fs_fail:
    lea rsi, [rel msg_fs_fail]
    jmp .panic_or_print
.root_dir_fail:
    lea rsi, [rel msg_root_dir_fail]
    jmp .panic_or_print
.memmap_fail:
    lea rsi, [rel msg_memmap_fail]
    jmp .panic_or_print
.alloc_gdt_fail:
    lea rsi, [rel msg_alloc_gdt_fail]
    jmp .panic_or_print
.alloc_idt_fail:
    lea rsi, [rel msg_alloc_idt_fail]
    jmp .panic_or_print
.pmm_fail:
    lea rsi, [rel msg_pmm_fail]
    jmp .panic_or_print
.paging_fail:
    lea rsi, [rel msg_paging_fail]
    jmp .panic_or_print
.exit_bs_fail:
    jmp .halt_critical ;Cannot print ExitBS failure reliably
.ahci_fail:
    lea rsi, [rel msg_ahci_fail]
    call scr64_print_string
    jmp .halt
.gpt_fail:
    lea rsi, [rel msg_gpt_fail]
    call scr64_print_string
    jmp .halt
.fat32_fail:
    lea rsi, [rel msg_fat32_fail]
    call scr64_print_string
    jmp .halt
.panic_or_print:
    mov rcx, [r15 + OFFSET_SYSTEM_TABLE]
    mov rdx, rsi
    call UefiPrint
    jmp .halt
.halt_critical: ; Halt when printing might not work
.halt:
    cli
.spin:
    hlt
    jmp .spin
.clean_exit:
    xor rax, rax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    add rsp, 64
    pop rbp
    ret

;--------------------------------------------------------------------------
; UefiPrint: Prints a null-terminated Unicode string.
; Input: RCX = (Ignored, uses gSystemTable)
;        RDX = Pointer to Null-terminated Unicode String
; Output: RAX = Status
;--------------------------------------------------------------------------
UefiPrint:
    push rbp
    mov rbp, rsp
    sub rsp, 32+8 ; Shadow space for 4 registers + 8 for alignment/scratch
    and rsp, -16  ; Ensure 16-byte alignment before call

    push rbx
    push rsi
    push rdi
    push r10 ; Using r10 for function pointer
    push r15 ; Save runtime data pointer

    ; Get main runtime data pointer
    call get_main_runtime_data
    mov r15, rax

    mov rsi, [r15 + OFFSET_SYSTEM_TABLE]
    test rsi, rsi
    jz .print_fail_no_systable

    mov rbx, [rsi + OFFSET_ST_CONOUT]
    test rbx, rbx
    jz .print_fail_no_conout

    mov r10, [rbx + OFFSET_CONOUT_OUTPUTSTRING]
    test r10, r10
    jz .print_fail_no_func

    ; Args for ConOut->OutputString:
    ; RCX = This (ConOut Protocol Pointer)
    ; RDX = String (Passed as input RDX)
    mov rcx, rbx
    ; RDX is already set
    call r10
    ; RAX holds status
    jmp .print_done

.print_fail_no_systable:
    mov rax, EFI_INVALID_PARAMETER ; SystemTable not set
    jmp .print_done
.print_fail_no_conout:
.print_fail_no_func:
    mov rax, EFI_UNSUPPORTED
.print_done:
    pop r15
    pop r10
    pop rdi
    pop rsi
    pop rbx
    add rsp, 32+8
    pop rbp
    ret

;--------------------------------------------------------------------------
; UefiHandleProtocol: Wrapper for EFI_BOOT_SERVICES.HandleProtocol
; Input: RCX = Handle
;        RDX = Protocol GUID
;        R8 = Interface pointer location
; Output: RAX = Status
;--------------------------------------------------------------------------
UefiHandleProtocol:
    push rbp
    mov rbp, rsp
    sub rsp, 32+8 ; Shadow space for 4 registers + 8 for alignment/scratch
    and rsp, -16  ; Ensure 16-byte alignment before call

    push rbx
    push rsi
    push rdi
    push r10 ; Using r10 for function pointer
    push r15 ; Save runtime data pointer

    ; Get main runtime data pointer
    call get_main_runtime_data
    mov r15, rax

    mov rsi, [r15 + OFFSET_SYSTEM_TABLE]
    test rsi, rsi
    jz .handle_fail_no_systable

    mov rbx, [rsi + OFFSET_ST_BOOTSERVICES]
    test rbx, rbx
    jz .handle_fail_no_bs

    mov r10, [rbx + OFFSET_BS_HANDLEPROTOCOL]
    test r10, r10
    jz .handle_fail_no_func

    ; Args for BootServices->HandleProtocol:
    ; RCX = Handle (already set)
    ; RDX = Protocol GUID (already set)
    ; R8 = Interface pointer location (already set)
    call r10
    ; RAX holds status
    jmp .handle_done

.handle_fail_no_systable:
.handle_fail_no_bs:
.handle_fail_no_func:
    mov rax, EFI_UNSUPPORTED
.handle_done:
    pop r15
    pop r10
    pop rdi
    pop rsi
    pop rbx
    add rsp, 32+8
    pop rbp
    ret

;--------------------------------------------------------------------------
; UefiLocateProtocol: Wrapper for EFI_BOOT_SERVICES.LocateProtocol
; Input: RCX = Protocol GUID
;        RDX = Registration (optional, can be NULL)
;        R8 = Interface pointer location
; Output: RAX = Status
;--------------------------------------------------------------------------
UefiLocateProtocol:
    push rbp
    mov rbp, rsp
    sub rsp, 32+8 ; Shadow space for 4 registers + 8 for alignment/scratch
    and rsp, -16  ; Ensure 16-byte alignment before call

    push rbx
    push rsi
    push rdi
    push r10 ; Using r10 for function pointer
    push r15 ; Save runtime data pointer

    ; Get main runtime data pointer
    call get_main_runtime_data
    mov r15, rax

    mov rsi, [r15 + OFFSET_SYSTEM_TABLE]
    test rsi, rsi
    jz .locate_fail_no_systable

    mov rbx, [rsi + OFFSET_ST_BOOTSERVICES]
    test rbx, rbx
    jz .locate_fail_no_bs

    mov r10, [rbx + OFFSET_BS_LOCATEPROTOCOL]
    test r10, r10
    jz .locate_fail_no_func

    ; Args for BootServices->LocateProtocol:
    ; RCX = Protocol GUID (already set)
    ; RDX = Registration (already set)
    ; R8 = Interface pointer location (already set)
    call r10
    ; RAX holds status
    jmp .locate_done

.locate_fail_no_systable:
.locate_fail_no_bs:
.locate_fail_no_func:
    mov rax, EFI_UNSUPPORTED
.locate_done:
    pop r15
    pop r10
    pop rdi
    pop rsi
    pop rbx
    add rsp, 32+8
    pop rbp
    ret

;--------------------------------------------------------------------------
; UefiGetMemoryMap: Wrapper for EFI_BOOT_SERVICES.GetMemoryMap
; Input: RCX = MemoryMapSize pointer
;        RDX = MemoryMap pointer
;        R8 = MapKey pointer
;        R9 = DescriptorSize pointer
;        [RSP+32] = DescriptorVersion pointer
; Output: RAX = Status
;--------------------------------------------------------------------------
UefiGetMemoryMap:
    push rbp
    mov rbp, rsp
    sub rsp, 32+8 ; Shadow space for 4 registers + 8 for alignment/scratch
    and rsp, -16  ; Ensure 16-byte alignment before call

    push rbx
    push rsi
    push rdi
    push r10 ; Using r10 for function pointer
    push r15 ; Save runtime data pointer

    ; Get main runtime data pointer
    call get_main_runtime_data
    mov r15, rax

    mov rsi, [r15 + OFFSET_SYSTEM_TABLE]
    test rsi, rsi
    jz .getmem_fail_no_systable

    mov rbx, [rsi + OFFSET_ST_BOOTSERVICES]
    test rbx, rbx
    jz .getmem_fail_no_bs

    mov r10, [rbx + OFFSET_BS_GETMEMORYMAP]
    test r10, r10
    jz .getmem_fail_no_func

    ; Args for BootServices->GetMemoryMap:
    ; RCX = MemoryMapSize pointer (already set)
    ; RDX = MemoryMap pointer (already set)
    ; R8 = MapKey pointer (already set)
    ; R9 = DescriptorSize pointer (already set)
    ; [RSP+32+40] = DescriptorVersion pointer (passed on stack)
    mov rax, [rbp+16] ; Get DescriptorVersion pointer from original stack position
    mov [rsp+32], rax ; Put it in the shadow space for the 5th parameter
    call r10
    ; RAX holds status
    jmp .getmem_done

.getmem_fail_no_systable:
.getmem_fail_no_bs:
.getmem_fail_no_func:
    mov rax, EFI_UNSUPPORTED
.getmem_done:
    pop r15
    pop r10
    pop rdi
    pop rsi
    pop rbx
    add rsp, 32+8
    pop rbp
    ret

;--------------------------------------------------------------------------
; UefiAllocatePages: Wrapper for EFI_BOOT_SERVICES.AllocatePages
; Input: RCX = AllocateType
;        RDX = MemoryType
;        R8 = Pages
;        R9 = Memory pointer location
; Output: RAX = Status
;--------------------------------------------------------------------------
UefiAllocatePages:
    push rbp
    mov rbp, rsp
    sub rsp, 32+8 ; Shadow space for 4 registers + 8 for alignment/scratch
    and rsp, -16  ; Ensure 16-byte alignment before call

    push rbx
    push rsi
    push rdi
    push r10 ; Using r10 for function pointer
    push r15 ; Save runtime data pointer

    ; Get main runtime data pointer
    call get_main_runtime_data
    mov r15, rax

    mov rsi, [r15 + OFFSET_SYSTEM_TABLE]
    test rsi, rsi
    jz .alloc_fail_no_systable

    mov rbx, [rsi + OFFSET_ST_BOOTSERVICES]
    test rbx, rbx
    jz .alloc_fail_no_bs

    mov r10, [rbx + OFFSET_BS_ALLOCATEPAGES]
    test r10, r10
    jz .alloc_fail_no_func

    ; Args for BootServices->AllocatePages:
    ; RCX = AllocateType (already set)
    ; RDX = MemoryType (already set)
    ; R8 = Pages (already set)
    ; R9 = Memory pointer location (already set)
    call r10
    ; RAX holds status
    jmp .alloc_done

.alloc_fail_no_systable:
.alloc_fail_no_bs:
.alloc_fail_no_func:
    mov rax, EFI_UNSUPPORTED
.alloc_done:
    pop r15
    pop r10
    pop rdi
    pop rsi
    pop rbx
    add rsp, 32+8
    pop rbp
    ret

;--------------------------------------------------------------------------
; UefiExitBootServices: Wrapper for EFI_BOOT_SERVICES.ExitBootServices
; Input: RCX = ImageHandle
;        RDX = MapKey
; Output: RAX = Status
;--------------------------------------------------------------------------
UefiExitBootServices:
    push rbp
    mov rbp, rsp
    sub rsp, 32+8 ; Shadow space for 4 registers + 8 for alignment/scratch
    and rsp, -16  ; Ensure 16-byte alignment before call

    push rbx
    push rsi
    push rdi
    push r10 ; Using r10 for function pointer
    push r15 ; Save runtime data pointer

    ; Get main runtime data pointer
    call get_main_runtime_data
    mov r15, rax

    mov rsi, [r15 + OFFSET_SYSTEM_TABLE]
    test rsi, rsi
    jz .exit_fail_no_systable

    mov rbx, [rsi + OFFSET_ST_BOOTSERVICES]
    test rbx, rbx
    jz .exit_fail_no_bs

    mov r10, [rbx + OFFSET_BS_EXITBOOTSERVICES]
    test r10, r10
    jz .exit_fail_no_func

    ; Args for BootServices->ExitBootServices:
    ; RCX = ImageHandle (already set)
    ; RDX = MapKey (already set)
    call r10
    ; RAX holds status
    jmp .exit_done

.exit_fail_no_systable:
.exit_fail_no_bs:
.exit_fail_no_func:
    mov rax, EFI_UNSUPPORTED
.exit_done:
    pop r15
    pop r10
    pop rdi
    pop rsi
    pop rbx
    add rsp, 32+8
    pop rbp
    ret
