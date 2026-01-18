; core/rt0-efi-x86_64.asm - UEFI Entry Point
; This file provides the _start symbol, which is the actual
; entry point for the UEFI executable. It sets up the stack
; and calls the C-style efi_main function.

BITS 64
default rel

section .text

; External C-style main function
extern efi_main

; UEFI entry point
global _start
_start:
    ; UEFI ABI requires the stack to be 16-byte aligned before a call.
    ; The firmware guarantees this at entry, but we'll enforce it.
    and rsp, -16

    ; According to the System V AMD64 ABI (used by GCC/Clang on Linux/macOS)
    ; and the Microsoft x64 calling convention, the first two arguments are
    ; passed in RCX and RDX. For UEFI, these are:
    ; RCX = ImageHandle
    ; RDX = SystemTable
    ; We need to move them to RDI and RSI for our efi_main, which follows
    ; a more traditional C-style convention for clarity.
    mov rdi, rcx
    mov rsi, rdx

    ; Call the main function
    call efi_main

    ; If efi_main returns, it's considered a successful exit.
    ; The return value from efi_main is in RAX.
    ; We can simply return from _start, and the UEFI loader will handle it.
    ret
