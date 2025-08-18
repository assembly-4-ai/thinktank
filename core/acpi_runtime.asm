; acpi_runtime.asm - ACPI Table Parsing Implementation with runtime allocation
; PIC-compliant version that avoids global variables in .bss/.data sections

BITS 64
default rel

; External dependencies
extern pmm_alloc_frame, pmm_free_frame
extern panic64, scr64_print_string, scr64_print_hex, scr64_print_dec
extern itoa64

; Exports
global find_parse_acpi_tables
global init_acpi_runtime_data
global get_acpi_lapic_base, get_acpi_ioapic_base
; NUMA functions moved to numa_pic.asm to avoid multiple definition errors
extern get_numa_node_count, get_numa_node_base, get_numa_node_limit

section .rodata
    ; Error messages
    msg_acpi_search db "Searching for ACPI tables...", 0
    msg_rsdp_found db "RSDP found at: 0x", 0
    msg_rsdp_not_found db "RSDP not found!", 0
    msg_rsdt_found db "RSDT found at: 0x", 0
    msg_xsdt_found db "XSDT found at: 0x", 0
    msg_madt_found db "MADT found at: 0x", 0
    msg_srat_found db "SRAT found at: 0x", 0
    msg_mcfg_found db "MCFG found at: 0x", 0
    msg_lapic_base db "Local APIC base: 0x", 0
    msg_ioapic_base db "I/O APIC base: 0x", 0
    msg_numa_nodes db "NUMA nodes found: ", 0
    msg_acpi_error db "ACPI parsing error: ", 0
    msg_acpi_alloc_error db "ACPI runtime data allocation error", 0
    
    ; ACPI table signatures
    sig_rsdp db "RSD PTR ", 0
    sig_madt db "APIC", 0
    sig_srat db "SRAT", 0
    sig_mcfg db "MCFG", 0

section .text

; Structure of runtime ACPI data block:
; Offset 0:  acpi_runtime_data_ptr (qword)
; Offset 8:  acpi_rsdp_found (byte)
; Offset 9:  acpi_rsdt_found (byte)
; Offset 10: acpi_xsdt_found (byte)
; Offset 11: acpi_madt_found (byte)
; Offset 12: acpi_srat_found (byte)
; Offset 13: acpi_mcfg_found (byte)
; Offset 14: padding (2 bytes)
; Offset 16: acpi_rsdp_addr (qword)
; Offset 24: acpi_rsdt_addr (qword)
; Offset 32: acpi_xsdt_addr (qword)
; Offset 40: acpi_madt_addr (qword)
; Offset 48: acpi_srat_addr (qword)
; Offset 56: acpi_mcfg_addr (qword)
; Offset 64: acpi_lapic_base (qword)
; Offset 72: acpi_ioapic_base (qword)
; Offset 80: numa_node_count (byte)
; Offset 81: padding (7 bytes)
; Offset 88: pmm_node_base_addrs (8 qwords = 64 bytes)
; Offset 152: pmm_node_addr_limits (8 qwords = 64 bytes)
; Total size: 216 bytes

%define ACPI_RUNTIME_DATA_SIZE 216
%define OFFSET_ACPI_RUNTIME_PTR 0
%define OFFSET_ACPI_RSDP_FOUND 8
%define OFFSET_ACPI_RSDT_FOUND 9
%define OFFSET_ACPI_XSDT_FOUND 10
%define OFFSET_ACPI_MADT_FOUND 11
%define OFFSET_ACPI_SRAT_FOUND 12
%define OFFSET_ACPI_MCFG_FOUND 13
%define OFFSET_ACPI_RSDP_ADDR 16
%define OFFSET_ACPI_RSDT_ADDR 24
%define OFFSET_ACPI_XSDT_ADDR 32
%define OFFSET_ACPI_MADT_ADDR 40
%define OFFSET_ACPI_SRAT_ADDR 48
%define OFFSET_ACPI_MCFG_ADDR 56
%define OFFSET_ACPI_LAPIC_BASE 64
%define OFFSET_ACPI_IOAPIC_BASE 72
%define OFFSET_NUMA_NODE_COUNT 80
%define OFFSET_PMM_NODE_BASE_ADDRS 88
%define OFFSET_PMM_NODE_ADDR_LIMITS 152

