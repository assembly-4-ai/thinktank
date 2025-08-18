; hex_utils.asm: Hexadecimal utility functions
; Project Arora - Bare-Metal NASM AI Implementation

section .text
    global hex_to_string

hex_to_string:
    ; Converts a 64-bit integer to its hexadecimal ASCII representation
    ; Input: RDI = number, RSI = buffer
    ; Output: RAX = pointer to the start of the string in the buffer

    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    
    mov r8, rdi      ; number
    mov r9, rsi      ; buffer
    
    ; Start from the end of the buffer (16 chars for 64-bit hex + null)
    add r9, 16
    mov byte [r9], 0 ; Null terminator
    dec r9
    
    ; Loop 16 times for 64-bit hex
    mov rcx, 16
    
.loop:
    mov rdx, r8
    and rdx, 0xF     ; Get last 4 bits
    cmp rdx, 9
    jle .digit
    add rdx, 7       ; For A-F
    
.digit:
    add rdx, '0'
    mov [r9], dl
    dec r9
    shr r8, 4        ; Shift right by 4 bits
    loop .loop
    
    inc r9           ; Adjust pointer to start of string
    mov rax, r9
    
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret


