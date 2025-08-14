; paging64_pic.asm: UEFI-centric 64-bit Paging Setup (PIC-compliant)
; PIC-compliant version that avoids global variables in .bss/.data sections
; and uses runtime allocation for kernel boundaries

BITS 64
default rel

; Exports
global paging_init_64_uefi, map_page, unmap_page, map_2mb_page, unmap_2mb_page
global reload_cr3
global kernel_pml4, get_kernel_pml4
global init_paging_runtime_data
global get_kernel_start, get_kernel_end

; External dependencies
extern pmm_alloc_frame, pmm_free_frame
extern scr64_print_string

%include "boot_defs_temp.inc"

; Structure of runtime paging data block:
; Offset 0:  paging_runtime_data_ptr (qword)
; Offset 8:  kernel_pml4 (qword)
; Offset 16: kernel_start (qword)
; Offset 24: kernel_end (qword)
; Total size: 32 bytes

%define PAGING_RUNTIME_DATA_SIZE 32
%define OFFSET_PAGING_RUNTIME_PTR 0
%define OFFSET_KERNEL_PML4 8
%define OFFSET_KERNEL_START 16
%define OFFSET_KERNEL_END 24

section .data
    ; Single global pointer to runtime allocated data
    paging_runtime_data_ptr dq 0
    
    ; Constants
    page_size_4k_minus_1 dq PAGE_SIZE_4K - 1
    page_size_2m_minus_1 dq PAGE_SIZE_2M - 1
    
    ; Error messages
    msg_paging_init db "Initializing paging...", 0
    msg_paging_error db "Paging initialization error", 0

section .text

;--------------------------------------------------------------------------
; init_paging_runtime_data: Allocate and initialize paging runtime data
; Input: RDI = Kernel start address
;        RSI = Kernel end address
; Output: RAX = 0 on success, error code otherwise
;--------------------------------------------------------------------------
init_paging_runtime_data:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rdi
    push rsi
    
    ; Check if already initialized
    mov rax, [rel paging_runtime_data_ptr]
    test rax, rax
    jnz .already_initialized
    
    ; Allocate memory for paging runtime data
    mov rdi, (PAGING_RUNTIME_DATA_SIZE + 4095) / 4096  ; Pages needed
    call pmm_alloc_frame
    test rax, rax
    jz .allocation_error
    
    ; Save pointer to allocated memory
    mov [rel paging_runtime_data_ptr], rax
    mov rbx, rax  ; Save pointer in RBX
    
    ; Store self-reference at offset 0
    mov [rbx + OFFSET_PAGING_RUNTIME_PTR], rax
    
    ; Initialize kernel_pml4 to 0
    mov qword [rbx + OFFSET_KERNEL_PML4], 0
    
    ; Store kernel boundaries
    pop rsi  ; Kernel end
    pop rdi  ; Kernel start
    mov [rbx + OFFSET_KERNEL_START], rdi
    mov [rbx + OFFSET_KERNEL_END], rsi
    
    ; Success
    xor rax, rax
    jmp .done
    
.already_initialized:
    ; Already initialized, return success
    xor rax, rax
    jmp .done
    
.allocation_error:
    ; Failed to allocate memory
    mov rsi, msg_paging_error
    call scr64_print_string
    mov rax, 1
    
.done:
    pop rsi
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

;--------------------------------------------------------------------------
; get_paging_runtime_data: Get pointer to paging runtime data
; Input: None
; Output: RAX = Pointer to paging runtime data, 0 if not initialized
;--------------------------------------------------------------------------
get_paging_runtime_data:
    mov rax, [rel paging_runtime_data_ptr]
    ret

;--------------------------------------------------------------------------
; get_kernel_pml4: Get kernel PML4 address
; Input: None
; Output: RAX = Kernel PML4 address
;--------------------------------------------------------------------------
get_kernel_pml4:
    push rbp
    mov rbp, rsp
    
    ; Get paging runtime data pointer
    call get_paging_runtime_data
    test rax, rax
    jz .not_initialized
    
    ; Return kernel PML4 address
    mov rax, [rax + OFFSET_KERNEL_PML4]
    jmp .done
    
.not_initialized:
    ; Return 0 if not initialized
    xor rax, rax
    
.done:
    pop rbp
    ret

;--------------------------------------------------------------------------
; kernel_pml4: Legacy compatibility function for kernel_pml4 global
; Input: None
; Output: RAX = Kernel PML4 address
;--------------------------------------------------------------------------
kernel_pml4:
    jmp get_kernel_pml4

;--------------------------------------------------------------------------
; get_kernel_start: Get kernel start address
; Input: None
; Output: RAX = Kernel start address
;--------------------------------------------------------------------------
get_kernel_start:
    push rbp
    mov rbp, rsp
    
    ; Get paging runtime data pointer
    call get_paging_runtime_data
    test rax, rax
    jz .not_initialized
    
    ; Return kernel start address
    mov rax, [rax + OFFSET_KERNEL_START]
    jmp .done
    
.not_initialized:
    ; Return 0 if not initialized
    xor rax, rax
    
.done:
    pop rbp
    ret

;--------------------------------------------------------------------------
; get_kernel_end: Get kernel end address
; Input: None
; Output: RAX = Kernel end address
;--------------------------------------------------------------------------
get_kernel_end:
    push rbp
    mov rbp, rsp
    
    ; Get paging runtime data pointer
    call get_paging_runtime_data
    test rax, rax
    jz .not_initialized
    
    ; Return kernel end address
    mov rax, [rax + OFFSET_KERNEL_END]
    jmp .done
    
.not_initialized:
    ; Return 0 if not initialized
    xor rax, rax
    
.done:
    pop rbp
    ret

;-----------------------------------------------------------------------------
; zero_page: Helper to zero a 4KB physical page
; Input: RDI = Physical address of page to zero
; Destroys: RAX, RCX, RDI, YMM0 (if AVX used)
;-----------------------------------------------------------------------------
zero_page:
    ; Use rep stosq for simplicity and no AVX dependency here
    push rdi
    mov rcx, PAGE_SIZE_4K / 8 ; 512 qwords
    xor eax, eax
    rep stosq
    pop rdi ; Keep RDI unchanged
    ret

;-----------------------------------------------------------------------------
; pmm_alloc_zeroed_page: Allocates and zeroes one 4KB page using PMM
; Output: RAX = Physical address of allocated page on success, 0 on failure
; Destroys: RAX, RDI, RCX (and others clobbered by pmm_alloc_frame)
;-----------------------------------------------------------------------------
pmm_alloc_zeroed_page:
    mov rcx, -1 ; Request any node
    call pmm_alloc_frame ; RAX = Physical address or 0
    test rax, rax
    jz .alloc_fail
    ; Success, zero the page
    push rax ; Save allocated address
    mov rdi, rax
    call zero_page
    pop rax ; Restore allocated address to return
    ret
.alloc_fail:
    ; RAX is already 0
    ret

;-----------------------------------------------------------------------------
; reload_cr3: Reloads CR3 to flush TLB after page table modifications
;-----------------------------------------------------------------------------
reload_cr3:
    mov rax, cr3
    mov cr3, rax
    ret

;-----------------------------------------------------------------------------
; map_page_internal: Common helper for mapping pages (UEFI context)
; Allocates necessary tables using pmm_alloc_zeroed_page
; Input: RDI=VirtAddr, RSI=PhysAddr, RDX=Flags, R12=PageSizeFlag(0/PTE_PS)
; Output: RAX: 0=success, 1=error
;-----------------------------------------------------------------------------
map_page_internal:
    push rdi; push rbx; push rcx; push rdx; push rsi; push r8; push r9; push r10; push r11; push r12; push r13

    mov r13, rdx                ; Save original flags in R13

    mov rax, cr3                ; Get current PML4 base address
    mov r8, rax
    and r8, 0xFFFFFFFFFFFFF000  ; Mask out flags (Explicit Hex)

    ; --- Level 4: PML4 ---
    mov rax, rdi;
    shr rax, 39;
    and rax, 0x1FF;
    lea r10, [r8 + rax*8]
    mov r9, [r10]
    test r9, PTE_PRESENT;
    jnz .pdpt
    call pmm_alloc_zeroed_page ; -> RAX=PhysAddr or 0
    test rax, rax;
    jz .err_map_internal
    mov r9, rax;
    or r9, PTE_PRESENT | PTE_WRITABLE | PTE_USER;
    mov [r10], r9

