; pmm64_pic.asm: UEFI-centric 64-bit Physical Memory Manager (PIC-compliant)
; Depends on: boot_defs_temp.inc (with UEFI defs)
; Depends on: boot_defs_uefi.inc (for additional UEFI definitions)

BITS 64
default rel
%include "boot_defs_temp.inc" ; Include UEFI defs!
%include "boot_defs_uefi.inc" ; Additional UEFI-specific definitions

; Globals defined/used by PMM
global pmm64_init_uefi, pmm_alloc_frame, pmm_free_frame
global pmm_alloc_frame_node, pmm_free_frame_node
global pmm_alloc_large_frame, pmm_free_large_frame
global pmm_mark_region_used, pmm_mark_region_free
global init_pmm_runtime_data
global get_pmm_total_frames, get_pmm_used_frames, get_pmm_max_ram_addr
global get_pmm_total_large_frames, get_pmm_used_large_frames
extern get_numa_node_count ; Use function-based accessor instead of direct variable

; External UEFI / System Info needed
extern uefi_AllocatePagesWrapper ; Assumed: RCX=Type, RDX=MemType, R8=Pages, R9=AddrPtr -> RAX=Status, [R9]=PhysAddr
extern get_efi_image_base       ; Physical base address of loaded EFI app
extern get_efi_image_size       ; Size of loaded EFI app in bytes
; extern AcpiParseSrat      ; Optional: extern void AcpiParseSrat(void); called before pmm init

%ifndef SMP
    %define SMP 0
%endif
%if SMP
    %define LOCK_PREFIX lock
%else
    %define LOCK_PREFIX
%endif

; Structure of runtime PMM data block:
; Offset 0:  pmm_runtime_data_ptr (qword)
; Offset 8:  pmm_total_frames (qword)
; Offset 16: pmm_used_frames (qword)
; Offset 24: pmm_total_large_frames (qword)
; Offset 32: pmm_used_large_frames (qword)
; Offset 40: pmm_max_ram_addr (qword)
; Offset 48: pmm_node_base_addrs[8] (8 qwords = 64 bytes)
; Offset 112: pmm_node_addr_limits[8] (8 qwords = 64 bytes)
; Offset 176: pmm_node_bitmaps[8] (8 qwords = 64 bytes)
; Offset 240: pmm_node_large_bitmaps[8] (8 qwords = 64 bytes)
; Offset 304: pmm_node_frame_counts[8] (8 qwords = 64 bytes)
; Offset 368: pmm_node_large_frame_counts[8] (8 qwords = 64 bytes)
; Offset 432: last_alloc_index_4k[8] (8 qwords = 64 bytes)
; Offset 496: last_alloc_index_large[8] (8 qwords = 64 bytes)
; Offset 560: page_size_4k_minus_1 (qword)
; Offset 568: page_size_2m_minus_1 (qword)
; Offset 576: temp_phys_addr (qword)
; Total size: 584 bytes

%define PMM_RUNTIME_DATA_SIZE 584

%define OFFSET_PMM_RUNTIME_PTR 0
%define OFFSET_PMM_TOTAL_FRAMES 8
%define OFFSET_PMM_USED_FRAMES 16
%define OFFSET_PMM_TOTAL_LARGE_FRAMES 24
%define OFFSET_PMM_USED_LARGE_FRAMES 32
%define OFFSET_PMM_MAX_RAM_ADDR 40
%define OFFSET_PMM_NODE_BASE_ADDRS 48
%define OFFSET_PMM_NODE_ADDR_LIMITS 112
%define OFFSET_PMM_NODE_BITMAPS 176
%define OFFSET_PMM_NODE_LARGE_BITMAPS 240
%define OFFSET_PMM_NODE_FRAME_COUNTS 304
%define OFFSET_PMM_NODE_LARGE_FRAME_COUNTS 368
%define OFFSET_LAST_ALLOC_INDEX_4K 432
%define OFFSET_LAST_ALLOC_INDEX_LARGE 496
%define OFFSET_PAGE_SIZE_4K_MINUS_1 560
%define OFFSET_PAGE_SIZE_2M_MINUS_1 568
%define OFFSET_TEMP_PHYS_ADDR 576

; Error codes for PMM init
PMM_INIT_ERR_OK         equ 0
PMM_INIT_ERR_NO_MEM     equ 1
PMM_INIT_ERR_ALLOC_FAIL equ 2
PMM_INIT_ERR_NUMA_CFG   equ 3
PMM_INIT_ERR_RUNTIME    equ 4

section .data
    ; Single global pointer to runtime allocated data
    pmm_runtime_data_ptr dq 0

section .text

;--------------------------------------------------------------------------
; init_pmm_runtime_data: Allocate and initialize PMM runtime data
; Input: None
; Output: RAX = 0 on success, error code otherwise
;--------------------------------------------------------------------------
init_pmm_runtime_data:
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
    mov rax, [rel pmm_runtime_data_ptr]
    test rax, rax
    jnz .already_initialized
    
    ; Allocate memory for PMM runtime data
    mov rdi, (PMM_RUNTIME_DATA_SIZE + 4095) / 4096  ; Pages needed
    call pmm_alloc_frame
    test rax, rax
    jz .allocation_error
    
    ; Save pointer to allocated memory
    mov [rel pmm_runtime_data_ptr], rax
    mov rdi, rax
    
    ; Store self-reference at offset 0
    mov [rdi + OFFSET_PMM_RUNTIME_PTR], rax
    
    ; Initialize all fields to 0
    mov rcx, PMM_RUNTIME_DATA_SIZE / 8  ; Number of qwords
    lea rdi, [rdi + 8]  ; Skip the first qword (self-reference)
    xor rax, rax
    rep stosq
    
    ; Initialize constants
    mov rax, [rel pmm_runtime_data_ptr]
    mov qword [rax + OFFSET_PAGE_SIZE_4K_MINUS_1], PAGE_SIZE_4K - 1
    mov qword [rax + OFFSET_PAGE_SIZE_2M_MINUS_1], PAGE_SIZE_2M - 1
    
    ; Success
    xor rax, rax
    jmp .done
    