section .data
    ; Single global pointer to runtime allocated data
    acpi_runtime_data_ptr dq 0

;--------------------------------------------------------------------------
; init_acpi_runtime_data: Allocate and initialize ACPI runtime data
; Input: None
; Output: RAX = 0 on success, error code otherwise
;--------------------------------------------------------------------------
init_acpi_runtime_data:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rdi
    push rsi
    
    ; Check if already initialized
    mov rax, [acpi_runtime_data_ptr]
    test rax, rax
    jnz .already_initialized
    
    ; Allocate memory for ACPI runtime data
    mov rdi, (ACPI_RUNTIME_DATA_SIZE + 4095) / 4096  ; Pages needed
    call pmm_alloc_frame
    test rax, rax
    jz .allocation_error
    
    ; Save pointer to allocated memory
    mov [acpi_runtime_data_ptr], rax
    mov rdi, rax
    
    ; Store self-reference at offset 0
    mov [rdi + OFFSET_ACPI_RUNTIME_PTR], rax
    
    ; Initialize status flags
    mov byte [rdi + OFFSET_ACPI_RSDP_FOUND], 0
    mov byte [rdi + OFFSET_ACPI_RSDT_FOUND], 0
    mov byte [rdi + OFFSET_ACPI_XSDT_FOUND], 0
    mov byte [rdi + OFFSET_ACPI_MADT_FOUND], 0
    mov byte [rdi + OFFSET_ACPI_SRAT_FOUND], 0
    mov byte [rdi + OFFSET_ACPI_MCFG_FOUND], 0
    
    ; Initialize ACPI table addresses
    mov qword [rdi + OFFSET_ACPI_RSDP_ADDR], 0
    mov qword [rdi + OFFSET_ACPI_RSDT_ADDR], 0
    mov qword [rdi + OFFSET_ACPI_XSDT_ADDR], 0
    mov qword [rdi + OFFSET_ACPI_MADT_ADDR], 0
    mov qword [rdi + OFFSET_ACPI_SRAT_ADDR], 0
    mov qword [rdi + OFFSET_ACPI_MCFG_ADDR], 0
    
    ; Initialize hardware information with default values
    mov qword [rdi + OFFSET_ACPI_LAPIC_BASE], 0xFEE00000 ; Default value if not found
    mov qword [rdi + OFFSET_ACPI_IOAPIC_BASE], 0xFEC00000 ; Default value if not found
    
    ; Initialize NUMA information with defaults
    mov byte [rdi + OFFSET_NUMA_NODE_COUNT], 1 ; Default to 1 node if SRAT not found
    
    ; Initialize node base addresses (all 0)
    lea rdi, [rdi + OFFSET_PMM_NODE_BASE_ADDRS]
    mov rcx, 8  ; 8 qwords
    xor rax, rax
    rep stosq
    
    ; Initialize node address limits (first entry max, rest 0)
    mov qword [rdi], 0xFFFFFFFFFFFFFFFF
    add rdi, 8
    mov rcx, 7  ; 7 more qwords
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
    mov rsi, msg_acpi_alloc_error
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
; get_acpi_runtime_data: Get pointer to ACPI runtime data
; Input: None
; Output: RAX = Pointer to ACPI runtime data, 0 if not initialized
;--------------------------------------------------------------------------
get_acpi_runtime_data:
    mov rax, [acpi_runtime_data_ptr]
    ret