.pdpt: ; --- Level 3: PDPT ---
    test r9, PTE_PS;
    jnz .err_map_internal
    mov r8, r9;
    and r8, 0xFFFFFFFFFFFFF000
    mov rax, rdi;
    shr rax, 30;
    and rax, 0x1FF;
    lea r10, [r8 + rax*8]
    mov r9, [r10]
    test r9, PTE_PRESENT;
    jnz .pd
    call pmm_alloc_zeroed_page ; -> RAX=PhysAddr or 0
    test rax, rax;
    jz .err_map_internal
    mov r9, rax;
    or r9, PTE_PRESENT | PTE_WRITABLE | PTE_USER;
    mov [r10], r9

.pd: ; --- Level 2: PD ---
    test r9, PTE_PS; jnz .err_if_4k
    mov r8, r9; and r8, 0xFFFFFFFFFFFFF000
    mov rax, rdi; shr rax, 21; and rax, 0x1FF; lea r10, [r8 + rax*8] ; r10 = PDE address
    mov r12, [rsp + 8*3] ; Get original R12 (page size flag) from stack
    cmp r12, 0; jne .map_final_2m

    ; --- Mapping 4K Page ---
    mov r9, [r10]; test r9, PTE_PS; jnz .err_map_internal
    test r9, PTE_PRESENT; jnz .pt
    call pmm_alloc_zeroed_page ; -> RAX=PhysAddr or 0
    test rax, rax; jz .err_map_internal
    mov r9, rax; or r9, PTE_PRESENT | PTE_WRITABLE | PTE_USER; mov [r10], r9

.pt: ; --- Level 1: PT ---
    mov r8, r9; and r8, 0xFFFFFFFFFFFFF000
    mov rax, rdi; shr rax, 12; and rax, 0x1FF; lea r10, [r8 + rax*8] ; r10 = PTE address
    mov rbx, rsi; or rbx, PTE_PRESENT; or rbx, r13 ; Use saved flags
    and rbx, 0xFFFFFFFFFFFFFF7F ; Explicit ~PTE_PS
    mov [r10], rbx; jmp .success_map_internal

.map_final_2m: ; --- Map Final 2M PDE ---
    mov r9, [r10]; test r9, PTE_PRESENT; jnz .err_map_internal
    mov rbx, rsi; or rbx, PTE_PRESENT | PTE_PS; or rbx, r13 ; Use saved flags
    mov [r10], rbx; jmp .success_map_internal

.err_if_4k: ; --- Error Conditions ---
    mov r12, [rsp + 8*3] ; Get original R12 (page size flag)
    cmp r12, 0; je .err_map_internal ; Trying to map 4K over 2M
    jmp .err_map_internal ; Trying to map 2M over 2M (or other error)

.success_map_internal: mov rax, 0; jmp .exit_map_internal
.err_map_internal: mov rax, 1
.exit_map_internal:
    pop r13; pop r12; pop r11; pop r10; pop r9; pop r8; pop rsi; pop rdx; pop rcx; pop rbx
    pop rdi ; Restore original RDI for invlpg
    test rax, rax; jnz .ret_no_invlpg
    invlpg [rdi];
.ret_no_invlpg: ret

;-----------------------------------------------------------------------------
; map_page: Maps a 4KB virtual page (UEFI context)
;-----------------------------------------------------------------------------
map_page:
    push rbx; push r12; push r13
    mov rax, rdi; or rax, rsi; and rax, [rel page_size_4k_minus_1]; jnz .align_err_4k
    mov r12, 0; call map_page_internal; jmp .done_4k
.align_err_4k: mov rax, 1
.done_4k: pop r13; pop r12; pop rbx; ret

;-----------------------------------------------------------------------------
; map_2mb_page: Maps a 2MB virtual page (UEFI context)
;-----------------------------------------------------------------------------
map_2mb_page:
    push rbx; push r12; push r13
    mov rax, rdi; or rax, rsi; and rax, [rel page_size_2m_minus_1]; jnz .align_err_2m
    mov r12, PTE_PS; call map_page_internal; jmp .done_2m
.align_err_2m: mov rax, 1
.done_2m: pop r13; pop r12; pop rbx; ret