.already_initialized:
    ; Already initialized, return success
    xor rax, rax
    jmp .done
    
.allocation_error:
    ; Failed to allocate memory
    mov rax, PMM_INIT_ERR_RUNTIME
    
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
; get_pmm_runtime_data: Get pointer to PMM runtime data
; Input: None
; Output: RAX = Pointer to PMM runtime data, 0 if not initialized
;--------------------------------------------------------------------------
get_pmm_runtime_data:
    mov rax, [rel pmm_runtime_data_ptr]
    ret

;--------------------------------------------------------------------------
; get_pmm_total_frames: Get total number of frames
; Input: None
; Output: RAX = Total number of frames
;--------------------------------------------------------------------------
get_pmm_total_frames:
    push rbp
    mov rbp, rsp
    
    ; Get PMM runtime data pointer
    call get_pmm_runtime_data
    test rax, rax
    jz .not_initialized
    
    ; Return total frames
    mov rax, [rax + OFFSET_PMM_TOTAL_FRAMES]
    jmp .done
    
.not_initialized:
    ; Return 0 if not initialized
    xor rax, rax
    
.done:
    pop rbp
    ret

;--------------------------------------------------------------------------
; get_pmm_used_frames: Get number of used frames
; Input: None
; Output: RAX = Number of used frames
;--------------------------------------------------------------------------
get_pmm_used_frames:
    push rbp
    mov rbp, rsp
    
    ; Get PMM runtime data pointer
    call get_pmm_runtime_data
    test rax, rax
    jz .not_initialized
    
    ; Return used frames
    mov rax, [rax + OFFSET_PMM_USED_FRAMES]
    jmp .done
    
.not_initialized:
    ; Return 0 if not initialized
    xor rax, rax
    
.done:
    pop rbp
    ret

;--------------------------------------------------------------------------
; get_pmm_max_ram_addr: Get maximum RAM address
; Input: None
; Output: RAX = Maximum RAM address
;--------------------------------------------------------------------------
get_pmm_max_ram_addr:
    push rbp
    mov rbp, rsp
    
    ; Get PMM runtime data pointer
    call get_pmm_runtime_data
    test rax, rax
    jz .not_initialized
    
    ; Return max RAM address
    mov rax, [rax + OFFSET_PMM_MAX_RAM_ADDR]
    jmp .done
    
.not_initialized:
    ; Return 0 if not initialized
    xor rax, rax
    
.done:
    pop rbp
    ret

;--------------------------------------------------------------------------
; get_pmm_total_large_frames: Get total number of large frames
; Input: None
; Output: RAX = Total number of large frames
;--------------------------------------------------------------------------
get_pmm_total_large_frames:
    push rbp
    mov rbp, rsp
    
    ; Get PMM runtime data pointer
    call get_pmm_runtime_data
    test rax, rax
    jz .not_initialized
    
    ; Return total large frames
    mov rax, [rax + OFFSET_PMM_TOTAL_LARGE_FRAMES]
    jmp .done
    
.not_initialized:
    ; Return 0 if not initialized
    xor rax, rax
    
.done:
    pop rbp
    ret

;--------------------------------------------------------------------------
; get_pmm_used_large_frames: Get number of used large frames
; Input: None
; Output: RAX = Number of used large frames
;--------------------------------------------------------------------------
get_pmm_used_large_frames:
    push rbp
    mov rbp, rsp
    
    ; Get PMM runtime data pointer
    call get_pmm_runtime_data
    test rax, rax
    jz .not_initialized
    
    ; Return used large frames
    mov rax, [rax + OFFSET_PMM_USED_LARGE_FRAMES]
    jmp .done
    
.not_initialized:
    ; Return 0 if not initialized
    xor rax, rax
    
.done:
    pop rbp
    ret

;-----------------------------------------------------------------------------
; pmm_get_node_for_addr: Determines NUMA node for a physical address
; Input: RDI = Physical Address
; Output: RAX = Node ID (0 to numa_node_count-1), or 0 if not found/single node
; Destroys: RCX, RDX
; Assumes pmm_node_base_addrs/limits are populated correctly.
;-----------------------------------------------------------------------------
pmm_get_node_for_addr:
    push rbp
    mov rbp, rsp
    push r15
    
    ; Get PMM runtime data pointer
    call get_pmm_runtime_data
    mov r15, rax
    test r15, r15
    jz .force_node_0
    
    call get_numa_node_count
    mov rcx, rax
    cmp rcx, 1
    jle .force_node_0       ; If only 0 or 1 node, always return 0

    xor rax, rax            ; Start checking Node 0
.node_check_loop:
    cmp rax, rcx
    jae .force_node_0       ; Address not found in any configured node range? Default to 0.

    mov rdx, [r15 + OFFSET_PMM_NODE_BASE_ADDRS + rax*8]
    cmp rdi, rdx
    jl .next_node           ; Address is lower than this node's base

    mov rdx, [r15 + OFFSET_PMM_NODE_ADDR_LIMITS + rax*8] ; Check against upper limit (exclusive)
    cmp rdi, rdx
    jge .next_node          ; Address is >= this node's limit

    ; Address is within the current node's range [base, limit)
    jmp .done               ; Return current Node ID in RAX

.next_node:
    inc rax
    jmp .node_check_loop

.force_node_0:
    xor rax, rax            ; Return Node 0
    
.done:
    pop r15
    pop rbp
    ret

;-----------------------------------------------------------------------------
; zero_physical_pages: Helper to zero contiguous physical pages
; Input: RDI = Start Physical address, RCX = Number of 4KB pages
; Destroys: RAX, RDI, RCX, RDX, YMM0 (if AVX used)
;-----------------------------------------------------------------------------
zero_physical_pages:
    test rcx, rcx
    jz .done_zero
    ; Calculate end address (exclusive)
    mov rdx, rcx
    shl rdx, 12 ; rdx = byte_count
    add rdx, rdi ; rdx = end address

.zero_loop:
    cmp rdi, rdx
    jae .done_zero
    ; Zero one page using rep stosq for simplicity/cycles if AVX not guaranteed
    push rcx ; Save outer loop count
    push rdi ; Save current page address
    xor eax, eax
    mov rcx, PAGE_SIZE_4K / 8
    rep stosq ; Zero using 64-bit stores
    pop rdi
    add rdi, PAGE_SIZE_4K ; Move RDI to start of next page
    pop rcx ; Restore outer loop count
    jmp .zero_loop
.done_zero:
    ret

;-----------------------------------------------------------------------------
; calculate_bitmap_size_pages: Calculates pages needed for a bitmap
; Input: RDI = number of frames to track
; Output: RAX = number of 4KB pages needed for the bitmap
; Destroys: RAX, RDX
;-----------------------------------------------------------------------------
calculate_bitmap_size_pages:
    mov rax, rdi ; frame_count
    add rax, 7   ; Add 7 for rounding up division by 8
    shr rax, 3   ; bytes needed = ceil(frame_count / 8)
    add rax, PAGE_SIZE_4K - 1 ; Add page_size-1 for rounding up division
    shr rax, 12  ; pages needed = ceil(bytes_needed / PAGE_SIZE_4K)
    ret

;-----------------------------------------------------------------------------
; mark_bitmap_region: Marks a range of bits in a bitmap
; Input: RDI = Bitmap phys base, RAX = Start frame idx, RDX = End frame idx (excl),
;        R8 = Total frames in node, R9 = Value (0=free, 1=used)
;-----------------------------------------------------------------------------
mark_bitmap_region:
    ; Bounds check start/end indices
    xor rcx, rcx
    cmp rax, rcx
    cmovl rax, rcx
    cmp rdx, r8
    cmovg rdx, r8
    cmp rax, rdx
    jae .done_mark

    mov rbx, rax
    shr rbx, 6
    mov cl, al
    and cl, 63 ; start qword/bit
    
    mov r10, rdx
    shr r10, 6
    mov r11d, edx
    and r11d, 63 ; end qword/bit (r10=end_q_idx, r11d=end_b_off)

    lea r12, [rdi + rbx*8] ; ptr to start qword

    test r9, r9
    jnz .mark_used

.mark_free: ; AND with inverted mask
    cmp rbx, r10
    jne .free_multi
    mov rax, -1
    mov rcx, -1
    mov r13d, ecx
    shl rax, cl
    test r11d, r11d
    jz .f_s_ne
    mov cl, 64
    sub cl, r11b
    shr rcx, cl
    and rax, rcx
.f_s_ne:
    not rax
    LOCK_PREFIX and qword [r12], rax
    jmp .done_mark
.free_multi:
    mov rax, -1
    shl rax, cl
    not rax
    LOCK_PREFIX and qword [r12], rax
    add r12, 8
    inc rbx
    mov rax, 0
.free_middle:
    cmp rbx, r10
    jae .free_last
    mov [r12], rax
    add r12, 8
    inc rbx
    jmp .free_middle
.free_last:
    test r11d, r11d
    jz .done_mark
    mov rax, -1
    mov cl, 64
    sub cl, r11b
    shr rax, cl
    not rax
    LOCK_PREFIX and qword [r12], rax
    jmp .done_mark

.mark_used: ; OR with mask
    cmp rbx, r10
    jne .used_multi
    mov rax, -1
    mov rcx, -1
    shl rax, cl
    test r11d, r11d
    jz .u_s_ne
    mov cl, 64
    sub cl, r11b
    shr rcx, cl
    and rax, rcx
.u_s_ne:
    LOCK_PREFIX or qword [r12], rax
    jmp .done_mark
.used_multi:
    mov rax, -1
    shl rax, cl
    LOCK_PREFIX or qword [r12], rax
    add r12, 8
    inc rbx
    mov rax, -1
.used_middle:
    cmp rbx, r10
    jae .used_last
    mov [r12], rax
    add r12, 8
    inc rbx
    jmp .used_middle
.used_last:
    test r11d, r11d
    jz .done_mark
    mov rax, -1
    mov cl, 64
    sub cl, r11b
    shr rax, cl
    LOCK_PREFIX or qword [r12], rax

.done_mark:
    ret

;-----------------------------------------------------------------------------
; pmm64_init_uefi: Initialize PMM using UEFI Memory Map.
; Input: RCX=MapPtr, RDX=MapSize, R8=DescSize
; Output: RAX=Status (0=OK)
;-----------------------------------------------------------------------------
pmm64_init_uefi:
    push rbp
    mov rbp, rsp
    sub rsp, 8
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; Initialize PMM runtime data
    call init_pmm_runtime_data
    test rax, rax
    jnz .fail_runtime_init
    
    ; Get PMM runtime data pointer
    call get_pmm_runtime_data
    mov r15, rax  ; Save pointer in R15

    mov r12, rcx
    mov r13, rdx
    mov r14, r8 ; Store inputs
    
    mov qword [r15 + OFFSET_PMM_TOTAL_FRAMES], 0
    mov qword [r15 + OFFSET_PMM_TOTAL_LARGE_FRAMES], 0
    
    call get_numa_node_count
    mov rcx, rax
    lea rdi, [r15 + OFFSET_PMM_NODE_FRAME_COUNTS]
    xor eax, eax
    push rcx
    rep stosq
    
    lea rdi, [r15 + OFFSET_PMM_NODE_LARGE_FRAME_COUNTS]
    pop rcx
    push rcx
    rep stosq
    pop rcx

    mov rbx, r12
    mov r9, r13 ; Ptr and remaining size
.calc_loop: ; Phase 1: Calculate sizes
    cmp r9, r14
    jl .calc_done
    
    mov edi, [rbx + EFI_MEMORY_DESCRIPTOR.Type]
    mov rsi, [rbx + EFI_MEMORY_DESCRIPTOR.PhysicalStart]
    mov r10, [rbx + EFI_MEMORY_DESCRIPTOR.NumberOfPages]
    mov rax, r10
    shl rax, 12
    add rax, rsi
    
    ; Update max addr if needed
    mov rcx, [r15 + OFFSET_PMM_MAX_RAM_ADDR]
    cmp rax, rcx
    jbe .skip_max_update
    mov [r15 + OFFSET_PMM_MAX_RAM_ADDR], rax
