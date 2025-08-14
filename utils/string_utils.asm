; string_utils.asm: String utility functions
; Project Arora - Bare-Metal NASM AI Implementation

section .text
    global string_compare

string_compare:
    ; Compares two null-terminated strings
    ; Input: RDI = string1_ptr, RSI = string2_ptr
    ; Output: RAX = 0 if equal, non-zero otherwise

    push rbp
    mov rbp, rsp

.loop:
    mov al, [rdi]
    mov bl, [rsi]
    cmp al, bl
    jne .not_equal
    test al, al
    jz .equal
    inc rdi
    inc rsi
    jmp .loop

.not_equal:
    mov rax, 1
    jmp .end

.equal:
    xor rax, rax

.end:
    pop rbp
    ret




    global string_copy

string_copy:
    ; Copies a null-terminated string from source to destination
    ; Input: RDI = dest_ptr, RSI = src_ptr
    ; Output: RAX = dest_ptr

    push rbp
    mov rbp, rsp

.loop:
    mov al, [rsi]
    mov [rdi], al
    test al, al
    jz .end
    inc rsi
    inc rdi
    jmp .loop

.end:
    mov rax, rdi
    pop rbp
    ret