;-----------------------------------------------------------------------------
; unmap_page: Unmaps a 4KB virtual page
;-----------------------------------------------------------------------------
unmap_page:
    push rbx; push rcx; push r10; push rdi
    mov rax, rdi; and rax, [rel page_size_4k_minus_1]; jnz .err_unmap_4k
    mov rax, cr3; mov r8, rax; and r8, 0xFFFFFFFFFFFFF000
    mov rax, rdi; shr rax, 39; and rax, 0x1FF; lea r10, [r8 + rax*8]; mov r9, [r10]; test r9, PTE_PRESENT; jz .err_unmap_4k
    test r9, PTE_PS; jnz .err_unmap_4k; mov r8, r9; and r8, 0xFFFFFFFFFFFFF000
    mov rax, rdi; shr rax, 30; and rax, 0x1FF; lea r10, [r8 + rax*8]; mov r9, [r10]; test r9, PTE_PRESENT; jz .err_unmap_4k
    test r9, PTE_PS; jnz .err_unmap_4k; mov r8, r9; and r8, 0xFFFFFFFFFFFFF000
    mov rax, rdi; shr rax, 21; and rax, 0x1FF; lea r10, [r8 + rax*8]; mov r9, [r10]; test r9, PTE_PRESENT; jz .err_unmap_4k
    test r9, PTE_PS; jnz .err_unmap_4k; mov r8, r9; and r8, 0xFFFFFFFFFFFFF000
    mov rax, rdi; shr rax, 12; and rax, 0x1FF; lea r10, [r8 + rax*8]; mov rbx, [r10]; test rbx, PTE_PRESENT; jz .err_unmap_4k
    and rbx, 0xFFFFFFFFFFFFFFFE; mov [r10], rbx; invlpg [rdi]; xor rax, rax; jmp .done_unmap_4k
.err_unmap_4k: mov rax, 1
.done_unmap_4k: pop rdi; pop r10; pop rcx; pop rbx; ret

;-----------------------------------------------------------------------------
; unmap_2mb_page: Unmaps a 2MB virtual page
;-----------------------------------------------------------------------------
unmap_2mb_page:
    push rbx; push rcx; push r10; push rdi
    mov rax, rdi; and rax, [rel page_size_2m_minus_1]; jnz .err_unmap_2m
    mov rax, cr3; mov r8, rax; and r8, 0xFFFFFFFFFFFFF000
    mov rax, rdi; shr rax, 39; and rax, 0x1FF; lea r10, [r8 + rax*8]; mov r9, [r10]; test r9, PTE_PRESENT; jz .err_unmap_2m
    test r9, PTE_PS; jnz .err_unmap_2m; mov r8, r9; and r8, 0xFFFFFFFFFFFFF000
    mov rax, rdi; shr rax, 30; and rax, 0x1FF; lea r10, [r8 + rax*8]; mov r9, [r10]; test r9, PTE_PRESENT; jz .err_unmap_2m
    test r9, PTE_PS; jz .err_unmap_2m; mov r8, r9; and r8, 0xFFFFFFFFFFFFF000
    mov rax, rdi; shr rax, 21; and rax, 0x1FF; lea r10, [r8 + rax*8] ; PDE Address
    mov r9, [r10]; test r9, PTE_PRESENT; jz .err_unmap_2m; test r9, PTE_PS; jz .err_unmap_2m
    and r9, 0xFFFFFFFFFFFFFFFE; mov [r10], r9; invlpg [rdi]; xor rax, rax; jmp .done_unmap_2m
.err_unmap_2m: mov rax, 1
.done_unmap_2m: pop rdi; pop r10; pop rcx; pop rbx; ret

;-----------------------------------------------------------------------------
; paging_init_64_uefi: Sets up final 64-bit kernel page tables using UEFI map.
; Input: RCX=MapPtr, RDX=MapSize, R8=DescSize, R9=Ptr to store PML4 phys addr
; Output: RAX=Status (0=OK), [R9]=PML4 phys addr on success
;-----------------------------------------------------------------------------
paging_init_64_uefi:
    push rbp; mov rbp, rsp; sub rsp, 8; push rbx; push r12; push r13; push r14; push r15

    mov r12, rcx; mov r13, rdx; mov r14, r8; mov r15, r9 ; Store inputs

    ; Print initialization message
    lea rsi, [rel msg_paging_init]
    call scr64_print_string

    ; 1. Allocate and Zero PML4 Table using PMM
    call pmm_alloc_zeroed_page ; RAX = PML4 phys addr or 0
    test rax, rax; jz .fail_alloc_page
    mov [r15], rax ; Store PML4 address in caller's pointer
    
    ; Store PML4 address in runtime data
    push rax ; Save PML4 address
    call get_paging_runtime_data
    test rax, rax
    jz .no_runtime_data
    mov rbx, rax ; RBX = Runtime data pointer
    pop rax ; Restore PML4 address
    mov [rbx + OFFSET_KERNEL_PML4], rax ; Store in runtime data
    jmp .pml4_stored
    
