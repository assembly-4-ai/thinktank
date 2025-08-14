; fat32_runtime.asm: FAT32 Filesystem Driver (64-bit, uses AHCI Driver)
; PIC-compliant version that avoids global variables in .bss/.data sections
; Depends on: boot_defs_temp.inc (which includes ahci_defs.inc and uefi_defs.inc)
;             ahci.asm (for ahci_read_sectors etc.)

BITS 64
default rel
global fat32_init_partition, fat32_read_file, fat32_write_file, fat32_create_file
global fat32_find_entry, fat32_get_next_cluster, fat32_init
global init_fat32_runtime_data, get_current_dir_cluster, set_current_dir_cluster

; --- Externals ---
extern ahci_read_sectors, ahci_write_sectors, ahci_flush_cache
extern memcpy64, memset64
extern scr64_print_string, scr64_print_hex, scr64_print_dec
extern panic64
extern pmm_alloc_frame, pmm_free_frame

; Explicitly define all required FAT32 constants to avoid macro expansion issues
%define PAGE_SIZE_4K            4096

; FAT32 Error Codes
%define FAT_ERR_OK              0
%define FAT_ERR_NOT_INIT        1
%define FAT_ERR_DISK_ERROR      2
%define FAT_ERR_NOT_FOUND       3
%define FAT_ERR_BAD_CLUSTER     4
%define FAT_ERR_FAT_READ        5
%define FAT_ERR_EOF             6
%define FAT_ERR_BUFFER_SMALL    7
%define FAT_ERR_NOT_FAT32       8
%define FAT_ERR_BAD_BPB         9
%define FAT_ERR_INVALID_PARAM   10
%define FAT_ERR_NO_FREE_CLUSTER 11
%define FAT_ERR_NOT_IMPLEMENTED 12
%define FAT_ERR_FILE_EXISTS     13
%define FAT_ERR_DIR_FULL        14
%define FAT_ERR_GPT_ERROR       15

; FAT32 BPB Offsets
%define FAT_BPB_BytesPerSector    11
%define FAT_BPB_SectorsPerCluster 13
%define FAT_BPB_ReservedSectors   14
%define FAT_BPB_NumberOfFATs      16
%define FAT32_BPB_SectorsPerFAT32 36
%define FAT32_BPB_RootCluster     44
%define FAT32_BPB_FSInfo          48
%define FAT32_BPB_FSType          82

; FAT32 Directory Entry Offsets
%define FAT_DIRENT_Name           0
%define FAT_DIRENT_Attributes     11
%define FAT_DIRENT_NTRes          12
%define FAT_DIRENT_CrtTimeTenth   13
%define FAT_DIRENT_CrtTime        14
%define FAT_DIRENT_CrtDate        16
%define FAT_DIRENT_LstAccDate     18
%define FAT_DIRENT_FstClusHI      20
%define FAT_DIRENT_WrtTime        22
%define FAT_DIRENT_WrtDate        24
%define FAT_DIRENT_FstClusLO      26
%define FAT_DIRENT_FileSize       28
%define FAT_DIRENT_SIZE           32

; FAT32 Attribute Flags
%define FAT_ATTR_READ_ONLY        0x01
%define FAT_ATTR_HIDDEN           0x02
%define FAT_ATTR_SYSTEM           0x04
%define FAT_ATTR_VOLUME_ID        0x08
%define FAT_ATTR_DIRECTORY        0x10
%define FAT_ATTR_ARCHIVE          0x20
%define FAT_ATTR_LONG_NAME        0x0F
%define FAT_ATTR_LFN_MASK         0x3F

; FAT32 Cluster Constants
%define FAT32_CLUSTER_FREE        0x00000000
%define FAT32_CLUSTER_RESERVED    0x00000001
%define FAT32_CLUSTER_MIN_VALID   0x00000002
%define FAT32_CLUSTER_MAX_VALID   0x0FFFFFF6
%define FAT32_CLUSTER_BAD         0x0FFFFFF7
%define FAT32_CLUSTER_EOF_MIN     0x0FFFFFF8
%define FAT32_CLUSTER_EOF_MAX     0x0FFFFFFF

%include "boot_defs_temp.inc" ; Include for other definitions

