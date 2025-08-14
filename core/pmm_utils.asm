; pmm_utils.asm: Physical Memory Manager utility functions
; Project Arora - Bare-Metal NASM AI Implementation

section .text
    global pmm_get_total_memory
    global pmm_get_free_memory

pmm_get_total_memory:
    ; Returns total physical memory
    ; TODO: Implement actual memory detection
    mov rax, 4096 * 1024 * 1024 ; 4GB for now
    ret

pmm_get_free_memory:
    ; Returns free physical memory
    ; TODO: Implement actual memory detection
    mov rax, 4096 * 1024 * 1024 ; 4GB for now
    ret


