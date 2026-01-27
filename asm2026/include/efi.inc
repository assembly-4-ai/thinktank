%ifndef EFI_INC
%define EFI_INC

; UEFI Calling Convention: Microsoft x64
; RCX, RDX, R8, R9 for first 4 arguments, then stack.
; Shadow space (32 bytes) must be allocated on stack.
; Volatile registers: RAX, RCX, RDX, R8, R9, R10, R11
; Non-volatile: RBX, RBP, RDI, RSI, R12, R13, R14, R15

%define EFI_SUCCESS 0

; Standard UEFI 64-bit System Table Offsets
; 0x00: Hdr (24 bytes)
; 0x18: FirmwareVendor (8 bytes)
; 0x20: FirmwareRevision (4 bytes)
; 0x24: Padding (4 bytes)
; 0x28: ConsoleInHandle (8 bytes)
; 0x30: ConIn (8 bytes)
; 0x38: ConsoleOutHandle (8 bytes)
%define OFFSET_ST_CONOUT           0x40 ; ConOut protocol pointer (64)
%define OFFSET_CONOUT_OUTPUTSTRING 0x08 ; OutputString function pointer (8)

%endif
