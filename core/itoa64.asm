; itoa64.asm: Integer to ASCII conversion for 64-bit integers
; Project Arora - Bare-Metal NASM AI Implementation

section .text
    global itoa64

itoa64:
    ; Converts a 64-bit integer to its ASCII representation
    ; Input: RDI = number, RSI = buffer, RDX = base (e.g., 10 for decimal)
    ; Output: RAX = pointer to the start of the string in the buffer

    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    
    mov r8, rdi      ; number
    mov r9, rsi      ; buffer
    mov r10, rdx     ; base
    
    ; Handle zero case
    cmp r8, 0
    jnz .not_zero
    mov byte [r9], '0'
    mov byte [r9 + 1], 0
    mov rax, r9
    jmp .done
    
.not_zero:
    ; Start from the end of the buffer (max 20 chars for 64-bit decimal + null)
    add r9, 20
    mov byte [r9], 0 ; Null terminator
    dec r9
    
.loop:
    test r8, r8
    jz .loop_end
    
    xor rdx, rdx
    mov rax, r8
    div r10          ; RDX = remainder, RAX = quotient
    
    add rdx, '0'
    cmp rdx, '9'
    jle .digit
    add rdx, 7       ; For hex A-F
    
.digit:
    mov [r9], dl
    dec r9
    mov r8, rax
    jmp .loop
    
.loop_end:
    inc r9           ; Adjust pointer to start of string
    mov rax, r9
    
.done:
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret


