; float_compare.asm: Epsilon-based floating-point comparison for Project Arora testing
; Implements precise floating-point comparisons with configurable epsilon

BITS 64
default rel

; Export floating-point comparison functions
global init_float_compare
global compare_float_epsilon
global compare_matrices_epsilon
global set_epsilon_value

; External dependencies
extern scr64_print_string
extern scr64_print_hex
extern scr64_print_dec

section .rodata
    ; Messages
    msg_float_compare_init db "Initializing epsilon-based float comparison...", 0Dh, 0Ah, 0
    msg_epsilon_set db "Epsilon value set to: ", 0
    msg_matrices_equal db "Matrices equal within epsilon", 0Dh, 0Ah, 0
    msg_matrices_differ db "Matrices differ at index ", 0
    msg_expected db ", expected: ", 0
    msg_actual db ", actual: ", 0
    msg_diff db ", diff: ", 0
    msg_newline db 0Dh, 0Ah, 0

section .data
    ; Default epsilon value (1e-6 as IEEE 754 float)
    default_epsilon dd 0.000001
    current_epsilon dd 0.000001

section .text

;--------------------------------------------------------------------------
; init_float_compare: Initialize floating-point comparison module
; Input: None
; Output: RAX = 0 (success)
;--------------------------------------------------------------------------
init_float_compare:
    push rbp
    mov rbp, rsp
    
    ; Print initialization message
    lea rsi, [rel msg_float_compare_init]
    call scr64_print_string
    
    ; Reset epsilon to default value
    movss xmm0, [rel default_epsilon]
    movss [rel current_epsilon], xmm0
    
    ; Return success
    xor rax, rax
    
    pop rbp
    ret

;--------------------------------------------------------------------------
; set_epsilon_value: Set the epsilon value for comparisons
; Input: XMM0 = New epsilon value (float)
; Output: RAX = 0 (success)
;--------------------------------------------------------------------------
set_epsilon_value:
    push rbp
    mov rbp, rsp
    
    ; Set new epsilon value
    movss [rel current_epsilon], xmm0
    
    ; Print confirmation message
    lea rsi, [rel msg_epsilon_set]
    call scr64_print_string
    
    ; Print the epsilon value (simplified - in production would use proper float printing)
    cvtss2si rsi, xmm0
    call scr64_print_dec
    lea rsi, [rel msg_newline]
    call scr64_print_string
    
    ; Return success
    xor rax, rax
    
    pop rbp
    ret

;--------------------------------------------------------------------------
; global compare_float_epsilon: Compare two float values with epsilon
; Input: XMM0 = First value, XMM1 = Second value
; Output: RAX = 0 if equal within epsilon, 1 if different
;--------------------------------------------------------------------------
global compare_float_epsilon:
    push rbp
    mov rbp, rsp
    
    ; Calculate absolute difference |a - b|
    subss xmm0, xmm1
    movss xmm2, xmm0
    pxor xmm3, xmm3
    maxss xmm0, xmm3    ; Handle negative result by taking max(result, 0)
    subss xmm3, xmm2
    maxss xmm3, xmm0    ; abs(a-b) = max(a-b, -(a-b))
    
    ; Compare with epsilon
    movss xmm0, [rel current_epsilon]
    comiss xmm3, xmm0
    jbe .equal
    
    ; Values differ by more than epsilon
    mov rax, 1
    jmp .done
    
.equal:
    ; Values are equal within epsilon
    xor rax, rax
    
.done:
    pop rbp
    ret

;--------------------------------------------------------------------------
; compare_matrices_epsilon: Compare two matrices with epsilon
; Input: RDI = First matrix, RSI = Second matrix, RDX = Size (elements)
; Output: RAX = 0 if equal within epsilon, index+1 of first difference if not
;--------------------------------------------------------------------------
compare_matrices_epsilon:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    
    ; Save parameters
    mov r12, rdi    ; First matrix
    mov r13, rsi    ; Second matrix
    mov r14, rdx    ; Size
    
    ; Initialize index
    xor rbx, rbx
    
.compare_loop:
    ; Check if we've reached the end
    cmp rbx, r14
    jge .matrices_equal
    
    ; Load values from matrices
    movss xmm0, [r12 + rbx * 4]
    movss xmm1, [r13 + rbx * 4]
    
    ; Save registers that might be modified by function call
    push rbx
    push r12
    push r13
    push r14
    
    ; Compare with epsilon
    call global compare_float_epsilon
    
    ; Restore registers
    pop r14
    pop r13
    pop r12
    pop rbx
    
    ; Check result
    test rax, rax
    jz .next_element
    
    ; Values differ - return index+1 (to distinguish from success case)
    lea rax, [rbx + 1]
    jmp .done
    
.next_element:
    ; Move to next element
    inc rbx
    jmp .compare_loop
    
.matrices_equal:
    ; All elements equal within epsilon
    xor rax, rax
    
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

;--------------------------------------------------------------------------
; print_matrix_diff: Print details about matrix difference
; Input: RDI = First matrix, RSI = Second matrix, RDX = Index of difference
; Output: None
;--------------------------------------------------------------------------
global print_matrix_diff
print_matrix_diff:
    push rbp
    mov rbp, rsp
    
    ; Print difference message
    lea rsi, [rel msg_matrices_differ]
    call scr64_print_string
    
    ; Print index
    mov rsi, rdx
    call scr64_print_dec
    
    ; Print expected value
    lea rsi, [rel msg_expected]
    call scr64_print_string
    
    ; Load and print expected value (simplified)
    mov rax, rdi
    movss xmm0, [rax + rdx * 4]
    cvtss2si rsi, xmm0
    call scr64_print_dec
    
    ; Print actual value
    lea rsi, [rel msg_actual]
    call scr64_print_string
    
    ; Load and print actual value (simplified)
    mov rax, rsi
    movss xmm0, [rax + rdx * 4]
    cvtss2si rsi, xmm0
    call scr64_print_dec
    
    ; Calculate and print difference
    mov rax, rdi
    movss xmm0, [rax + rdx * 4]
    mov rax, rsi
    movss xmm1, [rax + rdx * 4]
    subss xmm0, xmm1
    
    lea rsi, [rel msg_diff]
    call scr64_print_string
    
    cvtss2si rsi, xmm0
    call scr64_print_dec
    
    lea rsi, [rel msg_newline]
    call scr64_print_string
    
    pop rbp
    ret