.skip_max_update:
    
    cmp edi, EfiConventionalMemory
    jne .next_calc_desc
    
    ; Add to total frames
    mov rcx, [r15 + OFFSET_PMM_TOTAL_FRAMES]
    add rcx, r10
    mov [r15 + OFFSET_PMM_TOTAL_FRAMES], rcx
    
    push rsi
    push r10
    mov rdi, rsi
    call pmm_get_node_for_addr
    mov rcx, rax  ; node_id in rcx
    pop r10
    pop rsi
    
    ; Add to node frame counts
    mov rax, [r15 + OFFSET_PMM_NODE_FRAME_COUNTS + rcx*8]
    add rax, r10
    mov [r15 + OFFSET_PMM_NODE_FRAME_COUNTS + rcx*8], rax
    
.next_calc_desc:
    add rbx, r14
    sub r9, r14
    jmp .calc_loop
    
.calc_done:
    cmp qword [r15 + OFFSET_PMM_TOTAL_FRAMES], 0
    je .fail_no_mem

    call get_numa_node_count
    mov rcx, rax
    xor rbx, rbx ; Node index
.calc_large_loop: ; Calculate large counts
    cmp rbx, rcx
    jae .calc_large_done
    
    mov rax, [r15 + OFFSET_PMM_NODE_FRAME_COUNTS + rbx*8]
    mov rdx, rax
    shr rdx, 9
    mov [r15 + OFFSET_PMM_NODE_LARGE_FRAME_COUNTS + rbx*8], rdx
    
    ; Add to total large frames
    mov rax, [r15 + OFFSET_PMM_TOTAL_LARGE_FRAMES]
    add rax, rdx
    mov [r15 + OFFSET_PMM_TOTAL_LARGE_FRAMES], rax
    
    inc rbx
    jmp .calc_large_loop
    
.calc_large_done:

    call get_numa_node_count
    mov rcx, rax
    xor rbx, rbx ; Node index
.alloc_bitmap_loop: ; Phase 2: Allocate bitmaps
    cmp rbx, rcx
    jae .alloc_bitmaps_done
    
    mov rdi, [r15 + OFFSET_PMM_NODE_FRAME_COUNTS + rbx*8]
    test rdi, rdi
    jz .skip_4k_alloc
    
    call calculate_bitmap_size_pages
    mov r8, rax
    test r8, r8
    jz .skip_4k_alloc
    
    mov r10, rcx
    mov r11, rdx
    mov rcx, AllocateAnyPages
    mov rdx, EfiLoaderData
    lea r9, [r15 + OFFSET_TEMP_PHYS_ADDR]
    call uefi_AllocatePagesWrapper
    mov rcx, r10
    mov rdx, r11
    test rax, rax
    jnz .fail_alloc
    
    mov rdi, [r15 + OFFSET_TEMP_PHYS_ADDR]
    mov [r15 + OFFSET_PMM_NODE_BITMAPS + rbx*8], rdi
    push rbx
    push rcx
    mov rcx, r8
    call zero_physical_pages
    pop rcx
    pop rbx
    
.skip_4k_alloc:
    mov rdi, [r15 + OFFSET_PMM_NODE_LARGE_FRAME_COUNTS + rbx*8]
    test rdi, rdi
    jz .skip_large_alloc
    
    call calculate_bitmap_size_pages
    mov r8, rax
    test r8, r8
    jz .skip_large_alloc
    
    mov r10, rcx
    mov r11, rdx
    mov rcx, AllocateAnyPages
    mov rdx, EfiLoaderData
    lea r9, [r15 + OFFSET_TEMP_PHYS_ADDR]
    call uefi_AllocatePagesWrapper
    mov rcx, r10
    mov rdx, r11
    test rax, rax
    jnz .fail_alloc
    
    mov rdi, [r15 + OFFSET_TEMP_PHYS_ADDR]
    mov [r15 + OFFSET_PMM_NODE_LARGE_BITMAPS + rbx*8], rdi
    push rbx
    push rcx
    mov rcx, r8
    call zero_physical_pages
    pop rcx
    pop rbx
    
.skip_large_alloc:
    inc rbx
    jmp .alloc_bitmap_loop
    
.alloc_bitmaps_done:

    call get_numa_node_count
    mov rcx, rax
    xor rbx, rbx ; Node index
.init_bitmap_loop: ; Phase 3: Mark all used
    cmp rbx, rcx
    jae .init_bitmaps_done
    
    mov rdi, [r15 + OFFSET_PMM_NODE_BITMAPS + rbx*8]
    test rdi, rdi
    jz .next_init_bitmap_part
    
    mov rsi, [r15 + OFFSET_PMM_NODE_FRAME_COUNTS + rbx*8]
    add rsi, 63
    shr rsi, 6
    test rsi, rsi
    jz .next_init_bitmap_part
    
    mov rax, -1
    push rcx
    push rbx
    mov rcx, rsi
    rep stosq
    pop rbx
    pop rcx
    
.next_init_bitmap_part:
    mov rdi, [r15 + OFFSET_PMM_NODE_LARGE_BITMAPS + rbx*8]
    test rdi, rdi
    jz .next_init_node
    
    mov rsi, [r15 + OFFSET_PMM_NODE_LARGE_FRAME_COUNTS + rbx*8]
    add rsi, 63
    shr rsi, 6
    test rsi, rsi
    jz .next_init_node
    
    mov rax, -1
    push rcx
    push rbx
    mov rcx, rsi
    rep stosq
    pop rbx
    pop rcx
    
.next_init_node:
    inc rbx
    jmp .init_bitmap_loop
    
.init_bitmaps_done:

    mov rbx, r12
    mov r9, r13 ; Ptr and remaining size
.free_conv_loop: ; Phase 4: Free conventional memory
    cmp r9, r14
    jl .free_conv_done
    
    mov edi, [rbx + EFI_MEMORY_DESCRIPTOR.Type]
    cmp edi, EfiConventionalMemory
    jne .next_free_desc
    
    mov rsi, [rbx + EFI_MEMORY_DESCRIPTOR.PhysicalStart]
    mov r10, [rbx + EFI_MEMORY_DESCRIPTOR.NumberOfPages]
    mov rax, rsi
    mov rdx, r10
    shl rdx, 12
    add rdx, rax
    call pmm_mark_region_free
    
