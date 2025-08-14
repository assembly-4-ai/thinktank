; gpu_discovery.asm: GPU Discovery and Enumeration Module
; Project Arora - Bare-Metal NVIDIA RTX 4060 Integration
; Implements PCI bus scanning and GPU device identification
; Follows Project Arora coding rules: custom functions, no ints, no syscalls

section .text

; External dependencies from Project Arora
extern pmm_alloc_frame
extern pmm_free_frame
extern scr64_print_string
extern shell_print_newline
extern string_to_hex
extern hex_to_string

; Global exports
global gpu_discover_devices
global gpu_enumerate_pci_bus
global gpu_read_pci_config
global gpu_write_pci_config
global gpu_map_bars
global gpu_get_device_info

; Constants
NVIDIA_VENDOR_ID equ 0x10DE
RTX_4060_DEVICE_ID_1 equ 0x2882
RTX_4060_DEVICE_ID_2 equ 0x2883
PCI_CONFIG_ADDRESS equ 0xCF8
PCI_CONFIG_DATA equ 0xCFC

; Data structures
global gpu_device_info
struc gpu_device_info
    .vendor_id      resq 1
    .device_id      resq 1
    .bus_number     resq 1
    .device_number  resq 1
    .function_number resq 1
    .bar0_address   resq 1
    .bar1_address   resq 1
    .bar0_size      resq 1
    .bar1_size      resq 1
    .irq_line       resq 1
    .device_status  resq 1
endstruc

gpu_discover_devices:
    ; Discover and enumerate all NVIDIA RTX 4060 devices on PCI bus
    ; Input: RDI = pointer to device info array
    ; Input: RSI = maximum number of devices to find
    ; Output: RAX = number of devices found
    ; Output: Device info array populated with found devices
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push r12
    push r13
    push r14
    push r15
    
    ; Initialize variables
    mov r12, rdi                    ; Device info array pointer
    mov r13, rsi                    ; Maximum devices to find
    xor r14, r14                    ; Device count found
    xor r15, r15                    ; Current bus number
    
.bus_loop:
    ; Check if we've scanned all buses
    cmp r15, 256
    jge .discovery_complete
    
    ; Scan current bus
    mov rdi, r15                    ; Bus number
    mov rsi, r12                    ; Device info array
    mov rdx, r13                    ; Max devices
    mov rcx, r14                    ; Current device count
    call gpu_scan_pci_bus
    
    ; Update device count
    add r14, rax
    
    ; Check if we've found maximum devices
    cmp r14, r13
    jge .discovery_complete
    
    ; Move to next bus
    inc r15
    jmp .bus_loop
    
.discovery_complete:
    ; Return number of devices found
    mov rax, r14
    
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_scan_pci_bus:
    ; Scan a single PCI bus for NVIDIA RTX 4060 devices
    ; Input: RDI = bus number
    ; Input: RSI = device info array pointer
    ; Input: RDX = maximum devices to find
    ; Input: RCX = current device count
    ; Output: RAX = number of new devices found on this bus
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push r12
    push r13
    push r14
    push r15
    
    ; Save parameters
    mov r12, rdi                    ; Bus number
    mov r13, rsi                    ; Device info array
    mov r14, rdx                    ; Max devices
    mov r15, rcx                    ; Current device count
    xor rbx, rbx                    ; Device number (0-31)
    xor rcx, rcx                    ; New devices found
    
.device_loop:
    ; Check if we've scanned all devices on this bus
    cmp rbx, 32
    jge .bus_scan_complete
    
    ; Scan all functions for this device
    xor rdx, rdx                    ; Function number (0-7)
    