;--------------------------------------------------------------------------
; get_acpi_lapic_base: Get Local APIC base address
; Input: None
; Output: RAX = Local APIC base address
;--------------------------------------------------------------------------
get_acpi_lapic_base:
    push rbp
    mov rbp, rsp
    
    ; Get ACPI runtime data pointer
    call get_acpi_runtime_data
    test rax, rax
    jz .not_initialized
    
    ; Get Local APIC base address
    mov rax, [rax + OFFSET_ACPI_LAPIC_BASE]
    jmp .done
    
.not_initialized:
    ; Return default value if not initialized
    mov rax, 0xFEE00000
    
.done:
    pop rbp
    ret

;--------------------------------------------------------------------------
; get_acpi_ioapic_base: Get I/O APIC base address
; Input: None
; Output: RAX = I/O APIC base address
;--------------------------------------------------------------------------
get_acpi_ioapic_base:
    push rbp
    mov rbp, rsp
    
    ; Get ACPI runtime data pointer
    call get_acpi_runtime_data
    test rax, rax
    jz .not_initialized
    
    ; Get I/O APIC base address
    mov rax, [rax + OFFSET_ACPI_IOAPIC_BASE]
    jmp .done
    
.not_initialized:
    ; Return default value if not initialized
    mov rax, 0xFEC00000
    
.done:
    pop rbp
    ret

; NUMA functions removed to avoid multiple definition errors
; These functions are now implemented in numa_pic.asm
; and only referenced as external symbols here

; NUMA function removed to avoid multiple definition errors
; This function is now implemented in numa_pic.asm
; and only referenced as an external symbol here

;--------------------------------------------------------------------------
; find_parse_acpi_tables: Finds and parses ACPI tables
; Input: None
; Output: RAX = 0 on success, error code otherwise
;--------------------------------------------------------------------------
find_parse_acpi_tables:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    
    ; Initialize ACPI runtime data
    call init_acpi_runtime_data
    test rax, rax
    jnz .error
    
    ; Get ACPI runtime data pointer
    call get_acpi_runtime_data
    mov r15, rax  ; Save pointer in R15 for later use
    
    ; Print start message
    mov rsi, msg_acpi_search
    call scr64_print_string
    
    ; Find RSDP
    call find_rsdp
    test rax, rax
    jz .rsdp_not_found
    
    ; RSDP found, save address
    mov [r15 + OFFSET_ACPI_RSDP_ADDR], rax
    mov byte [r15 + OFFSET_ACPI_RSDP_FOUND], 1
    
    ; Print RSDP address
    mov rsi, msg_rsdp_found
    call scr64_print_string
    mov rsi, rax
    call scr64_print_hex
    
    ; Parse RSDP to find RSDT/XSDT
    mov rdi, rax
    call parse_rsdp
    test rax, rax
    jnz .error
    
    ; Parse RSDT/XSDT to find other tables
    cmp byte [r15 + OFFSET_ACPI_XSDT_FOUND], 1
    je .parse_xsdt
    
    cmp byte [r15 + OFFSET_ACPI_RSDT_FOUND], 1
    je .parse_rsdt
    
    ; Neither XSDT nor RSDT found
    mov rax, 1
    jmp .error
    
.parse_xsdt:
    mov rdi, [r15 + OFFSET_ACPI_XSDT_ADDR]
    mov rsi, 1 ; is_xsdt = true
    call parse_sdt
    test rax, rax
    jnz .error
    jmp .parse_tables
    
.parse_rsdt:
    mov rdi, [r15 + OFFSET_ACPI_RSDT_ADDR]
    mov rsi, 0 ; is_xsdt = false
    call parse_sdt
    test rax, rax
    jnz .error
    
.parse_tables:
    ; Parse MADT if found
    cmp byte [r15 + OFFSET_ACPI_MADT_FOUND], 1
    jne .check_srat
    
    mov rdi, [r15 + OFFSET_ACPI_MADT_ADDR]
    call parse_madt
    test rax, rax
    jnz .error
    