.next_free_desc:
    add rbx, r14
    sub r9, r14
    jmp .free_conv_loop
    
.free_conv_done:

    ; Phase 5: Mark critical regions used
    call get_efi_image_base
    mov rdi, rax
    call get_efi_image_size
    mov rsi, rax
    mov rax, rdi
    mov rdx, rsi
    add rdx, rax
    call pmm_mark_region_used
    
    call get_numa_node_count
    mov rcx, rax
    xor rbx, rbx
.mark_bitmap_loop:
    cmp rbx, rcx
    jae .mark_bitmaps_done
    
    mov rax, [r15 + OFFSET_PMM_NODE_BITMAPS + rbx*8]
    test rax, rax
    jz .next_mark_bitmap_part
    
    mov rdi, [r15 + OFFSET_PMM_NODE_FRAME_COUNTS + rbx*8]
    call calculate_bitmap_size_pages
    mov rdx, rax
    shl rdx, 12
    add rdx, rax
    call pmm_mark_region_used
    
.next_mark_bitmap_part:
    mov rax, [r15 + OFFSET_PMM_NODE_LARGE_BITMAPS + rbx*8]
    test rax, rax
    jz .next_mark_node
    
    mov rdi, [r15 + OFFSET_PMM_NODE_LARGE_FRAME_COUNTS + rbx*8]
    call calculate_bitmap_size_pages
    mov rdx, rax
    shl rdx, 12
    add rdx, rax
    call pmm_mark_region_used
    
.next_mark_node:
    inc rbx
    jmp .mark_bitmap_loop
    
.mark_bitmaps_done:

    mov rax, PMM_INIT_ERR_OK
    jmp .exit
    
.fail_runtime_init:
    mov rax, PMM_INIT_ERR_RUNTIME
    jmp .exit_final
    
.fail_no_mem:
    mov rax, PMM_INIT_ERR_NO_MEM
    jmp .exit_final
    
.fail_alloc:
    mov rax, PMM_INIT_ERR_ALLOC_FAIL
    jmp .exit_final
    
.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    add rsp, 8
    pop rbp
    
.exit_final:
    ret

;-----------------------------------------------------------------------------
; pmm_mark_region_used: Mark a physical memory region as used
; Input: RAX = Start physical address, RDX = End physical address (exclusive)
; Output: None
; Destroys: RAX, RCX, RDX, RDI, RSI, R8, R9, R10, R11
;-----------------------------------------------------------------------------
pmm_mark_region_used:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    
    ; Get PMM runtime data pointer
    call get_pmm_runtime_data
    mov r15, rax
    test r15, r15
    jz .done
    
    ; Align addresses to page boundaries
    mov rcx, [r15 + OFFSET_PAGE_SIZE_4K_MINUS_1]
    add rax, rcx
    not rcx
    and rax, rcx ; rax = aligned_start
    
    mov rcx, [r15 + OFFSET_PAGE_SIZE_4K_MINUS_1]
    not rcx
    and rdx, rcx ; rdx = aligned_end
    
    cmp rax, rdx
    jae .done ; Empty region after alignment
    
    ; Calculate frame indices
    mov rdi, rax
    shr rdi, 12 ; start_frame_idx
    mov rsi, rdx
    shr rsi, 12 ; end_frame_idx
    
    ; Get node for this address range
    push rax
    push rdx
    push rdi
    push rsi
    mov rdi, rax
    call pmm_get_node_for_addr
    mov rbx, rax ; node_id
    pop rsi
    pop rdi
    pop rdx
    pop rax
    
    ; Mark 4K frames as used
    mov r8, [r15 + OFFSET_PMM_NODE_FRAME_COUNTS + rbx*8]
    mov r9, 1 ; mark as used
    mov r10, [r15 + OFFSET_PMM_NODE_BITMAPS + rbx*8]
    test r10, r10
    jz .skip_4k_mark
    
    ; Adjust frame indices relative to node base
    mov r11, [r15 + OFFSET_PMM_NODE_BASE_ADDRS + rbx*8]
    shr r11, 12 ; node_base_frame
    sub rdi, r11 ; start_frame_idx relative to node
    sub rsi, r11 ; end_frame_idx relative to node
    
    ; Mark the bitmap region
    mov rdi, r10 ; bitmap base
    mov rax, rdi ; start_frame_idx
    mov rdx, rsi ; end_frame_idx
    call mark_bitmap_region
    
    ; Update used frames count
    mov rax, rsi
    sub rax, rdi ; frames_marked = end_idx - start_idx
    mov rcx, [r15 + OFFSET_PMM_USED_FRAMES]
    add rcx, rax
    mov [r15 + OFFSET_PMM_USED_FRAMES], rcx
    