; Structure of runtime FAT32 data block:
; Offset 0:  fat32_runtime_data_ptr (qword)
; Offset 8:  fat32_initialized (byte)
; Offset 9:  padding (7 bytes)
; Offset 16: fat32_partition_lba (qword)
; Offset 24: fat32_ahci_port (dword)
; Offset 28: padding (4 bytes)
; Offset 32: fat32_bytes_per_sector (word)
; Offset 34: fat32_sectors_per_cluster (byte)
; Offset 35: padding (1 byte)
; Offset 36: fat32_reserved_sectors (word)
; Offset 38: fat32_num_fats (byte)
; Offset 39: padding (1 byte)
; Offset 40: fat32_sectors_per_fat (dword)
; Offset 44: fat32_root_cluster (dword)
; Offset 48: fat32_first_data_sector (dword)
; Offset 52: fat32_fat_lba (dword)
; Offset 56: fat32_bytes_per_cluster (dword)
; Offset 60: fat32_fsinfo_sector (word)
; Offset 62: padding (2 bytes)
; Offset 64: fat32_fat_cache_lba (qword)
; Offset 72: fat32_fat_cache_dirty (byte)
; Offset 73: padding (3 bytes)
; Offset 76: current_dir_cluster (dword)
; Offset 80: sector_buffer (4096 bytes)
; Total size: 4176 bytes

%define FAT32_RUNTIME_DATA_SIZE 4176
%define OFFSET_FAT32_RUNTIME_PTR 0
%define OFFSET_FAT32_INITIALIZED 8
%define OFFSET_FAT32_PARTITION_LBA 16
%define OFFSET_FAT32_AHCI_PORT 24
%define OFFSET_FAT32_BYTES_PER_SECTOR 32
%define OFFSET_FAT32_SECTORS_PER_CLUSTER 34
%define OFFSET_FAT32_RESERVED_SECTORS 36
%define OFFSET_FAT32_NUM_FATS 38
%define OFFSET_FAT32_SECTORS_PER_FAT 40
%define OFFSET_FAT32_ROOT_CLUSTER 44
%define OFFSET_FAT32_FIRST_DATA_SECTOR 48
%define OFFSET_FAT32_FAT_LBA 52
%define OFFSET_FAT32_BYTES_PER_CLUSTER 56
%define OFFSET_FAT32_FSINFO_SECTOR 60
%define OFFSET_FAT32_FAT_CACHE_LBA 64
%define OFFSET_FAT32_FAT_CACHE_DIRTY 72
%define OFFSET_CURRENT_DIR_CLUSTER 76
%define OFFSET_SECTOR_BUFFER 80

section .rodata
; Messages
msg_fat32_bpb_ok   db "FAT32: BPB Parsed OK", 0Dh, 0Ah, 0
msg_fat32_not_fat32 db "FAT32: Filesystem not FAT32!", 0Dh, 0Ah, 0
msg_fat32_bad_bpb  db "FAT32: BPB Invalid!", 0Dh, 0Ah, 0
msg_fat32_read_err db "FAT32: Disk Read Error!", 0Dh, 0Ah, 0
msg_fat32_write_err db "FAT32: Disk Write Error!", 0Dh, 0Ah, 0
msg_fat32_fat_err  db "FAT32: FAT Access Error!", 0Dh, 0Ah, 0
msg_fat32_alloc_error db "FAT32: Runtime data allocation error", 0Dh, 0Ah, 0

fs_type_string_fat32 db "FAT32   " ; Must be 8 chars, space padded

section .data
    ; Single global pointer to runtime allocated data
    fat32_runtime_data_ptr dq 0

section .text