.function_loop:
    ; Check if we've scanned all functions
    cmp rdx, 8
    jge .next_device
    
    ; Read vendor ID to check if device exists
    mov rdi, r12                    ; Bus number
    mov rsi, rbx                    ; Device number
    mov r8, rdx                     ; Function number
    mov r9, 0                       ; Offset 0 (Vendor ID)
    call gpu_read_pci_config_dword
    
    ; Check if device exists (vendor ID != 0xFFFF)
    cmp eax, 0xFFFFFFFF
    je .next_function
    
    ; Extract vendor ID (lower 16 bits)
    and eax, 0xFFFF
    
    ; Check if this is an NVIDIA device
    cmp eax, NVIDIA_VENDOR_ID
    jne .next_function
    
    ; Read device ID
    mov rdi, r12                    ; Bus number
    mov rsi, rbx                    ; Device number
    mov r8, rdx                     ; Function number
    mov r9, 0                       ; Offset 0 (Vendor/Device ID)
    call gpu_read_pci_config_dword
    
    ; Extract device ID (upper 16 bits)
    shr eax, 16
    
    ; Check if this is an RTX 4060
    cmp eax, RTX_4060_DEVICE_ID_1
    je .found_rtx_4060
    cmp eax, RTX_4060_DEVICE_ID_2
    je .found_rtx_4060
    jmp .next_function
    
.found_rtx_4060:
    ; Check if we have space for another device
    cmp r15, r14
    jge .bus_scan_complete
    
    ; Calculate device info structure offset
    mov rdi, r15
    imul rdi, gpu_device_info_size
    add rdi, r13                    ; Device info array base
    
    ; Populate device information
    call gpu_populate_device_info
    
    ; Increment counters
    inc r15                         ; Total device count
    inc rcx                         ; New devices found
    
.next_function:
    inc rdx
    jmp .function_loop
    
.next_device:
    inc rbx
    jmp .device_loop
    
.bus_scan_complete:
    ; Return number of new devices found
    mov rax, rcx
    
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_populate_device_info:
    ; Populate device information structure for discovered RTX 4060
    ; Input: RDI = pointer to device info structure
    ; Input: R12 = bus number, RBX = device number, RDX = function number
    ; Output: Device info structure populated
    
    push rbp
    mov rbp, rsp
    push rax
    push rcx
    push rsi
    push r8
    push r9
    
    ; Save device info pointer
    mov rsi, rdi
    
    ; Store bus/device/function numbers
    mov [rsi + gpu_device_info.bus_number], r12
    mov [rsi + gpu_device_info.device_number], rbx
    mov [rsi + gpu_device_info.function_number], rdx
    
    ; Read and store vendor/device ID
    mov rdi, r12                    ; Bus number
    mov r8, rbx                     ; Device number
    mov r9, rdx                     ; Function number
    mov rcx, 0                      ; Offset 0
    call gpu_read_pci_config_dword
    
    ; Store vendor ID (lower 16 bits)
    mov rcx, rax
    and rcx, 0xFFFF
    mov [rsi + gpu_device_info.vendor_id], rcx
    
    ; Store device ID (upper 16 bits)
    shr rax, 16
    mov [rsi + gpu_device_info.device_id], rax
    
    ; Read BAR0 (Base Address Register 0)
    mov rdi, r12                    ; Bus number
    mov r8, rbx                     ; Device number
    mov r9, rdx                     ; Function number
    mov rcx, 0x10                   ; Offset 0x10 (BAR0)
    call gpu_read_pci_config_dword
    
    ; Store BAR0 address (mask off lower bits)
    and rax, 0xFFFFFFF0
    mov [rsi + gpu_device_info.bar0_address], rax
    
    ; Read BAR1 (Base Address Register 1)
    mov rdi, r12                    ; Bus number
    mov r8, rbx                     ; Device number
    mov r9, rdx                     ; Function number
    mov rcx, 0x14                   ; Offset 0x14 (BAR1)
    call gpu_read_pci_config_dword
    
    ; Store BAR1 address (mask off lower bits)
    and rax, 0xFFFFFFF0
    mov [rsi + gpu_device_info.bar1_address], rax
    
    ; Read interrupt line
    mov rdi, r12                    ; Bus number
    mov r8, rbx                     ; Device number
    mov r9, rdx                     ; Function number
    mov rcx, 0x3C                   ; Offset 0x3C (Interrupt Line)
    call gpu_read_pci_config_dword
    
    ; Store interrupt line (lower 8 bits)
    and rax, 0xFF
    mov [rsi + gpu_device_info.irq_line], rax
    
    ; Determine BAR sizes by writing all 1s and reading back
    call gpu_determine_bar_sizes
    
    ; Set device status to discovered
    mov qword [rsi + gpu_device_info.device_status], 1
    
    pop r9
    pop r8
    pop rsi
    pop rcx
    pop rax
    pop rbp
    ret