.skip_4k_mark:
    ; Mark 2M frames if applicable
    mov rax, [r15 + OFFSET_PAGE_SIZE_2M_MINUS_1]
    add rax, 1 ; 2M
    
    ; Check if region spans at least one 2M page
    mov rcx, rdx
    sub rcx, rax ; end - 2M
    cmp rcx, rax ; if end-2M < start, no 2M pages
    jl .done
    
    ; Align to 2M boundaries
    mov rcx, [r15 + OFFSET_PAGE_SIZE_2M_MINUS_1]
    add rax, rcx
    not rcx
    and rax, rcx ; rax = 2M_aligned_start
    
    mov rcx, [r15 + OFFSET_PAGE_SIZE_2M_MINUS_1]
    not rcx
    and rdx, rcx ; rdx = 2M_aligned_end
    
    cmp rax, rdx
    jae .done ; No 2M pages after alignment
    
    ; Calculate 2M frame indices
    mov rdi, rax
    shr rdi, 21 ; start_large_frame_idx
    mov rsi, rdx
    shr rsi, 21 ; end_large_frame_idx
    
    ; Mark 2M frames as used
    mov r8, [r15 + OFFSET_PMM_NODE_LARGE_FRAME_COUNTS + rbx*8]
    mov r9, 1 ; mark as used
    mov r10, [r15 + OFFSET_PMM_NODE_LARGE_BITMAPS + rbx*8]
    test r10, r10
    jz .done
    
    ; Adjust frame indices relative to node base
    mov r11, [r15 + OFFSET_PMM_NODE_BASE_ADDRS + rbx*8]
    shr r11, 21 ; node_base_large_frame
    sub rdi, r11 ; start_large_frame_idx relative to node
    sub rsi, r11 ; end_large_frame_idx relative to node
    
    ; Mark the bitmap region
    mov rdi, r10 ; large bitmap base
    mov rax, rdi ; start_large_frame_idx
    mov rdx, rsi ; end_large_frame_idx
    call mark_bitmap_region
    
    ; Update used large frames count
    mov rax, rsi
    sub rax, rdi ; frames_marked = end_idx - start_idx
    mov rcx, [r15 + OFFSET_PMM_USED_LARGE_FRAMES]
    add rcx, rax
    mov [r15 + OFFSET_PMM_USED_LARGE_FRAMES], rcx
    
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; pmm_mark_region_free: Mark a physical memory region as free
; Input: RAX = Start physical address, RDX = End physical address (exclusive)
; Output: None
; Destroys: RAX, RCX, RDX, RDI, RSI, R8, R9, R10, R11
;-----------------------------------------------------------------------------
pmm_mark_region_free:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    
    ; Get PMM runtime data pointer
    call get_pmm_runtime_data
    mov r15, rax
    test r15, r15
    jz .done
    
    ; Align addresses to page boundaries
    mov rcx, [r15 + OFFSET_PAGE_SIZE_4K_MINUS_1]
    add rax, rcx
    not rcx
    and rax, rcx ; rax = aligned_start
    
    mov rcx, [r15 + OFFSET_PAGE_SIZE_4K_MINUS_1]
    not rcx
    and rdx, rcx ; rdx = aligned_end
    
    cmp rax, rdx
    jae .done ; Empty region after alignment
    
    ; Calculate frame indices
    mov rdi, rax
    shr rdi, 12 ; start_frame_idx
    mov rsi, rdx
    shr rsi, 12 ; end_frame_idx
    
    ; Get node for this address range
    push rax
    push rdx
    push rdi
    push rsi
    mov rdi, rax
    call pmm_get_node_for_addr
    mov rbx, rax ; node_id
    pop rsi
    pop rdi
    pop rdx
    pop rax
    
    ; Mark 4K frames as free
    mov r8, [r15 + OFFSET_PMM_NODE_FRAME_COUNTS + rbx*8]
    mov r9, 0 ; mark as free
    mov r10, [r15 + OFFSET_PMM_NODE_BITMAPS + rbx*8]
    test r10, r10
    jz .skip_4k_mark
    
    ; Adjust frame indices relative to node base
    mov r11, [r15 + OFFSET_PMM_NODE_BASE_ADDRS + rbx*8]
    shr r11, 12 ; node_base_frame
    sub rdi, r11 ; start_frame_idx relative to node
    sub rsi, r11 ; end_frame_idx relative to node
    
    ; Mark the bitmap region
    mov rdi, r10 ; bitmap base
    mov rax, rdi ; start_frame_idx
    mov rdx, rsi ; end_frame_idx
    call mark_bitmap_region
    
    ; Update used frames count
    mov rax, rsi
    sub rax, rdi ; frames_marked = end_idx - start_idx
    mov rcx, [r15 + OFFSET_PMM_USED_FRAMES]
    sub rcx, rax
    mov [r15 + OFFSET_PMM_USED_FRAMES], rcx
    
.skip_4k_mark:
    ; Mark 2M frames if applicable
    mov rax, [r15 + OFFSET_PAGE_SIZE_2M_MINUS_1]
    add rax, 1 ; 2M
    
    ; Check if region spans at least one 2M page
    mov rcx, rdx
    sub rcx, rax ; end - 2M
    cmp rcx, rax ; if end-2M < start, no 2M pages
    jl .done
    
    ; Align to 2M boundaries
    mov rcx, [r15 + OFFSET_PAGE_SIZE_2M_MINUS_1]
    add rax, rcx
    not rcx
    and rax, rcx ; rax = 2M_aligned_start
    
    mov rcx, [r15 + OFFSET_PAGE_SIZE_2M_MINUS_1]
    not rcx
    and rdx, rcx ; rdx = 2M_aligned_end
    
    cmp rax, rdx
    jae .done ; No 2M pages after alignment
    
    ; Calculate 2M frame indices
    mov rdi, rax
    shr rdi, 21 ; start_large_frame_idx
    mov rsi, rdx
    shr rsi, 21 ; end_large_frame_idx
    
    ; Mark 2M frames as free
    mov r8, [r15 + OFFSET_PMM_NODE_LARGE_FRAME_COUNTS + rbx*8]
    mov r9, 0 ; mark as free
    mov r10, [r15 + OFFSET_PMM_NODE_LARGE_BITMAPS + rbx*8]
    test r10, r10
    jz .done
    
    ; Adjust frame indices relative to node base
    mov r11, [r15 + OFFSET_PMM_NODE_BASE_ADDRS + rbx*8]
    shr r11, 21 ; node_base_large_frame
    sub rdi, r11 ; start_large_frame_idx relative to node
    sub rsi, r11 ; end_large_frame_idx relative to node
    
    ; Mark the bitmap region
    mov rdi, r10 ; large bitmap base
    mov rax, rdi ; start_large_frame_idx
    mov rdx, rsi ; end_large_frame_idx
    call mark_bitmap_region
    
    ; Update used large frames count
    mov rax, rsi
    sub rax, rdi ; frames_marked = end_idx - start_idx
    mov rcx, [r15 + OFFSET_PMM_USED_LARGE_FRAMES]
    sub rcx, rax
    mov [r15 + OFFSET_PMM_USED_LARGE_FRAMES], rcx
    
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; pmm_alloc_frame_node: Allocate a 4KB physical memory frame from specific node
; Input: RCX = Node ID (-1 for any)
; Output: RAX = Physical address of allocated frame, 0 if failed
; Destroys: RCX, RDX, RDI, RSI, R8, R9, R10, R11
;-----------------------------------------------------------------------------
pmm_alloc_frame_node:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    
    ; Get PMM runtime data pointer
    call get_pmm_runtime_data
    mov r15, rax
    test r15, r15
    jz .fail
    
    ; Check if node ID is valid
    call get_numa_node_count
    mov r8, rax
    cmp rcx, r8
    jae .try_any_node
    
    cmp rcx, 0
    jl .try_any_node
    
    ; Try to allocate from specified node
    mov rbx, rcx
    jmp .try_node
    