.check_srat:
    ; Parse SRAT if found
    cmp byte [r15 + OFFSET_ACPI_SRAT_FOUND], 1
    jne .check_mcfg
    
    mov rdi, [r15 + OFFSET_ACPI_SRAT_ADDR]
    call parse_srat
    test rax, rax
    jnz .error
    
.check_mcfg:
    ; Parse MCFG if found
    cmp byte [r15 + OFFSET_ACPI_MCFG_FOUND], 1
    jne .success
    
    mov rdi, [r15 + OFFSET_ACPI_MCFG_ADDR]
    call parse_mcfg
    test rax, rax
    jnz .error
    
.success:
    ; Success
    xor rax, rax
    jmp .done
    
.rsdp_not_found:
    ; RSDP not found
    mov rsi, msg_rsdp_not_found
    call scr64_print_string
    mov rax, 1
    jmp .done
    
.error:
    ; Error occurred
    mov rsi, msg_acpi_error
    call scr64_print_string
    ; RAX already contains error code
    
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

;--------------------------------------------------------------------------
; find_rsdp: Searches for the RSDP in memory
; Input: None
; Output: RAX = RSDP address if found, 0 otherwise
;--------------------------------------------------------------------------
find_rsdp:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rdi
    push rsi
    
    ; First search the EBDA (Extended BIOS Data Area)
    mov rax, 0x40E ; EBDA pointer location
    mov ax, [rax]
    shl rax, 4 ; Convert segment to physical address
    
    ; Search first 1KB of EBDA
    mov rcx, 1024 / 16 ; RSDP is 16-byte aligned
    mov rdi, rax
    call search_rsdp_in_range
    test rax, rax
    jnz .found
    
    ; Next search the main BIOS area (0xE0000 to 0xFFFFF)
    mov rdi, 0xE0000
    mov rcx, (0x100000 - 0xE0000) / 16
    call search_rsdp_in_range
    ; RAX now contains RSDP address or 0 if not found
    
.found:
    pop rsi
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

;--------------------------------------------------------------------------
; search_rsdp_in_range: Searches for RSDP signature in a memory range
; Input: RDI = Start address
;        RCX = Number of 16-byte blocks to search
; Output: RAX = RSDP address if found, 0 otherwise
;--------------------------------------------------------------------------
search_rsdp_in_range:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rdi
    push rsi
    
.search_loop:
    ; Check for "RSD PTR " signature
    mov rsi, sig_rsdp
    mov rdx, 8 ; Signature length
    push rdi
    push rcx
    repe cmpsb
    pop rcx
    pop rdi
    je .verify_checksum
    
    ; Move to next 16-byte aligned address
    add rdi, 16
    dec rcx
    jnz .search_loop
    
    ; Not found
    xor rax, rax
    jmp .done
    
.verify_checksum:
    ; Verify RSDP checksum (first 20 bytes)
    mov rsi, rdi
    xor rbx, rbx
    mov rcx, 20
    
.checksum_loop:
    mov bl, [rsi]
    add rax, rbx
    inc rsi
    dec rcx
    jnz .checksum_loop
    
    ; Checksum should be 0 (mod 256)
    test al, al
    jz .valid_rsdp
    
    ; Invalid checksum, continue search
    add rdi, 16
    jmp .search_loop
    
.valid_rsdp:
    ; Valid RSDP found
    mov rax, rdi
    
.done:
    pop rsi
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

;--------------------------------------------------------------------------
; parse_rsdp: Parses the RSDP structure to find RSDT/XSDT
; Input: RDI = RSDP address
; Output: RAX = 0 on success, error code otherwise
;--------------------------------------------------------------------------
parse_rsdp:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rdi
    push rsi
    
    ; Get ACPI runtime data pointer
    call get_acpi_runtime_data
    mov rbx, rax  ; Save pointer in RBX
    
    ; Check RSDP revision
    mov al, [rdi + 15] ; Revision field
    cmp al, 0
    je .rsdp_v1
    cmp al, 2
    je .rsdp_v2
    
    ; Unknown revision
    mov rax, 2
    jmp .done
    