;--------------------------------------------------------------------------
; init_fat32_runtime_data: Allocate and initialize FAT32 runtime data
; Input: None
; Output: RAX = 0 on success, error code otherwise
;--------------------------------------------------------------------------
init_fat32_runtime_data:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rdi
    push rsi
    
    ; Check if already initialized
    mov rax, [fat32_runtime_data_ptr]
    test rax, rax
    jnz .already_initialized
    
    ; Allocate memory for FAT32 runtime data
    mov rdi, (FAT32_RUNTIME_DATA_SIZE + 4095) / 4096  ; Pages needed
    call pmm_alloc_frame
    test rax, rax
    jz .allocation_error
    
    ; Save pointer to allocated memory
    mov [fat32_runtime_data_ptr], rax
    mov rdi, rax
    
    ; Store self-reference at offset 0
    mov [rdi + OFFSET_FAT32_RUNTIME_PTR], rax
    
    ; Initialize FAT32 data
    mov byte [rdi + OFFSET_FAT32_INITIALIZED], 0
    mov qword [rdi + OFFSET_FAT32_PARTITION_LBA], 0
    mov dword [rdi + OFFSET_FAT32_AHCI_PORT], 0
    mov word [rdi + OFFSET_FAT32_BYTES_PER_SECTOR], 512  ; Default
    mov byte [rdi + OFFSET_FAT32_SECTORS_PER_CLUSTER], 0
    mov word [rdi + OFFSET_FAT32_RESERVED_SECTORS], 0
    mov byte [rdi + OFFSET_FAT32_NUM_FATS], 0
    mov dword [rdi + OFFSET_FAT32_SECTORS_PER_FAT], 0
    mov dword [rdi + OFFSET_FAT32_ROOT_CLUSTER], 0
    mov dword [rdi + OFFSET_FAT32_FIRST_DATA_SECTOR], 0
    mov dword [rdi + OFFSET_FAT32_FAT_LBA], 0
    mov dword [rdi + OFFSET_FAT32_BYTES_PER_CLUSTER], 0
    mov word [rdi + OFFSET_FAT32_FSINFO_SECTOR], 0
    mov qword [rdi + OFFSET_FAT32_FAT_CACHE_LBA], -1
    mov byte [rdi + OFFSET_FAT32_FAT_CACHE_DIRTY], 0
    mov dword [rdi + OFFSET_CURRENT_DIR_CLUSTER], 0
    
    ; Clear sector buffer
    lea rdi, [rdi + OFFSET_SECTOR_BUFFER]
    mov rcx, PAGE_SIZE_4K / 8  ; Size in qwords
    xor rax, rax
    rep stosq
    
    ; Success
    xor rax, rax
    jmp .done
    
.already_initialized:
    ; Already initialized, return success
    xor rax, rax
    jmp .done
    
.allocation_error:
    ; Failed to allocate memory
    mov rsi, msg_fat32_alloc_error
    call scr64_print_string
    mov rax, 1
    
.done:
    pop rsi
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

;--------------------------------------------------------------------------
; get_fat32_runtime_data: Get pointer to FAT32 runtime data
; Input: None
; Output: RAX = Pointer to FAT32 runtime data, 0 if not initialized
;--------------------------------------------------------------------------
get_fat32_runtime_data:
    mov rax, [fat32_runtime_data_ptr]
    ret

;--------------------------------------------------------------------------
; get_current_dir_cluster: Get current directory cluster
; Input: None
; Output: RAX = Current directory cluster
;--------------------------------------------------------------------------
get_current_dir_cluster:
    push rbp
    mov rbp, rsp
    
    ; Get FAT32 runtime data pointer
    call get_fat32_runtime_data
    test rax, rax
    jz .not_initialized
    
    ; Get current directory cluster
    mov eax, [rax + OFFSET_CURRENT_DIR_CLUSTER]
    jmp .done
    
.not_initialized:
    ; Return 0 if not initialized
    xor rax, rax
    
.done:
    pop rbp
    ret

;--------------------------------------------------------------------------
; set_current_dir_cluster: Set current directory cluster
; Input: RDI = New directory cluster
; Output: None
;--------------------------------------------------------------------------
set_current_dir_cluster:
    push rbp
    mov rbp, rsp
    
    ; Get FAT32 runtime data pointer
    call get_fat32_runtime_data
    test rax, rax
    jz .not_initialized
    
    ; Set current directory cluster
    mov [rax + OFFSET_CURRENT_DIR_CLUSTER], edi
    
.not_initialized:
    pop rbp
    ret

;--------------------------------------------------------------------------
; fat32_flush_fat_cache: Flush FAT cache to disk if dirty
; Input: None
; Output: RAX = 0 on success, error code otherwise, CF set on error
;--------------------------------------------------------------------------
fat32_flush_fat_cache:
    push rbp
    mov rbp, rsp
    push rbx
    
    ; Get FAT32 runtime data pointer
    call get_fat32_runtime_data
    mov rbx, rax  ; Save pointer in RBX
    
    ; Check if cache is dirty
    cmp byte [rbx + OFFSET_FAT32_FAT_CACHE_DIRTY], 1
    jne .flush_not_dirty
    
    ; Check if cache is valid
    mov rsi, [rbx + OFFSET_FAT32_FAT_CACHE_LBA]
    cmp rsi, -1
    je .flush_not_dirty
    
    ; Write cache to disk
    mov edi, [rbx + OFFSET_FAT32_AHCI_PORT]
    mov edx, 1
    lea rcx, [rbx + OFFSET_SECTOR_BUFFER]
    mov r8b, 1
    call ahci_write_sectors
    jc .flush_error
    test rax, rax
    jnz .flush_error
    
    ; Mark cache as clean
    mov byte [rbx + OFFSET_FAT32_FAT_CACHE_DIRTY], 0
    