.no_runtime_data:
    pop rax ; Restore PML4 address
    
.pml4_stored:
    mov cr3, rax ; Load new PML4

    ; 2. Map the Kernel using runtime data for boundaries
    call get_kernel_start
    mov rbx, rax ; RBX = Kernel start
    call get_kernel_end
    mov rcx, rax ; RCX = Kernel end
    
    ; If kernel boundaries are not set, use default values
    test rbx, rbx
    jnz .kernel_start_set
    mov rbx, 0xFFFFFFFF80000000 ; Default kernel start
    
.kernel_start_set:
    test rcx, rcx
    jnz .kernel_end_set
    mov rcx, 0xFFFFFFFF90000000 ; Default kernel end
    
.kernel_end_set:
    mov rax, [rel page_size_2m_minus_1]; not rax; and rbx, rax; add rcx, PAGE_SIZE_2M; and rcx, rax
.kmap_loop: cmp rbx, rcx; jae .kmap_done
    mov rdi, rbx; mov rsi, rbx; mov rdx, KERNEL_PTE_FLAGS; call map_2mb_page
    test rax, rax; jnz .fail_map
    add rbx, PAGE_SIZE_2M; jmp .kmap_loop
.kmap_done:

    ; 3. Map Usable Conventional Memory from UEFI Map
    mov rbx, r12; mov rcx, r13; mov r10, r14 ; Map Ptr, Map Size, Desc Size
.memmap_loop: cmp rcx, r10; jl .memmap_done
    mov edi, [rbx + EFI_MEMORY_DESCRIPTOR.Type]; cmp edi, EfiConventionalMemory; jne .next_descriptor
    mov rdi, [rbx + EFI_MEMORY_DESCRIPTOR.PhysicalStart]; mov rsi, [rbx + EFI_MEMORY_DESCRIPTOR.NumberOfPages]
    mov rax, rsi; shl rax, 12; add rax, rdi ; Phys End (excl)
    push rax; mov rax, [rel page_size_2m_minus_1]; not rax; and rdi, rax; pop r8; add r8, PAGE_SIZE_2M; and r8, rax ; Aligned start/end
.phys_loop: cmp rdi, r8; jae .next_descriptor
    push rax
    
    ; Check kernel overlap using runtime data
    call get_kernel_start
    mov r9, rax ; R9 = Kernel start
    test r9, r9
    jnz .kernel_start_valid
    mov r9, 0xFFFFFFFF80000000 ; Default kernel start
    
.kernel_start_valid:
    mov rax, [rel page_size_2m_minus_1]
    not rax
    and r9, rax ; Align kernel start
    cmp rdi, r9
    jb .map_phys
    
    call get_kernel_end
    mov r9, rax ; R9 = Kernel end
    test r9, r9
    jnz .kernel_end_valid
    mov r9, 0xFFFFFFFF90000000 ; Default kernel end
    
.kernel_end_valid:
    add r9, PAGE_SIZE_2M
    mov rax, [rel page_size_2m_minus_1]
    not rax
    and r9, rax ; Align kernel end
    pop rax
    cmp rdi, r9
    jae .map_phys
    jmp .skip_phys ; Skip if in kernel range
    
.map_phys: 
    mov rsi, rdi
    mov rdx, DATA_PTE_FLAGS
    call map_2mb_page
    test rax, rax
    jnz .fail_map
    
.skip_phys: 
    add rdi, PAGE_SIZE_2M
    jmp .phys_loop
    
.next_descriptor: 
    add rbx, r10
    sub rcx, r10
    jmp .memmap_loop
    
.memmap_done:
    xor rax, rax
    jmp .exit_page
    
.fail_alloc_page: 
    mov rax, 2
    jmp .exit_final_page
    
.fail_map: 
    mov rax, 1
    
.exit_page: 
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    add rsp, 8
    pop rbp
    
.exit_final_page: 
    ret