.rsdp_v1:
    ; RSDP v1 has only RSDT
    mov eax, [rdi + 16] ; RSDT address (32-bit)
    mov [rbx + OFFSET_ACPI_RSDT_ADDR], rax
    mov byte [rbx + OFFSET_ACPI_RSDT_FOUND], 1
    
    ; Print RSDT address
    mov rsi, msg_rsdt_found
    call scr64_print_string
    mov rsi, rax
    call scr64_print_hex
    
    xor rax, rax
    jmp .done
    
.rsdp_v2:
    ; RSDP v2 has both RSDT and XSDT
    mov eax, [rdi + 16] ; RSDT address (32-bit)
    mov [rbx + OFFSET_ACPI_RSDT_ADDR], rax
    mov byte [rbx + OFFSET_ACPI_RSDT_FOUND], 1
    
    ; Print RSDT address
    mov rsi, msg_rsdt_found
    call scr64_print_string
    mov rsi, rax
    call scr64_print_hex
    
    ; Get XSDT address (64-bit)
    mov rax, [rdi + 24]
    mov [rbx + OFFSET_ACPI_XSDT_ADDR], rax
    mov byte [rbx + OFFSET_ACPI_XSDT_FOUND], 1
    
    ; Print XSDT address
    mov rsi, msg_xsdt_found
    call scr64_print_string
    mov rsi, rax
    call scr64_print_hex
    
    xor rax, rax
    
.done:
    pop rsi
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

;--------------------------------------------------------------------------
; parse_sdt: Parses an SDT (RSDT or XSDT) to find other ACPI tables
; Input: RDI = SDT address
;        RSI = 1 if XSDT, 0 if RSDT
; Output: RAX = 0 on success, error code otherwise
;--------------------------------------------------------------------------
parse_sdt:
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
    
    ; Save is_xsdt flag
    mov r15, rsi
    
    ; Verify SDT header
    call verify_sdt_header
    test rax, rax
    jnz .done
    
    ; Calculate number of entries
    mov eax, [rdi + 4] ; Length field
    sub eax, 36 ; Subtract header size
    
    ; Divide by entry size (4 for RSDT, 8 for XSDT)
    cmp r15, 1
    je .xsdt_entries
    
    ; RSDT entries (4 bytes each)
    shr eax, 2
    jmp .process_entries
    
.xsdt_entries:
    ; XSDT entries (8 bytes each)
    shr eax, 3
    
.process_entries:
    ; RAX now contains number of entries
    mov r14, rax ; Save entry count
    mov r13, rdi ; Save SDT address
    
    ; Start processing entries
    add r13, 36 ; Skip header
    xor r12, r12 ; Entry index
    
.entry_loop:
    cmp r12, r14
    jae .success
    
    ; Get table address
    cmp r15, 1
    je .get_xsdt_entry
    
    ; RSDT entry (32-bit)
    mov eax, [r13 + r12*4]
    jmp .check_table
    
.get_xsdt_entry:
    ; XSDT entry (64-bit)
    mov rax, [r13 + r12*8]
    
.check_table:
    ; RAX now contains table address
    mov rdi, rax
    call identify_acpi_table
    
    ; Next entry
    inc r12
    jmp .entry_loop
    
.success:
    xor rax, rax
    
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
; verify_sdt_header: Verifies an SDT header checksum
; Input: RDI = SDT address
; Output: RAX = 0 if valid, error code otherwise
;--------------------------------------------------------------------------
verify_sdt_header:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rdi
    push rsi
    
    ; Get table length
    mov ecx, [rdi + 4]
    
    ; Calculate checksum
    mov rsi, rdi
    xor rax, rax
    xor rbx, rbx
    
