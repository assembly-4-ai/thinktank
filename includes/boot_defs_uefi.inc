; boot_defs_uefi.inc: Additional UEFI-specific definitions for Project Arora

%ifndef BOOT_DEFS_UEFI_INC
%define BOOT_DEFS_UEFI_INC

; UEFI File I/O related offsets
%define OFFSET_SFS_OPENVOLUME 0x08
%define OFFSET_FILE_OPEN      0x08
%define OFFSET_FILE_CLOSE     0x10
%define OFFSET_FILE_READ      0x18
%define OFFSET_FILE_WRITE     0x20
%define OFFSET_FILE_GET_POS   0x28
%define OFFSET_FILE_SET_POS   0x30

; UEFI File I/O related constants
%define EFI_FILE_MODE_READ    0x0000000000000001
%define EFI_FILE_MODE_WRITE   0x0000000000000002
%define EFI_FILE_MODE_CREATE  0x8000000000000000

%endif ; BOOT_DEFS_UEFI_INC