.try_any_node:
    ; Try each node in sequence
    xor rbx, rbx ; Start with node 0
    
.try_next_node:
    cmp rbx, r8
    jae .fail ; No free frames in any node
    
.try_node:
    ; Check if node has frames
    mov rdi, [r15 + OFFSET_PMM_NODE_FRAME_COUNTS + rbx*8]
    test rdi, rdi
    jz .next_node
    
    ; Check if node has bitmap
    mov rsi, [r15 + OFFSET_PMM_NODE_BITMAPS + rbx*8]
    test rsi, rsi
    jz .next_node
    
    ; Start search from last allocation hint
    mov rdx, [r15 + OFFSET_LAST_ALLOC_INDEX_4K + rbx*8]
    
    ; Calculate bitmap size in qwords
    mov r9, rdi
    add r9, 63
    shr r9, 6 ; qwords in bitmap
    
    ; Search for a free bit
    mov r10, rdx ; Current qword index
    
.search_loop:
    cmp r10, r9
    jae .wrap_search
    
    mov rax, [rsi + r10*8]
    not rax ; Invert to find free frames (0 bits)
    test rax, rax
    jnz .found_free_qword
    
    inc r10
    jmp .search_loop
    
.wrap_search:
    ; Wrap around to beginning of bitmap
    xor r10, r10
    
.wrap_search_loop:
    cmp r10, rdx
    jae .next_node ; Searched entire bitmap, no free frames
    
    mov rax, [rsi + r10*8]
    not rax ; Invert to find free frames (0 bits)
    test rax, rax
    jnz .found_free_qword
    
    inc r10
    jmp .wrap_search_loop
    
.found_free_qword:
    ; Find first free bit in qword
    bsf r11, rax ; Bit scan forward
    
    ; Calculate frame index
    mov rax, r10
    shl rax, 6
    add rax, r11
    
    ; Check if frame index is valid
    cmp rax, rdi
    jae .next_node ; Frame index out of bounds
    
    ; Mark frame as used
    mov rdx, 1
    mov ecx, r11d
    shl rdx, cl
    LOCK_PREFIX or qword [rsi + r10*8], rdx
    
    ; Update last allocation hint
    mov [r15 + OFFSET_LAST_ALLOC_INDEX_4K + rbx*8], r10
    
    ; Update used frames count
    mov rcx, [r15 + OFFSET_PMM_USED_FRAMES]
    inc rcx
    mov [r15 + OFFSET_PMM_USED_FRAMES], rcx
    
    ; Calculate physical address
    mov rdx, [r15 + OFFSET_PMM_NODE_BASE_ADDRS + rbx*8]
    shl rax, 12 ; Convert frame index to byte offset
    add rax, rdx ; Add node base address
    
    jmp .done
    
.next_node:
    inc rbx
    jmp .try_next_node
    
.fail:
    xor rax, rax
    
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; pmm_alloc_frame: Allocate a 4KB physical memory frame from any node
; Input: None
; Output: RAX = Physical address of allocated frame, 0 if failed
; Destroys: RCX, RDX, RDI, RSI, R8, R9, R10, R11
;-----------------------------------------------------------------------------
pmm_alloc_frame:
    mov rcx, -1 ; Any node
    jmp pmm_alloc_frame_node

;-----------------------------------------------------------------------------
; pmm_free_frame_node: Free a 4KB physical memory frame
; Input: RDI = Physical address of frame to free
; Output: None
; Destroys: RAX, RCX, RDX, RDI, RSI, R8, R9, R10, R11
;-----------------------------------------------------------------------------
pmm_free_frame_node:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    
    ; Get PMM runtime data pointer
    call get_pmm_runtime_data
    mov r15, rax
    test r15, r15
    jz .done
    
    ; Align address to page boundary
    mov rax, [r15 + OFFSET_PAGE_SIZE_4K_MINUS_1]
    not rax
    and rdi, rax
    
    ; Get node for this address
    push rdi
    call pmm_get_node_for_addr
    mov rbx, rax ; node_id
    pop rdi
    
    ; Check if node has bitmap
    mov rsi, [r15 + OFFSET_PMM_NODE_BITMAPS + rbx*8]
    test rsi, rsi
    jz .done
    
    ; Calculate frame index relative to node base
    mov rax, [r15 + OFFSET_PMM_NODE_BASE_ADDRS + rbx*8]
    sub rdi, rax ; Offset from node base
    shr rdi, 12 ; Convert to frame index
    
    ; Check if frame index is valid
    cmp rdi, [r15 + OFFSET_PMM_NODE_FRAME_COUNTS + rbx*8]
    jae .done ; Frame index out of bounds
    
    ; Calculate qword index and bit position
    mov rax, rdi
    shr rax, 6 ; qword index
    mov rdx, rdi
    and rdx, 63 ; bit position
    
    ; Check if frame is already free
    mov r8, 1
    mov ecx, edx
    shl r8, cl
    mov r9, [rsi + rax*8]
    test r9, r8
    jz .done ; Frame already free
    
    ; Mark frame as free
    not r8
    LOCK_PREFIX and qword [rsi + rax*8], r8
    
    ; Update used frames count
    mov rcx, [r15 + OFFSET_PMM_USED_FRAMES]
    dec rcx
    mov [r15 + OFFSET_PMM_USED_FRAMES], rcx
    
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; pmm_free_frame: Free a 4KB physical memory frame
; Input: RDI = Physical address of frame to free
; Output: None
; Destroys: RAX, RCX, RDX, RDI, RSI, R8, R9, R10, R11
;-----------------------------------------------------------------------------
pmm_free_frame:
    jmp pmm_free_frame_node