.checksum_loop:
    mov bl, [rsi]
    add al, bl
    inc rsi
    dec ecx
    jnz .checksum_loop
    
    ; Checksum should be 0
    test al, al
    jz .valid
    
    ; Invalid checksum
    mov rax, 3
    jmp .done
    
.valid:
    xor rax, rax
    
.done:
    pop rsi
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

;--------------------------------------------------------------------------
; identify_acpi_table: Identifies an ACPI table by signature
; Input: RDI = Table address
; Output: None (updates runtime data)
;--------------------------------------------------------------------------
identify_acpi_table:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rdi
    push rsi
    
    ; Get ACPI runtime data pointer
    call get_acpi_runtime_data
    mov rbx, rax  ; Save pointer in RBX
    
    ; Check for MADT signature "APIC"
    mov eax, [rdi]
    cmp eax, 'APIC'
    je .found_madt
    
    ; Check for SRAT signature "SRAT"
    cmp eax, 'SRAT'
    je .found_srat
    
    ; Check for MCFG signature "MCFG"
    cmp eax, 'MCFG'
    je .found_mcfg
    
    ; Unknown or unneeded table
    jmp .done
    
.found_madt:
    ; Found MADT
    mov [rbx + OFFSET_ACPI_MADT_ADDR], rdi
    mov byte [rbx + OFFSET_ACPI_MADT_FOUND], 1
    
    ; Print MADT address
    mov rsi, msg_madt_found
    call scr64_print_string
    mov rsi, rdi
    call scr64_print_hex
    
    jmp .done
    
.found_srat:
    ; Found SRAT
    mov [rbx + OFFSET_ACPI_SRAT_ADDR], rdi
    mov byte [rbx + OFFSET_ACPI_SRAT_FOUND], 1
    
    ; Print SRAT address
    mov rsi, msg_srat_found
    call scr64_print_string
    mov rsi, rdi
    call scr64_print_hex
    
    jmp .done
    
.found_mcfg:
    ; Found MCFG
    mov [rbx + OFFSET_ACPI_MCFG_ADDR], rdi
    mov byte [rbx + OFFSET_ACPI_MCFG_FOUND], 1
    
    ; Print MCFG address
    mov rsi, msg_mcfg_found
    call scr64_print_string
    mov rsi, rdi
    call scr64_print_hex
    
.done:
    pop rsi
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

;--------------------------------------------------------------------------
; parse_madt: Parses the MADT to find APIC information
; Input: RDI = MADT address
; Output: RAX = 0 on success, error code otherwise
;--------------------------------------------------------------------------
parse_madt:
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
    
    ; Get ACPI runtime data pointer
    call get_acpi_runtime_data
    mov rbx, rax  ; Save pointer in RBX
    
    ; Verify MADT header
    call verify_sdt_header
    test rax, rax
    jnz .done
    
    ; Get Local APIC address
    mov eax, [rdi + 36]
    mov [rbx + OFFSET_ACPI_LAPIC_BASE], rax
    
    ; Print Local APIC base
    mov rsi, msg_lapic_base
    call scr64_print_string
    mov rsi, rax
    call scr64_print_hex
    
    ; Calculate MADT entries start
    mov r12, rdi
    add r12, 44 ; Skip header and flags
    
    ; Calculate MADT end
    mov r13, rdi
    add r13d, [rdi + 4] ; Add length
    
    ; Process MADT entries
.entry_loop:
    cmp r12, r13
    jae .success
    
    ; Get entry type
    movzx eax, byte [r12]
    
    ; Type 1 = I/O APIC
    cmp al, 1
    je .io_apic_entry
    
    ; Skip to next entry
    movzx eax, byte [r12 + 1] ; Entry length
    add r12, rax
    jmp .entry_loop
    
