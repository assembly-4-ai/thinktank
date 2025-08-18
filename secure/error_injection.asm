; error_injection.asm: Error injection framework for Project Arora testing
; Implements controlled error injection for robustness testing

BITS 64
default rel

; Export error injection functions
global init_error_injection
global inject_memory_allocation_failure
global inject_data_corruption
global inject_invalid_input
global reset_error_injection

; External dependencies
extern scr64_print_string

section .rodata
    ; Error injection messages
    msg_error_injection_init db "Initializing error injection framework...", 0Dh, 0Ah, 0
    msg_memory_failure_injected db "Memory allocation failure injected", 0Dh, 0Ah, 0
    msg_data_corruption_injected db "Data corruption injected", 0Dh, 0Ah, 0
    msg_invalid_input_injected db "Invalid input injected", 0Dh, 0Ah, 0
    msg_error_injection_reset db "Error injection framework reset", 0Dh, 0Ah, 0

section .data
    ; Error injection control flags
    inject_memory_failure dd 0    ; When set, simulates memory allocation failure
    inject_corruption dd 0        ; When set, corrupts data at specified location
    inject_invalid dd 0           ; When set, modifies inputs to create invalid state
    
    ; Error injection parameters
    corruption_address dq 0       ; Address to corrupt
    corruption_pattern dq 0       ; Pattern to use for corruption
    corruption_size dd 0          ; Size of corruption in bytes

section .text

;--------------------------------------------------------------------------
; init_error_injection: Initialize error injection framework
; Input: None
; Output: RAX = 0 (success)
;--------------------------------------------------------------------------
init_error_injection:
    push rbp
    mov rbp, rsp
    
    ; Print initialization message
    lea rsi, [rel msg_error_injection_init]
    call scr64_print_string
    
    ; Reset all injection flags
    mov dword [rel inject_memory_failure], 0
    mov dword [rel inject_corruption], 0
    mov dword [rel inject_invalid], 0
    
    ; Clear injection parameters
    mov qword [rel corruption_address], 0
    mov qword [rel corruption_pattern], 0
    mov dword [rel corruption_size], 0
    
    ; Return success
    xor rax, rax
    
    pop rbp
    ret

;--------------------------------------------------------------------------
; inject_memory_allocation_failure: Set up memory allocation failure injection
; Input: RDI = 1 to enable, 0 to disable
; Output: RAX = Previous state
;--------------------------------------------------------------------------
inject_memory_allocation_failure:
    push rbp
    mov rbp, rsp
    
    ; Save previous state
    mov eax, [rel inject_memory_failure]
    
    ; Set new state
    mov [rel inject_memory_failure], edi
    
    ; Print message if enabling
    test edi, edi
    jz .skip_message
    
    push rax
    lea rsi, [rel msg_memory_failure_injected]
    call scr64_print_string
    pop rax
    
.skip_message:
    pop rbp
    ret

;--------------------------------------------------------------------------
; inject_data_corruption: Set up data corruption injection
; Input: RDI = Address to corrupt, RSI = Pattern, RDX = Size in bytes
; Output: RAX = 0 (success)
;--------------------------------------------------------------------------
inject_data_corruption:
    push rbp
    mov rbp, rsp
    
    ; Save corruption parameters
    mov [rel corruption_address], rdi
    mov [rel corruption_pattern], rsi
    mov [rel corruption_size], edx
    
    ; Enable corruption
    mov dword [rel inject_corruption], 1
    
    ; Print message
    push rdi
    push rsi
    push rdx
    lea rsi, [rel msg_data_corruption_injected]
    call scr64_print_string
    pop rdx
    pop rsi
    pop rdi
    
    ; Apply corruption immediately if address is non-zero
    test rdi, rdi
    jz .skip_corruption
    
    ; Corrupt memory with pattern
    mov rcx, rdx
    mov rax, rsi
.corrupt_loop:
    test rcx, rcx
    jz .skip_corruption
    
    mov [rdi], al
    inc rdi
    dec rcx
    jmp .corrupt_loop
    
.skip_corruption:
    ; Return success
    xor rax, rax
    
    pop rbp
    ret

;--------------------------------------------------------------------------
; inject_invalid_input: Set up invalid input injection
; Input: RDI = 1 to enable, 0 to disable
; Output: RAX = Previous state
;--------------------------------------------------------------------------
inject_invalid_input:
    push rbp
    mov rbp, rsp
    
    ; Save previous state
    mov eax, [rel inject_invalid]
    
    ; Set new state
    mov [rel inject_invalid], edi
    
    ; Print message if enabling
    test edi, edi
    jz .skip_message
    
    push rax
    lea rsi, [rel msg_invalid_input_injected]
    call scr64_print_string
    pop rax
    
.skip_message:
    pop rbp
    ret

;--------------------------------------------------------------------------
; reset_error_injection: Reset all error injection settings
; Input: None
; Output: RAX = 0 (success)
;--------------------------------------------------------------------------
reset_error_injection:
    push rbp
    mov rbp, rsp
    
    ; Reset all injection flags
    mov dword [rel inject_memory_failure], 0
    mov dword [rel inject_corruption], 0
    mov dword [rel inject_invalid], 0
    
    ; Clear injection parameters
    mov qword [rel corruption_address], 0
    mov qword [rel corruption_pattern], 0
    mov dword [rel corruption_size], 0
    
    ; Print message
    lea rsi, [rel msg_error_injection_reset]
    call scr64_print_string
    
    ; Return success
    xor rax, rax
    
    pop rbp
    ret

;--------------------------------------------------------------------------
; Hooks for system functions to enable error injection
;--------------------------------------------------------------------------

; Hook for pmm_alloc_frame to enable memory allocation failure injection
; This would be called by a modified version of the test harness
; that replaces direct calls to pmm_alloc_frame with calls to this function
global pmm_alloc_frame_hook
pmm_alloc_frame_hook:
    push rbp
    mov rbp, rsp
    
    ; Check if memory failure injection is enabled
    cmp dword [rel inject_memory_failure], 0
    je .normal_allocation
    
    ; Simulate allocation failure
    xor rax, rax
    jmp .done
    
.normal_allocation:
    ; Call the real allocation function
    ; The original function should be renamed or this should use a different approach
    ; to avoid recursive calls
    call pmm_alloc_frame
    
.done:
    pop rbp
    ret

extern pmm_alloc_frame