;-----------------------------------------------------------------------------
; pmm_alloc_large_frame: Allocate a 2MB physical memory frame
; Input: RCX = Node ID (-1 for any)
; Output: RAX = Physical address of allocated frame, 0 if failed
; Destroys: RCX, RDX, RDI, RSI, R8, R9, R10, R11
;-----------------------------------------------------------------------------
pmm_alloc_large_frame:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    
    ; Get PMM runtime data pointer
    call get_pmm_runtime_data
    mov r15, rax
    test r15, r15
    jz .fail
    
    ; Check if node ID is valid
    call get_numa_node_count
    mov r8, rax
    cmp rcx, r8
    jae .try_any_node
    
    cmp rcx, 0
    jl .try_any_node
    
    ; Try to allocate from specified node
    mov rbx, rcx
    jmp .try_node
    
.try_any_node:
    ; Try each node in sequence
    xor rbx, rbx ; Start with node 0
    
.try_next_node:
    cmp rbx, r8
    jae .fail ; No free frames in any node
    
.try_node:
    ; Check if node has large frames
    mov rdi, [r15 + OFFSET_PMM_NODE_LARGE_FRAME_COUNTS + rbx*8]
    test rdi, rdi
    jz .next_node
    
    ; Check if node has large bitmap
    mov rsi, [r15 + OFFSET_PMM_NODE_LARGE_BITMAPS + rbx*8]
    test rsi, rsi
    jz .next_node
    
    ; Start search from last allocation hint
    mov rdx, [r15 + OFFSET_LAST_ALLOC_INDEX_LARGE + rbx*8]
    
    ; Calculate bitmap size in qwords
    mov r9, rdi
    add r9, 63
    shr r9, 6 ; qwords in bitmap
    
    ; Search for a free bit
    mov r10, rdx ; Current qword index
    
.search_loop:
    cmp r10, r9
    jae .wrap_search
    
    mov rax, [rsi + r10*8]
    not rax ; Invert to find free frames (0 bits)
    test rax, rax
    jnz .found_free_qword
    
    inc r10
    jmp .search_loop
    
.wrap_search:
    ; Wrap around to beginning of bitmap
    xor r10, r10
    
.wrap_search_loop:
    cmp r10, rdx
    jae .next_node ; Searched entire bitmap, no free frames
    
    mov rax, [rsi + r10*8]
    not rax ; Invert to find free frames (0 bits)
    test rax, rax
    jnz .found_free_qword
    
    inc r10
    jmp .wrap_search_loop
    
.found_free_qword:
    ; Find first free bit in qword
    bsf r11, rax ; Bit scan forward
    
    ; Calculate frame index
    mov rax, r10
    shl rax, 6
    add rax, r11
    
    ; Check if frame index is valid
    cmp rax, rdi
    jae .next_node ; Frame index out of bounds
    
    ; Mark frame as used
    mov rdx, 1
    mov ecx, r11d
    shl rdx, cl
    LOCK_PREFIX or qword [rsi + r10*8], rdx
    
    ; Update last allocation hint
    mov [r15 + OFFSET_LAST_ALLOC_INDEX_LARGE + rbx*8], r10
    
    ; Update used large frames count
    mov rcx, [r15 + OFFSET_PMM_USED_LARGE_FRAMES]
    inc rcx
    mov [r15 + OFFSET_PMM_USED_LARGE_FRAMES], rcx
    
    ; Calculate physical address
    mov rdx, [r15 + OFFSET_PMM_NODE_BASE_ADDRS + rbx*8]
    shl rax, 21 ; Convert large frame index to byte offset
    add rax, rdx ; Add node base address
    
    jmp .done
    
.next_node:
    inc rbx
    jmp .try_next_node
    
.fail:
    xor rax, rax
    
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; pmm_free_large_frame: Free a 2MB physical memory frame
; Input: RDI = Physical address of frame to free
; Output: None
; Destroys: RAX, RCX, RDX, RDI, RSI, R8, R9, R10, R11
;-----------------------------------------------------------------------------
pmm_free_large_frame:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    
    ; Get PMM runtime data pointer
    call get_pmm_runtime_data
    mov r15, rax
    test r15, r15
    jz .done
    
    ; Align address to 2MB boundary
    mov rax, [r15 + OFFSET_PAGE_SIZE_2M_MINUS_1]
    not rax
    and rdi, rax
    
    ; Get node for this address
    push rdi
    call pmm_get_node_for_addr
    mov rbx, rax ; node_id
    pop rdi
    
    ; Check if node has large bitmap
    mov rsi, [r15 + OFFSET_PMM_NODE_LARGE_BITMAPS + rbx*8]
    test rsi, rsi
    jz .done
    
    ; Calculate large frame index relative to node base
    mov rax, [r15 + OFFSET_PMM_NODE_BASE_ADDRS + rbx*8]
    sub rdi, rax ; Offset from node base
    shr rdi, 21 ; Convert to large frame index
    
    ; Check if frame index is valid
    cmp rdi, [r15 + OFFSET_PMM_NODE_LARGE_FRAME_COUNTS + rbx*8]
    jae .done ; Frame index out of bounds
    
    ; Calculate qword index and bit position
    mov rax, rdi
    shr rax, 6 ; qword index
    mov rdx, rdi
    and rdx, 63 ; bit position
    
    ; Check if frame is already free
    mov r8, 1
    mov ecx, edx
    shl r8, cl
    mov r9, [rsi + rax*8]
    test r9, r8
    jz .done ; Frame already free
    
    ; Mark frame as free
    not r8
    LOCK_PREFIX and qword [rsi + rax*8], r8
    
    ; Update used large frames count
    mov rcx, [r15 + OFFSET_PMM_USED_LARGE_FRAMES]
    dec rcx
    mov [r15 + OFFSET_PMM_USED_LARGE_FRAMES], rcx
    
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
