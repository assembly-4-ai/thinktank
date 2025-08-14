


; gpu_mmio.asm: Memory-Mapped I/O Interface Module
; Project Arora - Bare-Metal NVIDIA RTX 4060 Integration
; Implements direct register access and GPU control
; Follows Project Arora coding rules: custom functions, no ints, no syscalls

section .text

; External dependencies from Project Arora
extern pmm_alloc_frame
extern pmm_free_frame
extern scr64_print_string
extern shell_print_newline

; External dependencies from GPU discovery module
extern gpu_get_device_info
extern gpu_device_info
extern discovered_devices
extern gpu_device_info_size

; Global exports
global gpu_mmio_init
global gpu_mmio_read_reg32
global gpu_mmio_write_reg32
global gpu_mmio_read_reg64
global gpu_mmio_write_reg64
global gpu_mmio_map_bars
global gpu_mmio_unmap_bars
global gpu_check_device_ready
global gpu_reset_device
global gpu_enable_device

; Constants from cpu_gpu manual
GPU_DISPLAY_CORE_OFFSET equ 0x00610000
GPU_GRAPHICS_ENGINE_OFFSET equ 0x00800000
GPU_MEMORY_CONTROLLER_OFFSET equ 0x00A00000
GPU_COMMAND_PROCESSOR_OFFSET equ 0x001000
GPU_STATUS_REGISTER equ 0x00000000
GPU_CONTROL_REGISTER equ 0x00000004
GPU_RESET_REGISTER equ 0x00000008
GPU_ENABLE_REGISTER equ 0x0000000C

; Data structure for MMIO mapping
struc gpu_mmio_mapping
    .bar0_virtual_addr  resq 1
    .bar1_virtual_addr  resq 1
    .bar0_physical_addr resq 1
    .bar1_physical_addr resq 1
    .bar0_size          resq 1
    .bar1_size          resq 1
    .mapping_valid      resq 1
endstruc

gpu_mmio_init:
    ; Initialize MMIO interface for specified GPU device
    ; Input: RDI = device index
    ; Output: RAX = 0 on success, error code on failure
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    push r12
    
    ; Save device index
    mov r12, rdi
    
    ; Get device information
    mov rdi, r12
    mov rsi, discovered_devices
    call gpu_get_device_info
    
    ; Check if device is valid
    test rax, rax
    jz .init_error
    
    ; Save device info pointer
    mov rbx, rax
    
    ; Map BARs into virtual memory
    mov rdi, rbx
    call gpu_mmio_map_bars
    
    ; Check mapping result
    test rax, rax
    jnz .init_error
    
    ; Verify device is accessible
    mov rdi, r12
    call gpu_check_device_ready
    
    ; Check device ready result
    test rax, rax
    jnz .init_error
    
    ; Success
    xor rax, rax
    jmp .init_complete
    
.init_error:
    ; Return error code
    mov rax, 1
    
.init_complete:
    pop r12
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_mmio_map_bars:
    ; Map GPU Base Address Registers into virtual memory space
    ; Input: RDI = pointer to device info structure
    ; Output: RAX = 0 on success, error code on failure
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    push r12
    push r13
    
    ; Save device info pointer
    mov r12, rdi
    
    ; Get BAR0 physical address and size
    mov rax, [r12 + gpu_device_info.bar0_address]
    mov rbx, [r12 + gpu_device_info.bar0_size]
    
    ; Verify BAR0 is valid
    test rax, rax
    jz .mapping_error
    test rbx, rbx
    jz .mapping_error
    
    ; Calculate number of pages needed for BAR0
    add rbx, 0xFFF                  ; Round up to page boundary
    shr rbx, 12                     ; Convert to page count
    
    ; Allocate virtual memory for BAR0 mapping
    mov rdi, rbx                    ; Number of pages
    call pmm_alloc_frame
    
    ; Check allocation result
    test rax, rax
    jz .mapping_error
    
    ; Store BAR0 virtual address
    mov [mmio_mapping + gpu_mmio_mapping.bar0_virtual_addr], rax
    mov rcx, [r12 + gpu_device_info.bar0_address]
    mov [mmio_mapping + gpu_mmio_mapping.bar0_physical_addr], rcx
    mov rcx, [r12 + gpu_device_info.bar0_size]
    mov [mmio_mapping + gpu_mmio_mapping.bar0_size], rcx
    
    ; Get BAR1 physical address and size
    mov rax, [r12 + gpu_device_info.bar1_address]
    mov rbx, [r12 + gpu_device_info.bar1_size]
    
    ; Verify BAR1 is valid
    test rax, rax
    jz .mapping_error
    test rbx, rbx
    jz .mapping_error
    
    ; Calculate number of pages needed for BAR1
    add rbx, 0xFFF                  ; Round up to page boundary
    shr rbx, 12                     ; Convert to page count
    
    ; Allocate virtual memory for BAR1 mapping
    mov rdi, rbx                    ; Number of pages
    call pmm_alloc_frame
    
    ; Check allocation result
    test rax, rax
    jz .mapping_error
    
    ; Store BAR1 virtual address
    mov [mmio_mapping + gpu_mmio_mapping.bar1_virtual_addr], rax
    mov rcx, [r12 + gpu_device_info.bar1_address]
    mov [mmio_mapping + gpu_mmio_mapping.bar1_physical_addr], rcx
    mov rcx, [r12 + gpu_device_info.bar1_size]
    mov [mmio_mapping + gpu_mmio_mapping.bar1_size], rcx
    
    ; Mark mapping as valid
    mov qword [mmio_mapping + gpu_mmio_mapping.mapping_valid], 1
    
    ; Success
    xor rax, rax
    jmp .mapping_complete
    
.mapping_error:
    ; Clean up any partial mappings
    call gpu_mmio_unmap_bars
    
    ; Return error code
    mov rax, 1
    
.mapping_complete:
    pop r13
    pop r12
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_mmio_unmap_bars:
    ; Unmap GPU Base Address Registers from virtual memory
    ; Input: None
    ; Output: None
    
    push rbp
    mov rbp, rsp
    push rax
    push rdi
    
    ; Check if mapping is valid
    cmp qword [mmio_mapping + gpu_mmio_mapping.mapping_valid], 1
    jne .unmap_complete
    
    ; Free BAR0 virtual memory
    mov rax, [mmio_mapping + gpu_mmio_mapping.bar0_virtual_addr]
    test rax, rax
    jz .unmap_bar1
    
    mov rdi, rax
    call pmm_free_frame
    
    ; Clear BAR0 mapping
    mov qword [mmio_mapping + gpu_mmio_mapping.bar0_virtual_addr], 0
    
.unmap_bar1:
    ; Free BAR1 virtual memory
    mov rax, [mmio_mapping + gpu_mmio_mapping.bar1_virtual_addr]
    test rax, rax
    jz .clear_mapping
    
    mov rdi, rax
    call pmm_free_frame
    
    ; Clear BAR1 mapping
    mov qword [mmio_mapping + gpu_mmio_mapping.bar1_virtual_addr], 0
    
.clear_mapping:
    ; Mark mapping as invalid
    mov qword [mmio_mapping + gpu_mmio_mapping.mapping_valid], 0
    
.unmap_complete:
    pop rdi
    pop rax
    pop rbp
    ret

gpu_mmio_read_reg32:
    ; Read a 32-bit value from GPU register
    ; Input: RDI = register offset from BAR0
    ; Output: EAX = 32-bit register value
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    
    ; Verify mapping is valid
    cmp qword [mmio_mapping + gpu_mmio_mapping.mapping_valid], 1
    jne .read_error
    
    ; Calculate virtual address
    mov rbx, [mmio_mapping + gpu_mmio_mapping.bar0_virtual_addr]
    add rbx, rdi
    
    ; Verify offset is within BAR0 bounds
    mov rcx, [mmio_mapping + gpu_mmio_mapping.bar0_size]
    cmp rdi, rcx
    jge .read_error
    
    ; Read 32-bit value with memory barrier
    mfence
    mov eax, [rbx]
    mfence
    
    jmp .read_complete
    
.read_error:
    ; Return error value
    mov eax, 0xFFFFFFFF
    
.read_complete:
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_mmio_write_reg32:
    ; Write a 32-bit value to GPU register
    ; Input: RDI = register offset from BAR0
    ; Input: ESI = 32-bit value to write
    ; Output: None
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    
    ; Verify mapping is valid
    cmp qword [mmio_mapping + gpu_mmio_mapping.mapping_valid], 1
    jne .write_complete
    
    ; Calculate virtual address
    mov rbx, [mmio_mapping + gpu_mmio_mapping.bar0_virtual_addr]
    add rbx, rdi
    
    ; Verify offset is within BAR0 bounds
    mov rcx, [mmio_mapping + gpu_mmio_mapping.bar0_size]
    cmp rdi, rcx
    jge .write_complete
    
    ; Write 32-bit value with memory barrier
    mfence
    mov [rbx], esi
    mfence
    
.write_complete:
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_mmio_read_reg64:
    ; Read a 64-bit value from GPU register
    ; Input: RDI = register offset from BAR0
    ; Output: RAX = 64-bit register value
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    
    ; Verify mapping is valid
    cmp qword [mmio_mapping + gpu_mmio_mapping.mapping_valid], 1
    jne .read_error
    
    ; Calculate virtual address
    mov rbx, [mmio_mapping + gpu_mmio_mapping.bar0_virtual_addr]
    add rbx, rdi
    
    ; Verify offset is within BAR0 bounds
    mov rcx, [mmio_mapping + gpu_mmio_mapping.bar0_size]
    cmp rdi, rcx
    jge .read_error
    
    ; Read 64-bit value with memory barrier
    mfence
    mov rax, [rbx]
    mfence
    
    jmp .read_complete
    
.read_error:
    ; Return error value
    mov rax, 0xFFFFFFFFFFFFFFFF
    
.read_complete:
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_mmio_write_reg64:
    ; Write a 64-bit value to GPU register
    ; Input: RDI = register offset from BAR0
    ; Input: RSI = 64-bit value to write
    ; Output: None
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    
    ; Verify mapping is valid
    cmp qword [mmio_mapping + gpu_mmio_mapping.mapping_valid], 1
    jne .write_complete
    
    ; Calculate virtual address
    mov rbx, [mmio_mapping + gpu_mmio_mapping.bar0_virtual_addr]
    add rbx, rdi
    
    ; Verify offset is within BAR0 bounds
    mov rcx, [mmio_mapping + gpu_mmio_mapping.bar0_size]
    cmp rdi, rcx
    jge .write_complete
    
    ; Write 64-bit value with memory barrier
    mfence
    mov [rbx], rsi
    mfence
    
.write_complete:
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_check_device_ready:
    ; Check if GPU device is ready for operation
    ; Input: RDI = device index
    ; Output: RAX = 0 if ready, error code if not ready
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    
    ; Read GPU status register
    mov rdi, GPU_STATUS_REGISTER
    call gpu_mmio_read_reg32
    
    ; Check if device is responding
    cmp eax, 0xFFFFFFFF
    je .device_not_ready
    
    ; Check ready bit (assuming bit 0 indicates ready)
    test eax, 1
    jz .device_not_ready
    
    ; Device is ready
    xor rax, rax
    jmp .check_complete
    
.device_not_ready:
    ; Device is not ready
    mov rax, 1
    
.check_complete:
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_reset_device:
    ; Reset GPU device to initial state
    ; Input: RDI = device index
    ; Output: RAX = 0 on success, error code on failure
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    
    ; Write reset command to reset register
    mov rdi, GPU_RESET_REGISTER
    mov esi, 1                      ; Reset bit
    call gpu_mmio_write_reg32
    
    ; Wait for reset to complete (simple delay loop)
    mov rcx, 1000000                ; Delay counter
    
.reset_wait_loop:
    ; Check if reset is complete
    mov rdi, GPU_STATUS_REGISTER
    call gpu_mmio_read_reg32
    
    ; Check reset complete bit (assuming bit 1 indicates reset complete)
    test eax, 2
    jnz .reset_complete
    
    ; Decrement counter and continue waiting
    dec rcx
    jnz .reset_wait_loop
    
    ; Reset timeout
    mov rax, 1
    jmp .reset_done
    
.reset_complete:
    ; Clear reset bit
    mov rdi, GPU_RESET_REGISTER
    mov esi, 0
    call gpu_mmio_write_reg32
    
    ; Success
    xor rax, rax
    
.reset_done:
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_enable_device:
    ; Enable GPU device for operation
    ; Input: RDI = device index
    ; Output: RAX = 0 on success, error code on failure
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    
    ; Write enable command to control register
    mov rdi, GPU_CONTROL_REGISTER
    call gpu_mmio_read_reg32
    
    ; Set enable bit (bit 0)
    or eax, 1
    
    ; Write back to control register
    mov rdi, GPU_CONTROL_REGISTER
    mov esi, eax
    call gpu_mmio_write_reg32
    
    ; Verify device is enabled
    mov rdi, GPU_STATUS_REGISTER
    call gpu_mmio_read_reg32
    
    ; Check enabled bit (assuming bit 0 indicates enabled)
    test eax, 1
    jz .enable_failed
    
    ; Success
    xor rax, rax
    jmp .enable_complete
    
.enable_failed:
    ; Enable failed
    mov rax, 1
    
.enable_complete:
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

; Data section
section .data
    mmio_init_msg db 'GPU MMIO: Initializing memory-mapped I/O interface...', 0
    mmio_map_msg db 'GPU MMIO: Mapping BARs into virtual memory...', 0
    mmio_ready_msg db 'GPU MMIO: Device ready for operation', 0
    mmio_error_msg db 'GPU MMIO: Error during initialization', 0

; BSS section
section .bss
    ; MMIO mapping information
    mmio_mapping resb gpu_mmio_mapping_size




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


