; numa_pic.asm: NUMA support functions (PIC-compliant)
; Provides NUMA node information in a position-independent way

BITS 64
default rel

; Exports
global get_numa_node_count
global init_numa_runtime_data
global get_numa_node_base, get_numa_node_limit
global numa_node_count

; External dependencies
extern pmm_alloc_frame
extern scr64_print_string

%include "boot_defs_temp.inc"

; Structure of runtime NUMA data block:
; Offset 0:  numa_runtime_data_ptr (qword)
; Offset 8:  numa_node_count (byte)
; Offset 9:  padding (7 bytes)
; Offset 16: numa_node_base_addrs[8] (8 qwords = 64 bytes)
; Offset 80: numa_node_addr_limits[8] (8 qwords = 64 bytes)
; Total size: 144 bytes

%define NUMA_RUNTIME_DATA_SIZE 144
%define OFFSET_NUMA_RUNTIME_PTR 0
%define OFFSET_NUMA_NODE_COUNT 8
%define OFFSET_NUMA_NODE_BASE_ADDRS 16
%define OFFSET_NUMA_NODE_ADDR_LIMITS 80

section .data
    ; Single global pointer to runtime allocated data
    numa_runtime_data_ptr dq 0
    
    ; Default node count for compatibility (renamed to avoid redefinition)
    default_node_count db 1
    
    ; Error messages
    msg_numa_init db "Initializing NUMA support...", 0
    msg_numa_error db "NUMA initialization error", 0

section .text

;--------------------------------------------------------------------------
; init_numa_runtime_data: Allocate and initialize NUMA runtime data
; Input: None
; Output: RAX = 0 on success, error code otherwise
;--------------------------------------------------------------------------
init_numa_runtime_data:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rdi
    push rsi
    
    ; Check if already initialized
    mov rax, [rel numa_runtime_data_ptr]
    test rax, rax
    jnz .already_initialized
    
    ; Print initialization message
    lea rsi, [rel msg_numa_init]
    call scr64_print_string
    
    ; Allocate memory for NUMA runtime data
    mov rdi, (NUMA_RUNTIME_DATA_SIZE + 4095) / 4096  ; Pages needed
    call pmm_alloc_frame
    test rax, rax
    jz .allocation_error
    
    ; Save pointer to allocated memory
    mov [rel numa_runtime_data_ptr], rax
    mov rbx, rax  ; Save pointer in RBX
    
    ; Store self-reference at offset 0
    mov [rbx + OFFSET_NUMA_RUNTIME_PTR], rax
    
    ; Initialize node count to 1 (default)
    mov byte [rbx + OFFSET_NUMA_NODE_COUNT], 1
    
    ; Initialize all node base addresses and limits to 0
    lea rdi, [rbx + OFFSET_NUMA_NODE_BASE_ADDRS]
    mov rcx, 16  ; 16 qwords (8 base + 8 limit)
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
    lea rsi, [rel msg_numa_error]
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
; get_numa_runtime_data: Get pointer to NUMA runtime data
; Input: None
; Output: RAX = Pointer to NUMA runtime data, 0 if not initialized
;--------------------------------------------------------------------------
get_numa_runtime_data:
    mov rax, [rel numa_runtime_data_ptr]
    ret

;--------------------------------------------------------------------------
; get_numa_node_count: Get number of NUMA nodes
; Input: None
; Output: RAX = Number of NUMA nodes
;--------------------------------------------------------------------------
get_numa_node_count:
    push rbp
    mov rbp, rsp
    
    ; Get NUMA runtime data pointer
    call get_numa_runtime_data
    test rax, rax
    jz .not_initialized
    
    ; Return node count
    movzx rax, byte [rax + OFFSET_NUMA_NODE_COUNT]
    jmp .done
    
.not_initialized:
    ; Return default node count if not initialized
    movzx rax, byte [rel default_node_count]
    
.done:
    pop rbp
    ret

;--------------------------------------------------------------------------
; numa_node_count: Legacy compatibility function for numa_node_count global
; Input: None
; Output: RAX = Number of NUMA nodes
;--------------------------------------------------------------------------
numa_node_count:
    jmp get_numa_node_count

;--------------------------------------------------------------------------
; get_numa_node_base: Get base address of a NUMA node
; Input: RDI = Node ID
; Output: RAX = Base address of the node
;--------------------------------------------------------------------------
get_numa_node_base:
    push rbp
    mov rbp, rsp
    
    ; Get NUMA runtime data pointer
    call get_numa_runtime_data
    test rax, rax
    jz .not_initialized
    
    ; Check if node ID is valid
    movzx rcx, byte [rax + OFFSET_NUMA_NODE_COUNT]
    cmp rdi, rcx
    jae .invalid_node
    
    ; Return node base address
    mov rax, [rax + OFFSET_NUMA_NODE_BASE_ADDRS + rdi*8]
    jmp .done
    
.not_initialized:
.invalid_node:
    ; Return 0 if not initialized or invalid node
    xor rax, rax
    
.done:
    pop rbp
    ret

;--------------------------------------------------------------------------
; get_numa_node_limit: Get limit address of a NUMA node
; Input: RDI = Node ID
; Output: RAX = Limit address of the node
;--------------------------------------------------------------------------
get_numa_node_limit:
    push rbp
    mov rbp, rsp
    
    ; Get NUMA runtime data pointer
    call get_numa_runtime_data
    test rax, rax
    jz .not_initialized
    
    ; Check if node ID is valid
    movzx rcx, byte [rax + OFFSET_NUMA_NODE_COUNT]
    cmp rdi, rcx
    jae .invalid_node
    
    ; Return node limit address
    mov rax, [rax + OFFSET_NUMA_NODE_ADDR_LIMITS + rdi*8]
    jmp .done
    
.not_initialized:
.invalid_node:
    ; Return 0 if not initialized or invalid node
    xor rax, rax
    
.done:
    pop rbp
    ret