gpu_determine_bar_sizes:
    ; Determine the size of BAR0 and BAR1 by writing all 1s
    ; Input: RSI = device info structure pointer
    ; Input: R12 = bus, RBX = device, RDX = function
    ; Output: BAR sizes stored in device info structure
    
    push rbp
    mov rbp, rsp
    push rax
    push rcx
    push rdi
    push r8
    push r9
    
    ; Save original BAR0 value
    mov rax, [rsi + gpu_device_info.bar0_address]
    push rax
    
    ; Write all 1s to BAR0
    mov rdi, r12                    ; Bus number
    mov r8, rbx                     ; Device number
    mov r9, rdx                     ; Function number
    mov rcx, 0x10                   ; Offset 0x10 (BAR0)
    mov rax, 0xFFFFFFFF
    call gpu_write_pci_config_dword
    
    ; Read back to determine size
    mov rdi, r12                    ; Bus number
    mov r8, rbx                     ; Device number
    mov r9, rdx                     ; Function number
    mov rcx, 0x10                   ; Offset 0x10 (BAR0)
    call gpu_read_pci_config_dword
    
    ; Calculate BAR0 size
    and rax, 0xFFFFFFF0             ; Mask off lower bits
    not rax                         ; Invert bits
    inc rax                         ; Add 1 to get size
    mov [rsi + gpu_device_info.bar0_size], rax
    
    ; Restore original BAR0 value
    pop rax
    mov rdi, r12                    ; Bus number
    mov r8, rbx                     ; Device number
    mov r9, rdx                     ; Function number
    mov rcx, 0x10                   ; Offset 0x10 (BAR0)
    call gpu_write_pci_config_dword
    
    ; Save original BAR1 value
    mov rax, [rsi + gpu_device_info.bar1_address]
    push rax
    
    ; Write all 1s to BAR1
    mov rdi, r12                    ; Bus number
    mov r8, rbx                     ; Device number
    mov r9, rdx                     ; Function number
    mov rcx, 0x14                   ; Offset 0x14 (BAR1)
    mov rax, 0xFFFFFFFF
    call gpu_write_pci_config_dword
    
    ; Read back to determine size
    mov rdi, r12                    ; Bus number
    mov r8, rbx                     ; Device number
    mov r9, rdx                     ; Function number
    mov rcx, 0x14                   ; Offset 0x14 (BAR1)
    call gpu_read_pci_config_dword
    
    ; Calculate BAR1 size
    and rax, 0xFFFFFFF0             ; Mask off lower bits
    not rax                         ; Invert bits
    inc rax                         ; Add 1 to get size
    mov [rsi + gpu_device_info.bar1_size], rax
    
    ; Restore original BAR1 value
    pop rax
    mov rdi, r12                    ; Bus number
    mov r8, rbx                     ; Device number
    mov r9, rdx                     ; Function number
    mov rcx, 0x14                   ; Offset 0x14 (BAR1)
    call gpu_write_pci_config_dword
    
    pop r9
    pop r8
    pop rdi
    pop rcx
    pop rax
    pop rbp
    ret

