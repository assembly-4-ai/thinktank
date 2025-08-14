; error_pic.asm: Error handling and panic functions (PIC-compliant)
; Depends on: boot_defs_temp.inc

BITS 64
default rel
%include "boot_defs_temp.inc"

global panic64

extern scr64_print_string
extern scr64_print_hex
extern scr64_print_dec
extern scr64_print_char

section .text

;--------------------------------------------------------------------------
; panic64: Handles fatal CPU exceptions
; Input: RDI = Exception number, RSI = Error code
; Output: None (does not return)
;--------------------------------------------------------------------------
panic64:
    ; Save all registers
    push rax
    push rbx
    push rcx
    push rdx
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15
    
    ; Print panic message
    lea rax, [rel panic_msg]
    mov rdi, rax
    call scr64_print_string
    
    ; Print exception number
    pop rax  ; Get exception number from stack
    push rax ; Save it back
    mov rdi, rax
    call scr64_print_dec
    
    ; Print error code
    lea rax, [rel error_code_msg]
    mov rdi, rax
    call scr64_print_string
    
    pop rax  ; Get error code from stack
    push rax ; Save it back
    mov rdi, rax
    call scr64_print_hex
    
    ; Print newline
    mov rdi, 10  ; ASCII for newline
    call scr64_print_char
    
    ; Restore registers
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rbx
    pop rax
    
    ; Halt the system
.halt:
    cli
    hlt
    jmp .halt

section .rodata
panic_msg:      db "PANIC: CPU Exception #", 0
error_code_msg: db ", Error Code: 0x", 0
