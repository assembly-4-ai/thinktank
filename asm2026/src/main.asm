bits 64
default rel

%include "efi.inc"

global _start

section .text

_start:
    ; UEFI entry point:
    ; RCX = ImageHandle
    ; RDX = SystemTable

    push rbp
    mov rbp, rsp
    sub rsp, 32 ; Shadow space

    ; SystemTable is in RDX. We can use R8 (volatile) to save it.
    mov r8, rdx

    ; Get ConOut protocol pointer from SystemTable
    mov rcx, [r8 + OFFSET_ST_CONOUT]

    ; Call OutputString(ConOut, hello_msg)
    ; RCX = ConOut protocol pointer
    ; RDX = String pointer (UTF-16)
    lea rdx, [rel hello_msg]
    mov rax, [rcx + OFFSET_CONOUT_OUTPUTSTRING]
    call rax

    add rsp, 32
    pop rbp
    xor rax, rax ; EFI_SUCCESS
    ret

section .rodata
    ; "Asm2026 Project Started!" in UTF-16LE
    hello_msg dw 'A','s','m','2','0','2','6',' ','P','r','o','j','e','c','t',' ','S','t','a','r','t','e','d','!',13,10,0