.flush_not_dirty:
    xor rax, rax
    clc
    jmp .done
    
.flush_error:
    mov rax, FAT_ERR_DISK_ERROR
    stc
    
.done:
    pop rbx
    pop rbp
    ret

;--------------------------------------------------------------------------
; fat32_read_fat_sector: Read FAT sector into cache
; Input: RSI = Absolute LBA of FAT sector
; Output: RAX = 0 on success, error code otherwise, CF set on error
;--------------------------------------------------------------------------
fat32_read_fat_sector:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    
    ; Get FAT32 runtime data pointer
    call get_fat32_runtime_data
    mov rbx, rax  ; Save pointer in RBX
    
    ; Check if sector is already in cache
    cmp rsi, [rbx + OFFSET_FAT32_FAT_CACHE_LBA]
    je .read_fat_ok
    
    ; Flush cache if dirty
    call fat32_flush_fat_cache
    jc .read_fat_error
    
    ; Read new sector into cache
    mov edi, [rbx + OFFSET_FAT32_AHCI_PORT]
    mov edx, 1
    lea rcx, [rbx + OFFSET_SECTOR_BUFFER]
    mov r8b, 0
    call ahci_read_sectors
    jc .read_fat_error
    test rax, rax
    jnz .read_fat_error
    
    ; Update cache info
    mov [rbx + OFFSET_FAT32_FAT_CACHE_LBA], rsi
    mov byte [rbx + OFFSET_FAT32_FAT_CACHE_DIRTY], 0
    
.read_fat_ok:
    xor rax, rax
    clc
    jmp .done
    
.read_fat_error:
    mov qword [rbx + OFFSET_FAT32_FAT_CACHE_LBA], -1
    cmp rax, 0
    jnz .read_fat_error_ret
    mov rax, FAT_ERR_FAT_READ
    
.read_fat_error_ret:
    stc
    
.done:
    pop rsi
    pop rbx
    pop rbp
    ret

;--------------------------------------------------------------------------
; fat32_init_partition: Initialize FAT32 partition
; Input: RDI = Partition LBA, EDX = AHCI Port
; Output: RAX = 0 on success, error code otherwise, CF set on error
;--------------------------------------------------------------------------
fat32_init_partition:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push rdx
    push r12
    push r13
    
    ; Initialize FAT32 runtime data if not already done
    call init_fat32_runtime_data
    test rax, rax
    jnz .init_error
    
    ; Get FAT32 runtime data pointer
    call get_fat32_runtime_data
    mov rbx, rax  ; Save pointer in RBX
    
    ; Store partition LBA and AHCI port
    mov [rbx + OFFSET_FAT32_PARTITION_LBA], rdi
    mov [rbx + OFFSET_FAT32_AHCI_PORT], edx
    
    ; Initialize FAT32 state
    mov byte [rbx + OFFSET_FAT32_INITIALIZED], 0
    mov qword [rbx + OFFSET_FAT32_FAT_CACHE_LBA], -1
    mov byte [rbx + OFFSET_FAT32_FAT_CACHE_DIRTY], 0
    
    ; Read boot sector (BPB)
    mov esi, [rbx + OFFSET_FAT32_PARTITION_LBA]
    mov edx, 1
    lea rcx, [rbx + OFFSET_SECTOR_BUFFER]
    mov r8b, 0
    mov edi, [rbx + OFFSET_FAT32_AHCI_PORT]
    call ahci_read_sectors
    jnc .read_bpb_ok
    jmp .init_disk_error_msg
    
.read_bpb_ok:
    test rax, rax
    jnz .init_disk_error_msg
    
    ; Validate boot sector signature
    lea rsi, [rbx + OFFSET_SECTOR_BUFFER]
    cmp word [rsi + 510], 0xAA55
    jne .init_bad_bpb_msg
    
    ; Parse BPB fields
    mov ax, [rsi + FAT_BPB_BytesPerSector]
    cmp ax, 512
    jne .init_bad_bpb_msg
    mov [rbx + OFFSET_FAT32_BYTES_PER_SECTOR], ax
    
    movzx eax, byte [rsi + FAT_BPB_SectorsPerCluster]
    test al, al
    jz .init_bad_bpb_msg
    mov [rbx + OFFSET_FAT32_SECTORS_PER_CLUSTER], al
    
    mov ax, [rsi + FAT_BPB_ReservedSectors]
    cmp ax, 0
    je .init_bad_bpb_msg
    mov [rbx + OFFSET_FAT32_RESERVED_SECTORS], ax
    
    movzx eax, byte [rsi + FAT_BPB_NumberOfFATs]
    cmp al, 1
    jb .init_bad_bpb_msg
    mov [rbx + OFFSET_FAT32_NUM_FATS], al
    
    mov eax, [rsi + FAT32_BPB_SectorsPerFAT32]
    test eax, eax
    jz .init_not_fat32_msg
    mov [rbx + OFFSET_FAT32_SECTORS_PER_FAT], eax
    
    mov eax, [rsi + FAT32_BPB_RootCluster]
    cmp eax, FAT32_CLUSTER_MIN_VALID
    jb .init_bad_bpb_msg
    mov [rbx + OFFSET_FAT32_ROOT_CLUSTER], eax
    mov [rbx + OFFSET_CURRENT_DIR_CLUSTER], eax
    
    mov ax, [rsi + FAT32_BPB_FSInfo]
    mov [rbx + OFFSET_FAT32_FSINFO_SECTOR], ax
    
    ; Verify FAT32 signature
    mov rdi, rsi
    add rdi, FAT32_BPB_FSType
    lea r12, [fs_type_string_fat32]
    mov ecx, 8
    repe cmpsb
    jne .init_not_fat32_msg
    
    ; Calculate first data sector
    mov eax, [rbx + OFFSET_FAT32_SECTORS_PER_FAT]
    movzx ecx, byte [rbx + OFFSET_FAT32_NUM_FATS]
    mul ecx
    movzx ecx, word [rbx + OFFSET_FAT32_RESERVED_SECTORS]
    add eax, ecx
    mov [rbx + OFFSET_FAT32_FIRST_DATA_SECTOR], eax
    
    ; Calculate FAT LBA
    mov rax, [rbx + OFFSET_FAT32_PARTITION_LBA]
    movzx ecx, word [rbx + OFFSET_FAT32_RESERVED_SECTORS]
    add rax, rcx
    mov [rbx + OFFSET_FAT32_FAT_LBA], eax
    
    ; Calculate bytes per cluster
    movzx eax, byte [rbx + OFFSET_FAT32_SECTORS_PER_CLUSTER]
    movzx ecx, word [rbx + OFFSET_FAT32_BYTES_PER_SECTOR]
    mul ecx
    mov [rbx + OFFSET_FAT32_BYTES_PER_CLUSTER], eax
    
    ; Mark as initialized
    mov byte [rbx + OFFSET_FAT32_INITIALIZED], 1
    
    ; Print success message
    mov rsi, msg_fat32_bpb_ok
    call scr64_print_string
    
    ; Return success
    xor rax, rax
    clc
    jmp .init_done
    
.init_disk_error_msg:
    mov rsi, msg_fat32_read_err
    call scr64_print_string
    mov rax, FAT_ERR_DISK_ERROR
    stc
    jmp .init_done
    
.init_bad_bpb_msg:
    mov rsi, msg_fat32_bad_bpb
    call scr64_print_string
    mov rax, FAT_ERR_BAD_BPB
    stc
    jmp .init_done
    
.init_not_fat32_msg:
    mov rsi, msg_fat32_not_fat32
    call scr64_print_string
    mov rax, FAT_ERR_NOT_FAT32
    stc
    
.init_error:
    stc
    
.init_done:
    pop r13
    pop r12
    pop rdx
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret

;--------------------------------------------------------------------------
; cluster_to_lba: Convert cluster number to LBA
; Input: EDI = Cluster number
; Output: RAX = LBA, CF set on error
;--------------------------------------------------------------------------
cluster_to_lba:
    push rbp
    mov rbp, rsp
    push rbx
    
    ; Get FAT32 runtime data pointer
    call get_fat32_runtime_data
    mov rbx, rax  ; Save pointer in RBX
    
    ; Validate cluster number
    cmp edi, FAT32_CLUSTER_MIN_VALID
    jb .invalid_cluster_ctl
    
    ; Calculate LBA
    mov eax, edi
    sub eax, 2
    movzx ecx, byte [rbx + OFFSET_FAT32_SECTORS_PER_CLUSTER]
    mul ecx
    add eax, [rbx + OFFSET_FAT32_FIRST_DATA_SECTOR]
    add rax, [rbx + OFFSET_FAT32_PARTITION_LBA]
    clc
    jmp .done
    
.invalid_cluster_ctl:
    xor rax, rax
    stc
    
.done:
    pop rbx
    pop rbp
    ret

;--------------------------------------------------------------------------
; fat32_get_next_cluster: Get next cluster in chain
; Input: EDI = Current cluster
; Output: RAX = Next cluster or error code, CF set on error
;--------------------------------------------------------------------------
fat32_get_next_cluster:
    push rbp
    mov rbp, rsp
    push rbx
    push rdx
    push rdi
    push rsi
    
    ; Get FAT32 runtime data pointer
    call get_fat32_runtime_data
    mov rbx, rax  ; Save pointer in RBX
    
    ; Calculate FAT sector and offset
    mov esi, edi
    mov eax, esi
    shl eax, 2  ; Multiply by 4 (4 bytes per FAT entry)
    movzx ecx, word [rbx + OFFSET_FAT32_BYTES_PER_SECTOR]
    xor edx, edx
    div ecx
    
    ; Save offset in RDX
    push rdx
    
    ; Calculate FAT sector LBA
    mov rdi, rax
    add rdi, [rbx + OFFSET_FAT32_FAT_LBA]
    
    ; Read FAT sector
    call fat32_read_fat_sector
    jc .fat_op_error_exit
    
    ; Get FAT entry
    pop rdx
    lea rsi, [rbx + OFFSET_SECTOR_BUFFER]
    mov eax, [rsi + rdx]
    and eax, 0x0FFFFFFF
    
    ; Check for special values
    cmp eax, FAT32_CLUSTER_BAD
    je .fat_bad_cluster_exit
    cmp eax, FAT32_CLUSTER_EOF_MIN
    jae .fat_eof_exit
    
    ; Return next cluster
    clc
    jmp .fat_get_done
    
.fat_bad_cluster_exit:
    mov rax, FAT_ERR_BAD_CLUSTER
    stc
    jmp .fat_get_done
    
.fat_eof_exit:
    mov rax, FAT32_CLUSTER_EOF_MIN
    clc
    jmp .fat_get_done
    
.fat_op_error_exit:
    ; RAX already contains error code
    stc
    
.fat_get_done:
    pop rsi
    pop rdi
    pop rdx
    pop rbx
    pop rbp
    ret

;--------------------------------------------------------------------------
; read_cluster_chain: Read a chain of clusters
; Input: RDI = Start cluster, RSI = Buffer pointer, RDX = Bytes to read
; Output: RAX = Bytes read, RCX = Last cluster, CF set on error
;--------------------------------------------------------------------------
read_cluster_chain:
    push rbp
    mov rbp, rsp
    push rbx
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15
    
    ; Get FAT32 runtime data pointer
    call get_fat32_runtime_data
    mov rbx, rax  ; Save pointer in RBX
    
    ; Initialize variables
    mov r10, rdi  ; Current cluster
    mov r11, rsi  ; Current buffer position
    mov r12, rdx  ; Remaining bytes to read
    mov r14, 0    ; Total bytes read
    mov r15, rdi  ; Last cluster read
    
    ; Get bytes per cluster
    mov r13, [rbx + OFFSET_FAT32_BYTES_PER_CLUSTER]
    
    ; Check if there's anything to read
    test r12, r12
    jz .rcc_done_ok
    
.rcc_loop:
    ; Validate current cluster
    cmp r10d, FAT32_CLUSTER_MIN_VALID
    jb .rcc_error_bad_cluster
    
    ; Save current cluster as last read
    mov r15, r10
    
    ; Convert cluster to LBA
    mov edi, r10d
    call cluster_to_lba
    jc .rcc_error_bad_cluster
    mov r9, rax  ; Save LBA
    
    ; Calculate bytes to read from this cluster
    mov rbx, r13  ; Bytes per cluster
    cmp rbx, r12  ; Compare with remaining bytes
    cmova rbx, r12  ; Take minimum
    
    ; Calculate sectors to read
    mov rcx, rbx
    mov rax, [fat32_runtime_data_ptr + OFFSET_FAT32_BYTES_PER_SECTOR]
    dec rax
    add rcx, rax
    mov rax, rcx
    xor edx, edx
    div qword [fat32_runtime_data_ptr + OFFSET_FAT32_BYTES_PER_SECTOR]
    mov rcx, rax  ; Number of sectors
    
    ; Read sectors
    mov rdi, [fat32_runtime_data_ptr + OFFSET_FAT32_AHCI_PORT]
    mov rsi, r9  ; LBA
    mov rdx, rcx  ; Sector count
    mov rcx, r11  ; Buffer
    mov r8b, 0    ; No write
    call ahci_read_sectors
    jnc .rcc_read_ok
    jmp .rcc_error_disk
    
.rcc_read_ok:
    test rax, rax
    jnz .rcc_error_disk
    
    ; Update counters
    add r11, rbx  ; Advance buffer pointer
    sub r12, rbx  ; Decrease remaining bytes
    add r14, rbx  ; Increase total bytes read
    
    ; Check if we're done
    test r12, r12
    jz .rcc_done_ok
    
    ; Get next cluster
    mov edi, r10d
    call fat32_get_next_cluster
    jc .rcc_error_fat_read
    cmp rax, FAT32_CLUSTER_EOF_MIN
    jae .rcc_done_eof
    
    ; Continue with next cluster
    mov r10, rax
    jmp .rcc_loop
    
.rcc_done_ok:
.rcc_done_eof:
    mov rax, r14  ; Total bytes read
    mov rcx, r15  ; Last cluster read
    clc
    jmp .rcc_done
    
.rcc_error_disk:
    mov rax, FAT_ERR_DISK_ERROR
    jmp .rcc_error_common
    
.rcc_error_bad_cluster:
    mov rax, FAT_ERR_BAD_CLUSTER
    jmp .rcc_error_common
    
.rcc_error_fat_read:
    mov rax, FAT_ERR_FAT_READ
    
.rcc_error_common:
    mov rcx, r15  ; Last cluster read
    stc
    
.rcc_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop rbx
    pop rbp
    ret

;--------------------------------------------------------------------------
; fat32_read_file: Read a file from the current directory
; Input: RDI = Filename (8.3 Padded), RSI = Buffer pointer, RDX = Bytes to read
; Output: RAX = Bytes read or error code, CF set on error
;--------------------------------------------------------------------------
fat32_read_file:
    push rbp
    mov rbp, rsp
    push rbx
    push r10
    push r11
    push r12
    push r13
    push r14
    
    ; Save parameters
    mov r12, rdi  ; Filename
    mov r13, rsi  ; Buffer
    mov r14, rdx  ; Bytes to read
    
    ; Get FAT32 runtime data pointer
    call get_fat32_runtime_data
    mov rbx, rax  ; Save pointer in RBX
    
    ; Check if initialized
    cmp byte [rbx + OFFSET_FAT32_INITIALIZED], 1
    jne .read_not_init
    
    ; Find file in directory
    mov rdi, r12  ; Filename
    mov esi, [rbx + OFFSET_CURRENT_DIR_CLUSTER]  ; Current directory
    call fat32_find_entry
    jc .read_find_error
    
    ; Check if file found
    test rax, rax
    jz .read_not_found
    
    ; Get file cluster and size
    mov r10, rbx  ; First cluster
    mov r11, rcx  ; File size
    
    ; Adjust bytes to read if needed
    cmp r14, r11
    cmovb r14, r11
    
    ; Read file data
    mov rdi, r10  ; Start cluster
    mov rsi, r13  ; Buffer
    mov rdx, r14  ; Bytes to read
    call read_cluster_chain
    jc .read_chain_error
    
    ; Success
    clc
    jmp .read_done
    
.read_not_init:
    mov rax, FAT_ERR_NOT_INIT
    stc
    jmp .read_done_final
    
.read_find_error:
    ; RAX already contains error code
    stc
    jmp .read_done_final
    
.read_not_found:
    mov rax, FAT_ERR_NOT_FOUND
    stc
    jmp .read_done_final
    
.read_chain_error:
    ; RAX already contains error code
    stc
    
.read_done:
.read_done_final:
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop rbx
    pop rbp
    ret

;--------------------------------------------------------------------------
; fat32_find_entry: Find a directory entry by name
; Input: RDI = Filename (8.3 Padded), ESI = Start cluster
; Output: RAX = Entry address or 0 if not found, RBX = First cluster, RCX = File size
;         CF set on error
;--------------------------------------------------------------------------
fat32_find_entry:
    push rbp
    mov rbp, rsp
    push rdi
    push rsi
    push rdx
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15
    
    ; Get FAT32 runtime data pointer
    call get_fat32_runtime_data
    mov r15, rax  ; Save pointer in R15
    
    ; Save parameters
    mov r10, rdi  ; Filename
    mov r11, rsi  ; Start cluster
    mov r12, FAT_DIRENT_SIZE
    
.fde_cluster_loop:
    ; Validate cluster
    cmp r11d, FAT32_CLUSTER_MIN_VALID
    jb .fde_error_bad_cluster
    
    ; Convert cluster to LBA
    mov edi, r11d
    call cluster_to_lba
    jc .fde_error_bad_cluster
    mov r13, rax  ; Save LBA
    
    ; Process all sectors in cluster
    movzx rdx, byte [r15 + OFFSET_FAT32_SECTORS_PER_CLUSTER]
    