.io_apic_entry:
    ; Found I/O APIC entry
    mov eax, [r12 + 4] ; I/O APIC address
    mov [rbx + OFFSET_ACPI_IOAPIC_BASE], rax
    
    ; Print I/O APIC base
    mov rsi, msg_ioapic_base
    call scr64_print_string
    mov rsi, rax
    call scr64_print_hex
    
    ; Skip to next entry
    movzx eax, byte [r12 + 1] ; Entry length
    add r12, rax
    jmp .entry_loop
    
.success:
    xor rax, rax
    
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
; parse_srat: Parses the SRAT to find NUMA information
; Input: RDI = SRAT address
; Output: RAX = 0 on success, error code otherwise
;--------------------------------------------------------------------------
parse_srat:
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
    
    ; Get ACPI runtime data pointer
    call get_acpi_runtime_data
    mov rbx, rax  ; Save pointer in RBX
    
    ; Verify SRAT header
    call verify_sdt_header
    test rax, rax
    jnz .done
    
    ; Calculate SRAT entries start
    mov r12, rdi
    add r12, 48 ; Skip header and reserved fields
    
    ; Calculate SRAT end
    mov r13, rdi
    add r13d, [rdi + 4] ; Add length
    
    ; Reset NUMA node count
    mov byte [rbx + OFFSET_NUMA_NODE_COUNT], 0
    
    ; Process SRAT entries
.entry_loop:
    cmp r12, r13
    jae .success
    
    ; Get entry type
    movzx eax, byte [r12]
    
    ; Type 1 = Memory Affinity
    cmp al, 1
    je .memory_affinity_entry
    
    ; Skip to next entry
    movzx eax, byte [r12 + 1] ; Entry length
    add r12, rax
    jmp .entry_loop
    
.memory_affinity_entry:
    ; Check if enabled
    test byte [r12 + 28], 1
    jz .skip_entry
    
    ; Get node ID
    movzx edx, byte [r12 + 2]
    
    ; Check if we already have this node
    movzx ecx, byte [rbx + OFFSET_NUMA_NODE_COUNT]
    
    ; Add new node if we have space
    cmp ecx, 8
    jae .skip_entry
    
    ; Get base address and length
    mov rax, [r12 + 8] ; Base address low
    mov rdx, [r12 + 12] ; Base address high
    shl rdx, 32
    or rax, rdx
    
    ; Store base address
    mov [rbx + OFFSET_PMM_NODE_BASE_ADDRS + rcx*8], rax
    
    ; Get length
    mov rax, [r12 + 16] ; Length low
    mov rdx, [r12 + 20] ; Length high
    shl rdx, 32
    or rax, rdx
    
    ; Calculate limit
    mov rdx, [rbx + OFFSET_PMM_NODE_BASE_ADDRS + rcx*8]
    add rax, rdx
    
    ; Store limit
    mov [rbx + OFFSET_PMM_NODE_ADDR_LIMITS + rcx*8], rax
    
    ; Increment node count
    inc byte [rbx + OFFSET_NUMA_NODE_COUNT]
    
.skip_entry:
    ; Skip to next entry
    movzx eax, byte [r12 + 1] ; Entry length
    add r12, rax
    jmp .entry_loop
    
.success:
    ; Print NUMA node count
    mov rsi, msg_numa_nodes
    call scr64_print_string
    movzx rsi, byte [rbx + OFFSET_NUMA_NODE_COUNT]
    call scr64_print_dec
    
    xor rax, rax
    
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
; parse_mcfg: Parses the MCFG to find PCI Express configuration space
; Input: RDI = MCFG address
; Output: RAX = 0 on success, error code otherwise
;--------------------------------------------------------------------------
parse_mcfg:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rdi
    push rsi
    
    ; Verify MCFG header
    call verify_sdt_header
    test rax, rax
    jnz .done
    
    ; Basic MCFG parsing - just verify it exists for now
    ; Future implementation can extract PCI Express configuration space base address
    
    xor rax, rax
    
.done:
    pop rsi
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret
