; image_base.asm - Provides ImageBase symbol required by GNU-EFI
; This is a special symbol required by the UEFI PE/COFF format

BITS 64
default rel

; Export the ImageBase symbol required by GNU-EFI
global ImageBase

section .data
; Define ImageBase as a quad-word (8 bytes) with value 0
; This will be properly relocated by the PE/COFF loader at runtime
ImageBase dq 0