.fde_sector_loop:
    ; Check if we've processed all sectors
    test rdx, rdx
    jz .fde_next_cluster
    
    ; Read sector
    mov edi, [r15 + OFFSET_FAT32_AHCI_PORT]
    mov rsi, r13  ; LBA
    mov r8d, 1    ; One sector
    lea rcx, [r15 + OFFSET_SECTOR_BUFFER]
    mov r9b, 0    ; No write
    call ahci_read_sectors
    jnc .fde_read_ok
    jmp .fde_error_disk
    
.fde_read_ok:
    test rax, rax
    jnz .fde_error_disk
    
    ; Process entries in sector
    lea rsi, [r15 + OFFSET_SECTOR_BUFFER]
    movzx rbx, word [r15 + OFFSET_FAT32_BYTES_PER_SECTOR]
    add rbx, rsi  ; End of sector
    
.fde_entry_loop:
    ; Check if we've reached the end of the sector
    cmp rsi, rbx
    jae .fde_next_sector
    
    ; Check for end of directory or deleted entry
    mov al, [rsi + FAT_DIRENT_Name]
    test al, al
    jz .fde_not_found_ok
    cmp al, 0xE5
    je .fde_next_entry_skip
    
    ; Check if it's a long filename entry
    mov cl, [rsi + FAT_DIRENT_Attributes]
    and cl, FAT_ATTR_LFN_MASK
    cmp cl, FAT_ATTR_LONG_NAME
    je .fde_next_entry_skip
    
    ; Compare filename
    mov rdi, rsi
    mov r8, r10
    mov rcx, 11
    repe cmpsb
    je .fde_found
    
.fde_next_entry_skip:
    add rsi, r12  ; Move to next entry
    jmp .fde_entry_loop
    
.fde_next_sector:
    inc r13  ; Next sector
    dec rdx  ; Decrement sector count
    jmp .fde_sector_loop
    
.fde_next_cluster:
    ; Get next cluster
    mov edi, r11d
    call fat32_get_next_cluster
    jc .fde_error_fat
    cmp rax, FAT32_CLUSTER_EOF_MIN
    jae .fde_not_found_ok
    mov r11, rax
    jmp .fde_cluster_loop
    
.fde_found:
    ; Entry found, extract information
    mov rax, rsi  ; Entry address
    
    ; Get first cluster (combine high and low parts)
    movzx ebx, word [rsi + FAT_DIRENT_FstClusLO]
    movzx r8d, word [rsi + FAT_DIRENT_FstClusHI]
    shl r8d, 16
    or ebx, r8d
    
    ; Get file size
    mov ecx, [rsi + FAT_DIRENT_FileSize]
    
    clc
    jmp .fde_done
    
.fde_error_disk:
    mov rax, FAT_ERR_DISK_ERROR
    stc
    jmp .fde_error_common
    
.fde_error_fat:
    mov rax, FAT_ERR_FAT_READ
    stc
    jmp .fde_error_common
    
.fde_error_bad_cluster:
    mov rax, FAT_ERR_BAD_CLUSTER
    stc
    jmp .fde_error_common
    
.fde_not_found_ok:
    xor rax, rax  ; Not found
    clc
    
.fde_error_common:
    xor rbx, rbx
    xor rcx, rcx
    
.fde_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdx
    pop rsi
    pop rdi
    pop rbp
    ret

; --- Stubs for Write/Create functionality ---
fat32_write_file:
    mov rax, FAT_ERR_NOT_IMPLEMENTED
    stc
    ret
    
fat32_create_file:
    mov rax, FAT_ERR_NOT_IMPLEMENTED
    stc
    ret
    
update_fat_entry:
    mov rax, FAT_ERR_NOT_IMPLEMENTED
    stc
    ret
    
find_free_cluster:
    mov rax, FAT_ERR_NOT_IMPLEMENTED
    stc
    ret
    
allocate_cluster_chain:
    mov rax, FAT_ERR_NOT_IMPLEMENTED
    stc
    ret
    
update_dir_entry:
    mov rax, FAT_ERR_NOT_IMPLEMENTED
    stc
    ret
    
clear_cluster:
    mov rax, FAT_ERR_NOT_IMPLEMENTED
    stc
    ret

;--------------------------------------------------------------------------
; fat32_init: Initialize FAT32 driver (compatibility wrapper)
; Input: None
; Output: RAX = 0 on success, error code otherwise
;--------------------------------------------------------------------------
fat32_init:
    call init_fat32_runtime_data
    ret