gpu_read_pci_config_dword:
    ; Read a 32-bit value from PCI configuration space
    ; Input: RDI = bus number
    ; Input: RSI = device number  
    ; Input: R8 = function number
    ; Input: R9 = register offset
    ; Output: EAX = 32-bit configuration value
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    
    ; Build PCI configuration address
    ; Format: 1 | (bus << 16) | (device << 11) | (function << 8) | (offset & 0xFC)
    mov eax, 0x80000000             ; Enable bit
    
    ; Add bus number (bits 23-16)
    shl rdi, 16
    or rax, rdi
    
    ; Add device number (bits 15-11)
    shl rsi, 11
    or rax, rsi
    
    ; Add function number (bits 10-8)
    shl r8, 8
    or rax, r8
    
    ; Add register offset (bits 7-2, must be DWORD aligned)
    and r9, 0xFC
    or rax, r9
    
    ; Write address to CONFIG_ADDRESS port
    mov dx, PCI_CONFIG_ADDRESS
    out dx, eax
    
    ; Read data from CONFIG_DATA port
    mov dx, PCI_CONFIG_DATA
    in eax, dx
    
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_write_pci_config_dword:
    ; Write a 32-bit value to PCI configuration space
    ; Input: RDI = bus number
    ; Input: RSI = device number
    ; Input: R8 = function number
    ; Input: R9 = register offset
    ; Input: RAX = 32-bit value to write
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push r10
    
    ; Save value to write
    mov r10, rax
    
    ; Build PCI configuration address
    mov eax, 0x80000000             ; Enable bit
    
    ; Add bus number (bits 23-16)
    shl rdi, 16
    or rax, rdi
    
    ; Add device number (bits 15-11)
    shl rsi, 11
    or rax, rsi
    
    ; Add function number (bits 10-8)
    shl r8, 8
    or rax, r8
    
    ; Add register offset (bits 7-2, must be DWORD aligned)
    and r9, 0xFC
    or rax, r9
    
    ; Write address to CONFIG_ADDRESS port
    mov dx, PCI_CONFIG_ADDRESS
    out dx, eax
    
    ; Write data to CONFIG_DATA port
    mov dx, PCI_CONFIG_DATA
    mov eax, r10d
    out dx, eax
    
    pop r10
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_map_bars:
    ; Map GPU Base Address Registers into virtual memory
    ; Input: RDI = pointer to device info structure
    ; Output: RAX = 0 on success, error code on failure
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    
    ; Save device info pointer
    mov rbx, rdi
    
    ; Enable memory space and bus mastering in PCI command register
    mov rdi, [rbx + gpu_device_info.bus_number]
    mov rsi, [rbx + gpu_device_info.device_number]
    mov r8, [rbx + gpu_device_info.function_number]
    mov r9, 0x04                    ; PCI Command Register offset
    call gpu_read_pci_config_dword
    
    ; Set memory space enable (bit 1) and bus master enable (bit 2)
    or eax, 0x06
    
    ; Write back to command register
    mov rdi, [rbx + gpu_device_info.bus_number]
    mov rsi, [rbx + gpu_device_info.device_number]
    mov r8, [rbx + gpu_device_info.function_number]
    mov r9, 0x04                    ; PCI Command Register offset
    call gpu_write_pci_config_dword
    
    ; BAR mapping is handled by the memory management system
    ; For now, we just verify the BARs are properly configured
    
    ; Check if BAR0 is valid
    mov rax, [rbx + gpu_device_info.bar0_address]
    test rax, rax
    jz .mapping_error
    
    ; Check if BAR1 is valid
    mov rax, [rbx + gpu_device_info.bar1_address]
    test rax, rax
    jz .mapping_error
    
    ; Success
    xor rax, rax
    jmp .mapping_complete
    
.mapping_error:
    ; Return error code
    mov rax, 1
    
.mapping_complete:
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_get_device_info:
    ; Get device information for a specific device index
    ; Input: RDI = device index
    ; Input: RSI = pointer to device info array
    ; Output: RAX = pointer to device info structure, or 0 if invalid index
    
    push rbp
    mov rbp, rsp
    
    ; Calculate offset into device info array
    imul rdi, gpu_device_info_size
    add rax, rsi
    
    ; Verify device is valid by checking status
    cmp qword [rax + gpu_device_info.device_status], 1
    je .device_valid
    
    ; Invalid device
    xor rax, rax
    
.device_valid:
    pop rbp
    ret

; Data section
section .data
    gpu_discovery_msg db 'GPU Discovery: Scanning PCI bus for NVIDIA RTX 4060...', 0
    gpu_found_msg db 'GPU Found: RTX 4060 at Bus ', 0
    gpu_device_msg db ', Device ', 0
    gpu_function_msg db ', Function ', 0
    gpu_bar0_msg db ' BAR0: ', 0
    gpu_bar1_msg db ' BAR1: ', 0
    gpu_irq_msg db ' IRQ: ', 0
    gpu_newline db 10, 0

section .bss
    ; Reserve space for discovered devices (max 8 devices)
    global discovered_devices
discovered_devices resb gpu_device_info_size * 8
    device_count resq 1

